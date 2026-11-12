import Foundation

/// Little-endian byte reader for BLE GATT payloads.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var index = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    var remaining: Int { bytes.count - index }

    mutating func u8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { index += 1 }
        return bytes[index]
    }

    mutating func u16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        defer { index += 2 }
        return UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    mutating func s16() -> Int16? {
        u16().map { Int16(bitPattern: $0) }
    }

    mutating func u24() -> UInt32? {
        guard remaining >= 3 else { return nil }
        defer { index += 3 }
        return UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8) | (UInt32(bytes[index + 2]) << 16)
    }

    mutating func u32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { index += 4 }
        return UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16) | (UInt32(bytes[index + 3]) << 24)
    }

    mutating func skip(_ n: Int) { index = min(bytes.count, index + n) }
}

/// Fields from FTMS Indoor Bike Data (0x2AD2). Nil means "not present in this packet".
struct IndoorBikeData {
    var speed: Double?        // km/h
    var cadence: Double?      // rpm
    var distance: Int?        // m (total since console start)
    var resistance: Double?
    var power: Int?           // W
    var kcal: Int?            // total kcal since console start
    var heartRate: Int?
    var elapsed: Int?         // s
}

enum Parsers {
    /// FTMS Indoor Bike Data, Bluetooth FTMS spec 4.9
    static func indoorBike(_ data: Data) -> IndoorBikeData {
        var r = ByteReader(data)
        var o = IndoorBikeData()
        guard let flags = r.u16() else { return o }
        func has(_ bit: Int) -> Bool { (flags >> bit) & 1 == 1 }

        if !has(0) { o.speed = r.u16().map { Double($0) / 100 } }      // instantaneous speed
        if has(1) { r.skip(2) }                                         // average speed
        if has(2) { o.cadence = r.u16().map { Double($0) / 2 } }        // instantaneous cadence
        if has(3) { r.skip(2) }                                         // average cadence
        if has(4) { o.distance = r.u24().map { Int($0) } }              // total distance
        if has(5) { o.resistance = r.s16().map { Double($0) } }         // resistance level
        if has(6) { o.power = r.s16().map { Int($0) } }                 // instantaneous power
        if has(7) { r.skip(2) }                                         // average power
        if has(8) {                                                     // expended energy
            if let k = r.u16(), k != 0xFFFF { o.kcal = Int(k) }
            r.skip(3)
        }
        if has(9) { if let h = r.u8(), h > 0 { o.heartRate = Int(h) } }
        if has(10) { r.skip(1) }                                        // metabolic equivalent
        if has(11) { o.elapsed = r.u16().map { Int($0) } }
        return o
    }

    /// Heart Rate Measurement (0x2A37)
    static func heartRate(_ data: Data) -> Int? {
        var r = ByteReader(data)
        guard let flags = r.u8() else { return nil }
        if flags & 1 == 1 { return r.u16().map { Int($0) } }
        return r.u8().map { Int($0) }
    }

    /// Cycling Power Measurement (0x2A63): flags(2) + instantaneous power(sint16)
    static func cyclingPower(_ data: Data) -> Int? {
        var r = ByteReader(data)
        guard r.u16() != nil else { return nil }
        return r.s16().map { Int($0) }
    }

    /// FTMS Supported Resistance Level Range (0x2AD6)
    static func resistanceRange(_ data: Data) -> ClosedRange<Double>? {
        var r = ByteReader(data)
        guard let lo = r.s16(), let hi = r.s16(), hi >= lo else { return nil }
        return Double(lo) / 10 ... Double(hi) / 10
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
