import CoreBluetooth
import SwiftUI

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var session: RideSession
    @EnvironmentObject var history: HistoryStore

    @State private var showDevices = false
    @State private var showHistory = false
    @State private var showLog = false
    @State private var confirmFinish = false
    @AppStorage(SpeedCorrection.key) private var speedFactor = SpeedCorrection.defaultValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    connectionBar

                    Tile(label: "운동 시간", value: formatTime(session.elapsed), unit: nil, big: true)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        Tile(label: "속도", value: fmt(ble.live.speed.map { $0 * speedFactor }, 1), unit: "km/h")
                        Tile(label: "케이던스", value: fmt(ble.live.cadence, 0), unit: "rpm")
                        Tile(label: "파워", value: fmt(ble.live.power.map { Double($0) }, 0), unit: "W")
                        Tile(label: "심박", value: fmt(ble.live.heartRate.map { Double($0) }, 0), unit: "bpm")
                        Tile(label: "거리", value: String(format: "%.2f", session.distance / 1000), unit: "km")
                        Tile(label: "칼로리", value: String(format: "%.0f", session.kcal), unit: "kcal")
                    }

                    controls

                    speedCorrection

                    if ble.canControlResistance { resistance }
                }
                .padding(16)
            }
            .background(Color(red: 0.06, green: 0.07, blue: 0.08))
            .navigationTitle("바이크")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLog = true } label: { Image(systemName: "ladybug") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: { Image(systemName: "list.bullet.rectangle") }
                }
            }
            .sheet(isPresented: $showDevices) { DeviceListView() }
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showLog) { LogView() }
            .confirmationDialog("운동을 종료할까요?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("종료하고 저장") { if let r = session.finish() { history.add(r) } }
                Button("저장하지 않고 종료", role: .destructive) { _ = session.finish() }
                Button("취소", role: .cancel) {}
            }
        }
    }

    private var connectionBar: some View {
        HStack {
            Circle()
                .fill(ble.isConnected ? Color.accentColor : Color.gray)
                .frame(width: 10, height: 10)
            Text(ble.status).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if ble.isConnected {
                Button("연결 해제") { ble.disconnect() }.buttonStyle(.bordered)
            } else {
                Button("자전거 연결") { showDevices = true }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            switch session.state {
            case .idle:
                BigButton(title: "운동 시작", color: .accentColor) { session.start() }
            case .running:
                BigButton(title: "일시정지", color: .orange) { session.pause() }
                BigButton(title: "종료", color: .red) { confirmFinish = true }
            case .paused:
                BigButton(title: "계속", color: .accentColor) { session.start() }
                BigButton(title: "종료", color: .red) { confirmFinish = true }
            }
        }
    }

    private var speedCorrection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("속도 보정").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button { speedFactor = max(0.3, ((speedFactor - 0.05) * 100).rounded() / 100) } label: {
                    Image(systemName: "minus").frame(width: 56, height: 44)
                }.buttonStyle(.bordered)
                Spacer()
                Text(String(format: "×%.2f", speedFactor))
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                Spacer()
                Button { speedFactor = min(1.5, ((speedFactor + 0.05) * 100).rounded() / 100) } label: {
                    Image(systemName: "plus").frame(width: 56, height: 44)
                }.buttonStyle(.bordered)
            }
            Text(ble.live.speed.map { String(format: "자전거 원래 속도 %.1f km/h · 거리도 같은 비율로 계산", $0) }
                 ?? "자전거가 보내는 속도·거리에 이 비율을 곱합니다")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }

    private var resistance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("저항").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button { ble.setResistance((ble.live.resistance ?? 0) - 1) } label: {
                    Image(systemName: "minus").frame(width: 56, height: 44)
                }.buttonStyle(.bordered)
                Spacer()
                Text(fmt(ble.live.resistance, 0)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                Spacer()
                Button { ble.setResistance((ble.live.resistance ?? 0) + 1) } label: {
                    Image(systemName: "plus").frame(width: 56, height: 44)
                }.buttonStyle(.bordered)
            }
            if let r = ble.resistanceRange {
                Text("범위 \(Int(r.lowerBound))–\(Int(r.upperBound))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Components

struct Tile: View {
    let label: String
    let value: String
    let unit: String?
    var big = false

    var body: some View {
        VStack(alignment: big ? .center : .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: big ? 56 : 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: big ? .center : .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }
}

struct BigButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }
}

// MARK: - Device list

struct DeviceListView: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if ble.bluetoothState == .unauthorized {
                    Text("설정 > 바이크 > 블루투스를 허용해 주세요.").foregroundStyle(.orange)
                } else if ble.bluetoothState == .poweredOff {
                    Text("블루투스가 꺼져 있습니다.").foregroundStyle(.orange)
                }
                Section {
                    ForEach(ble.devices) { d in
                        Button {
                            ble.connect(d)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: d.isFitness ? "bicycle" : "dot.radiowaves.left.and.right")
                                    .foregroundStyle(d.isFitness ? Color.accentColor : Color.secondary)
                                Text(d.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(d.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("주변 기기")
                        if ble.isScanning { ProgressView().padding(.leading, 4) }
                    }
                } footer: {
                    Text("자전거 페달을 돌려 콘솔을 깨운 뒤 목록에서 EXCIDER로 시작하는 기기를 고르세요.")
                }
            }
            .navigationTitle("자전거 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
        .onAppear { ble.startScan() }
        .onDisappear { ble.stopScan() }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if history.rides.isEmpty {
                    Text("아직 기록이 없습니다.").foregroundStyle(.secondary)
                }
                ForEach(history.rides) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text("\(formatTime(TimeInterval(r.seconds))) · \(String(format: "%.2f", Double(r.distance) / 1000))km · 평균 \(String(format: "%.1f", r.avgSpeed))km/h · \(r.kcal)kcal")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if r.avgCadence > 0 || r.avgPower > 0 {
                            Text("평균 \(Int(r.avgCadence))rpm · \(Int(r.avgPower))W")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { history.delete(at: $0) }
            }
            .navigationTitle("운동 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: history.csv(), preview: SharePreview("운동 기록 CSV")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(history.rides.isEmpty)
                }
            }
        }
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(ble.logLines.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("블루투스 로그")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("복사") { UIPasteboard.general.string = ble.logLines.joined(separator: "\n") }
                        Button("지우기", role: .destructive) { ble.clearLog() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
    }
}

// MARK: - Formatting

func fmt(_ v: Double?, _ digits: Int) -> String {
    guard let v, v.isFinite else { return "–" }
    return String(format: "%.\(digits)f", v)
}

func formatTime(_ t: TimeInterval) -> String {
    let s = Int(t)
    let h = s / 3600, m = (s % 3600) / 60, x = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%02d:%02d", m, x)
}
