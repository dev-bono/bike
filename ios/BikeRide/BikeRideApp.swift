import SwiftUI

@main
struct BikeRideApp: App {
    @StateObject private var ble: BLEManager
    @StateObject private var session: RideSession
    @StateObject private var history = HistoryStore()

    init() {
        let ble = BLEManager()
        _ble = StateObject(wrappedValue: ble)
        _session = StateObject(wrappedValue: RideSession(ble: ble))
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(ble)
                .environmentObject(session)
                .environmentObject(history)
                .preferredColorScheme(.dark)
        }
    }
}
