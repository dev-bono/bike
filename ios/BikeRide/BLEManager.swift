import CoreBluetooth
import Foundation

struct LiveMetrics {
    var speed: Double?
    var cadence: Double?
    var power: Int?
    var heartRate: Int?
    var resistance: Double?
    var deviceDistance: Int?
    var deviceKcal: Int?
}

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var isFitness: Bool
}

enum GATT {
    static let ftms = CBUUID(string: "1826")
    static let csc = CBUUID(string: "1816")
    static let cps = CBUUID(string: "1818")
    static let hr = CBUUID(string: "180D")
    static let deviceInfo = CBUUID(string: "180A")

    static let indoorBikeData = CBUUID(string: "2AD2")
    static let ftmsControlPoint = CBUUID(string: "2AD9")
    static let ftmsStatus = CBUUID(string: "2ADA")
    static let resistanceRange = CBUUID(string: "2AD6")
    static let cscMeasurement = CBUUID(string: "2A5B")
    static let cyclingPower = CBUUID(string: "2A63")
    static let heartRate = CBUUID(string: "2A37")
}

final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var status = "연결 안 됨"
    @Published private(set) var live = LiveMetrics()
    @Published private(set) var canControlResistance = false
    @Published private(set) var resistanceRange: ClosedRange<Double>?
    @Published private(set) var logLines: [String] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlPoint: CBCharacteristic?
    private var userDisconnected = false

    // CSC state
    private var lastCrank: (revs: UInt16, time: UInt16)?
    private var lastWheel: (revs: UInt32, time: UInt16)?
    private var lastCrankMove = Date.distantPast

    private let lastDeviceKey = "lastDeviceID"

    var isConnected: Bool { connectedName != nil }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Public

    func startScan() {
        guard central.state == .poweredOn else { return }
        devices.removeAll()
        isScanning = true
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log("검색 시작")
    }

    func stopScan() {
        if central.state == .poweredOn { central.stopScan() }
        isScanning = false
    }

    func connect(_ device: DiscoveredDevice) {
        stopScan()
        userDisconnected = false
        if let p = peripheral, p.identifier != device.id { central.cancelPeripheralConnection(p) }
        peripheral = device.peripheral
        device.peripheral.delegate = self
        status = "연결 중…"
        log("연결 시도: \(device.name)")
        central.connect(device.peripheral)
    }

    func disconnect() {
        userDisconnected = true
        UserDefaults.standard.removeObject(forKey: lastDeviceKey)
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    func setResistance(_ level: Double) {
        var v = level
        if let r = resistanceRange { v = min(max(v, r.lowerBound), r.upperBound) }
        v = max(0, v)
        live.resistance = v
        // Set Target Resistance Level (0x04), UINT8, resolution 0.1
        writeControl([0x04, UInt8(min(255, (v * 10).rounded()))])
    }

    func sendStart() { writeControl([0x07]) }
    func sendPause() { writeControl([0x08, 0x02]) }
    func sendStop() { writeControl([0x08, 0x01]) }

    func clearLog() { logLines.removeAll() }

    // MARK: - Private

    private func writeControl(_ bytes: [UInt8]) {
        guard let p = peripheral, let cp = controlPoint else { return }
        let type: CBCharacteristicWriteType = cp.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(Data(bytes), for: cp, type: type)
        log("FTMS CP ⇒ " + Parsers.hex(Data(bytes)))
    }

    fileprivate func log(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        logLines.append("[\(f.string(from: Date()))] \(s)")
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    private func resetLive() {
        live = LiveMetrics()
        lastCrank = nil
        lastWheel = nil
        canControlResistance = false
        controlPoint = nil
    }

    private func reconnectLastDevice() {
        guard let s = UserDefaults.standard.string(forKey: lastDeviceKey), let id = UUID(uuidString: s),
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = p
        p.delegate = self
        status = "이전 기기에 연결 중…"
        log("이전 기기 자동 연결: \(p.name ?? id.uuidString)")
        central.connect(p)
    }

    private func handleCSC(_ data: Data) {
        var r = ByteReader(data)
        guard let flags = r.u8() else { return }
        if flags & 1 == 1, let revs = r.u32(), let t = r.u16() {
            if let last = lastWheel {
                let dr = revs &- last.revs
                let dt = Double(t &- last.time) / 1024
                if dt > 0 { live.speed = Double(dr) * 2.105 / dt * 3.6 }
            }
            lastWheel = (revs, t)
        }
        if flags & 2 == 2, let revs = r.u16(), let t = r.u16() {
            if let last = lastCrank {
                let dr = revs &- last.revs
                let dt = Double(t &- last.time) / 1024
                if dt > 0, dr > 0 {
                    live.cadence = Double(dr) / dt * 60
                    lastCrankMove = Date()
                } else if Date().timeIntervalSince(lastCrankMove) > 3 {
                    live.cadence = 0
                }
            }
            lastCrank = (revs, t)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        switch central.state {
        case .poweredOn:
            log("블루투스 켜짐")
            if peripheral == nil { reconnectLastDevice() }
        case .unauthorized: status = "블루투스 권한 없음 (설정에서 허용)"
        case .poweredOff: status = "블루투스 꺼짐"
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name = advName ?? peripheral.name, !name.isEmpty else { return }
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isFitness = services.contains(GATT.ftms) || services.contains(GATT.csc)
            || name.uppercased().contains("EXCIDER")
        let d = DiscoveredDevice(id: peripheral.identifier, peripheral: peripheral, name: name,
                                 rssi: RSSI.intValue, isFitness: isFitness)
        if let i = devices.firstIndex(where: { $0.id == d.id }) {
            devices[i] = d
        } else {
            devices.append(d)
        }
        devices.sort { ($0.isFitness ? 1 : 0, $0.rssi) > ($1.isFitness ? 1 : 0, $1.rssi) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedName = peripheral.name ?? "자전거"
        status = connectedName ?? "연결됨"
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastDeviceKey)
        log("연결됨: \(connectedName ?? "")")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "연결 실패"
        log("연결 실패: \(error?.localizedDescription ?? "알 수 없음")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectedName = nil
        resetLive()
        log("연결 끊김\(error.map { ": \($0.localizedDescription)" } ?? "")")
        if userDisconnected {
            status = "연결 안 됨"
            self.peripheral = nil
        } else {
            // 연결 요청은 기기가 다시 나타날 때까지 대기하므로 그대로 걸어 둔다
            status = "재연결 대기 중…"
            central.connect(peripheral)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        log("서비스 \(services.count)개: " + services.map { $0.uuid.uuidString }.joined(separator: ", "))
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            log("  \(service.uuid.uuidString) / \(c.uuid.uuidString)")
            switch c.uuid {
            case GATT.indoorBikeData, GATT.cscMeasurement, GATT.cyclingPower, GATT.heartRate, GATT.ftmsStatus:
                peripheral.setNotifyValue(true, for: c)
            case GATT.ftmsControlPoint:
                controlPoint = c
                canControlResistance = true
                peripheral.setNotifyValue(true, for: c)
                writeControl([0x00]) // Request Control
            case GATT.resistanceRange:
                peripheral.readValue(for: c)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let data = c.value else { return }
        switch c.uuid {
        case GATT.indoorBikeData:
            let d = Parsers.indoorBike(data)
            if let v = d.speed { live.speed = v }
            if let v = d.cadence { live.cadence = v }
            if let v = d.power { live.power = v }
            if let v = d.resistance { live.resistance = v }
            if let v = d.distance { live.deviceDistance = v }
            if let v = d.kcal { live.deviceKcal = v }
            if let v = d.heartRate { live.heartRate = v }
        case GATT.cscMeasurement:
            handleCSC(data)
        case GATT.cyclingPower:
            if let v = Parsers.cyclingPower(data) { live.power = v }
        case GATT.heartRate:
            if let v = Parsers.heartRate(data) { live.heartRate = v }
        case GATT.resistanceRange:
            resistanceRange = Parsers.resistanceRange(data)
            log("저항 범위: \(resistanceRange.map { "\($0.lowerBound)–\($0.upperBound)" } ?? Parsers.hex(data))")
        case GATT.ftmsControlPoint:
            log("FTMS CP 응답 " + Parsers.hex(data))
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if let error {
            log("구독 실패 \(c.uuid.uuidString): \(error.localizedDescription)")
        } else {
            log("구독 \(c.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let error { log("쓰기 실패 \(c.uuid.uuidString): \(error.localizedDescription)") }
    }
}
