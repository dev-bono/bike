import Foundation
import UIKit

struct RideRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var seconds: Int
    var distance: Int      // m
    var avgSpeed: Double   // km/h
    var avgCadence: Double
    var avgPower: Double
    var kcal: Int
}

final class HistoryStore: ObservableObject {
    @Published private(set) var rides: [RideRecord] = []

    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rides.json")
    }

    init() { load() }

    func add(_ r: RideRecord) {
        rides.insert(r, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        rides.remove(atOffsets: offsets)
        save()
    }

    func csv() -> String {
        let f = ISO8601DateFormatter()
        var lines = ["date,seconds,distance_m,avg_speed_kmh,avg_cadence_rpm,avg_power_w,kcal"]
        for r in rides {
            lines.append([f.string(from: r.date), "\(r.seconds)", "\(r.distance)",
                          String(format: "%.1f", r.avgSpeed), String(format: "%.0f", r.avgCadence),
                          String(format: "%.0f", r.avgPower), "\(r.kcal)"].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([RideRecord].self, from: data) else { return }
        rides = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rides) { try? data.write(to: url, options: .atomic) }
    }
}

final class RideSession: ObservableObject {
    enum State { case idle, running, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var distance: Double = 0   // m
    @Published private(set) var kcal: Double = 0

    private let ble: BLEManager
    private var timer: Timer?
    private var lastTick = Date()
    private var distBase: Int?
    private var kcalBase: Int?
    private var speedSum = 0.0, cadenceSum = 0.0, powerSum = 0.0
    private var speedN = 0, cadenceN = 0, powerN = 0

    init(ble: BLEManager) { self.ble = ble }

    func start() {
        if state == .idle { reset() }
        state = .running
        lastTick = Date()
        ble.sendStart()
        UIApplication.shared.isIdleTimerDisabled = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pause() {
        state = .paused
        timer?.invalidate()
        ble.sendPause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Ends the ride. Returns a record if it was long enough to keep.
    func finish() -> RideRecord? {
        timer?.invalidate()
        ble.sendStop()
        UIApplication.shared.isIdleTimerDisabled = false
        defer { state = .idle }
        guard elapsed >= 10 else { return nil }
        return RideRecord(date: Date().addingTimeInterval(-elapsed), seconds: Int(elapsed),
                          distance: Int(distance), avgSpeed: avg(speedSum, speedN),
                          avgCadence: avg(cadenceSum, cadenceN), avgPower: avg(powerSum, powerN),
                          kcal: Int(kcal))
    }

    private func avg(_ s: Double, _ n: Int) -> Double { n > 0 ? s / Double(n) : 0 }

    private func reset() {
        elapsed = 0; distance = 0; kcal = 0
        distBase = nil; kcalBase = nil
        speedSum = 0; cadenceSum = 0; powerSum = 0
        speedN = 0; cadenceN = 0; powerN = 0
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard state == .running else { return }
        elapsed += dt

        let live = ble.live
        let speed = live.speed ?? 0

        // 기기 누적값이 있으면 그 차이를, 없으면 속도·파워로 적분
        if let d = live.deviceDistance {
            if distBase == nil { distBase = d - Int(distance) }
            distance = Double(max(0, d - (distBase ?? d)))
        } else {
            distance += speed / 3.6 * dt
        }
        if let k = live.deviceKcal {
            if kcalBase == nil { kcalBase = k - Int(kcal) }
            kcal = Double(max(0, k - (kcalBase ?? k)))
        } else if let p = live.power {
            kcal += Double(p) * dt / 4184 / 0.24
        } else {
            kcal += Self.kcalPerSecond(speed: speed) * dt
        }

        if speed > 0 { speedSum += speed; speedN += 1 }
        if let c = live.cadence, c > 0 { cadenceSum += c; cadenceN += 1 }
        if let p = live.power, p > 0 { powerSum += Double(p); powerN += 1 }
    }

    /// 대략적인 MET 기반 추정 (체중 70kg 가정)
    private static func kcalPerSecond(speed: Double) -> Double {
        let met: Double
        switch speed {
        case ..<0.1: met = 0
        case ..<16: met = 4
        case ..<19: met = 6.8
        case ..<22: met = 8
        default: met = 10
        }
        return met * 3.5 * 70 / 200 / 60
    }
}
