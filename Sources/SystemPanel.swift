import SwiftUI
import AppKit

// MARK: - Panel de rendimiento (pestaña 🎛 de la isla abierta)

struct SystemPanel: View {
    @EnvironmentObject var system: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Fila 1: anillos + batería
            HStack(alignment: .top, spacing: 6) {
                UsageRing(value: system.cpu, label: "CPU", color: loadColor(system.cpu))
                UsageRing(value: system.memory, label: L("sys.memory"), color: pressureColor,
                          caption: pressureText)
                if let gpu = system.gpu {
                    UsageRing(value: gpu, label: "GPU", color: loadColor(gpu))
                }
                UsageRing(value: system.disk, label: L("sys.disk"), color: loadColor(system.disk),
                          caption: L("sys.free", bytes(system.diskFree)))
                Spacer(minLength: 4)
                BatteryHealthView()
            }

            // Fila 2: último minuto de CPU y red
            HStack(spacing: 10) {
                Sparkline(values: system.cpuHistory, maxValue: 1, color: loadColor(system.cpu),
                          title: L("sys.cpu1min"), value: "\(Int((system.cpu * 100).rounded())) %")
                Sparkline(values: system.netHistory, maxValue: nil, color: .cyan,
                          title: L("sys.network"),
                          value: "↓ \(rate(system.downPerSec))  ↑ \(rate(system.upPerSec))")
            }

            // Fila 3: lo que más consume
            VStack(alignment: .leading, spacing: 2) {
                ForEach(system.topProcesses) { p in
                    ProcessRow(process: p)
                }
            }
        }
        .onAppear { system.setDetailActive(true) }
        .onDisappear { system.setDetailActive(false) }
    }

    private var pressureColor: Color {
        switch system.pressure {
        case 4: return .red
        case 2: return .yellow
        default: return .green
        }
    }

    private var pressureText: String {
        switch system.pressure {
        case 4: return L("sys.pressure.critical")
        case 2: return L("sys.pressure.warn")
        default: return L("sys.pressure.normal")
        }
    }

    private func loadColor(_ v: Double) -> Color { v < 0.6 ? .green : (v < 0.85 ? .orange : .red) }

    private func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useTB]
        return f.string(fromByteCount: n)
    }

    private func rate(_ bps: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: Int64(bps)) + "/s"
    }
}

struct UsageRing: View {
    let value: Double
    let label: String
    let color: Color
    var caption: String = ""

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(value, 0.001), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: value)
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.primary)
            }
            .frame(width: 38, height: 38)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.7))
                .lineLimit(1)
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(width: 50)
        .opensOnClick(L("sys.open")) { Opener.app("com.apple.ActivityMonitor") }
    }
}

struct BatteryHealthView: View {
    @EnvironmentObject var system: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let b = system.battery {
                line("heart.fill", L("sys.health", b.healthPercent), b.healthPercent >= 80 ? .green : .orange)
                line("arrow.triangle.2.circlepath", L("sys.cycles", b.cycles), Color.primary.opacity(0.7))
                if b.onAC {
                    line("bolt.fill", L("sys.drawAC", watts(b.watts)), .green)
                } else {
                    line("bolt", L("sys.drawBattery", watts(b.watts)), .orange)
                }
            }
            line(thermalSymbol, thermalText, thermalColor)
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(Color.primary.opacity(0.85))
        .frame(width: 112, alignment: .leading)
        .opensOnClick(L("battery.open")) { Opener.battery() }
    }

    private func line(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 12)
            Text(text).lineLimit(1)
        }
    }

    private func watts(_ w: Double) -> String { String(format: "%.1f W", w) }

    private var thermalSymbol: String { system.thermal == .nominal ? "thermometer.low" : "thermometer.high" }

    private var thermalText: String {
        switch system.thermal {
        case .nominal: return L("sys.thermal.nominal")
        case .fair: return L("sys.thermal.fair")
        case .serious: return L("sys.thermal.serious")
        case .critical: return L("sys.thermal.critical")
        @unknown default: return "—"
        }
    }

    private var thermalColor: Color {
        switch system.thermal {
        case .nominal: return Color.primary.opacity(0.7)
        case .fair: return .yellow
        case .serious: return .orange
        default: return .red
        }
    }
}

/// Mini gráfica del último minuto.
struct Sparkline: View {
    let values: [Double]
    let maxValue: Double?
    let color: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).foregroundStyle(Color.primary.opacity(0.5))
                Spacer(minLength: 4)
                Text(value).foregroundStyle(Color.primary.opacity(0.85)).lineLimit(1)
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())

            GeometryReader { g in
                let pts = points(in: g.size)
                ZStack {
                    if pts.count > 1 {
                        Path { p in
                            p.move(to: CGPoint(x: pts[0].x, y: g.size.height))
                            pts.forEach { p.addLine(to: $0) }
                            p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom))
                        Path { p in
                            p.move(to: pts[0])
                            pts.dropFirst().forEach { p.addLine(to: $0) }
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.05)))
        }
        .frame(maxWidth: .infinity)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let top = maxValue ?? max(values.max() ?? 1, 1)
        let step = size.width / CGFloat(29)   // 30 muestras = 1 minuto
        let offset = CGFloat(30 - values.count) * step
        return values.enumerated().map { i, v in
            CGPoint(x: offset + CGFloat(i) * step,
                    y: size.height - CGFloat(min(v / top, 1)) * (size.height - 1))
        }
    }
}

struct ProcessRow: View {
    @EnvironmentObject var system: SystemMonitor
    let process: SystemMonitor.ProcessUsage

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon = process.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "gearshape.fill").resizable().foregroundStyle(Color.primary.opacity(0.4))
                }
            }
            .frame(width: 13, height: 13)
            Text(process.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.primary.opacity(0.85))
            Spacer(minLength: 6)
            Text(String(format: "%.0f %%", process.cpu))
                .foregroundStyle(process.cpu > 80 ? Color.orange : Color.primary.opacity(0.85))
                .frame(width: 42, alignment: .trailing)
            Text(ByteCountFormatter.string(fromByteCount: Int64(process.memory), countStyle: .memory))
                .foregroundStyle(Color.primary.opacity(0.5))
                .frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
        .frame(height: 15)
        .contentShape(Rectangle())
        .onTapGesture { system.activate(process) }
        .islandMenu {
            var items: [PopupItem] = []
            if process.isApp {
                items.append(PopupItem(title: L("sys.showApp"), symbol: "macwindow") { system.activate(process) })
                items.append(PopupItem(title: L("sys.forceQuit"), symbol: "xmark.octagon") { system.forceQuit(process) })
                items.append(.separator)
            }
            items.append(PopupItem(title: L("sys.open"), symbol: "chart.bar.xaxis") { Opener.app("com.apple.ActivityMonitor") })
            return items
        }
        .help(L("sys.processHelp"))
    }
}

// MARK: - Aviso del sistema en la isla cerrada

struct SystemAlertView: View {
    @EnvironmentObject var state: NotchState
    let alert: SystemMonitor.SysAlert
    let height: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: alert.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(alert.color)
                .symbolEffectBounce(trigger: alert.short)
            Text(alert.short)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            if state.hasNotch { Spacer(minLength: state.notchSize.width + 8) }
            Text(alert.detail)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.75))
                .lineLimit(1)
                .frame(maxWidth: state.hasNotch ? 100 : .infinity, alignment: state.hasNotch ? .trailing : .leading)
        }
        .frame(height: height)
    }
}
