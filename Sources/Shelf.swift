import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Bandeja de archivos (se guardan referencias, no copias)

final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []
    private let key = "shelfItems"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ providers: [NSItemProvider]) {
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                guard let url else { return }
                DispatchQueue.main.async {
                    guard let self, !self.items.contains(url) else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self.items.append(url) }
                    self.save()
                }
            }
        }
    }

    func remove(_ url: URL) {
        withAnimation(.easeOut(duration: 0.2)) { items.removeAll { $0 == url } }
        save()
    }

    func clear() {
        withAnimation(.easeOut(duration: 0.2)) { items.removeAll() }
        save()
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    /// Compartir por AirDrop, Correo o Mensajes.
    func share(_ url: URL, _ service: NSSharingService.Name) {
        if service == .composeEmail, Self.outlookInstalled {
            emailWithOutlook(url)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        NSSharingService(named: service)?.perform(withItems: [url])
    }

    // MARK: Correo con Outlook

    static var outlookInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Outlook") != nil
    }

    /// Nuevo mensaje de Outlook con el archivo adjunto (y el nombre como asunto).
    private func emailWithOutlook(_ url: URL) {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = """
        tell application "Microsoft Outlook"
            set newMsg to make new outgoing message with properties {subject:"\(esc(url.lastPathComponent))"}
            make new attachment at newMsg with properties {file:(POSIX file "\(esc(url.path))")}
            open newMsg
            activate
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error {
                Log.write("Outlook: \(error)")
                // Si Outlook no lo permite, usar Mail
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    NSSharingService(named: .composeEmail)?.perform(withItems: [url])
                }
            }
        }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: key)
    }
}

struct ShelfView: View {
    @EnvironmentObject var shelf: ShelfStore

    var body: some View {
        if shelf.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.5))
                Text(L("shelf.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("shelf.title", shelf.items.count))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.5))
                    Spacer()
                    Button(L("shelf.clear")) { shelf.clear() }
                        .buttonStyle(PillButtonStyle())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct ShelfItemView: View {
    @EnvironmentObject var shelf: ShelfStore
    let url: URL

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 46, height: 46)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .padding(4)
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            Button { shelf.remove(url) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(L("shelf.remove"))
        }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { shelf.open(url) }
        .overlay(alignment: .topLeading) {
            Button { PopupMenu.show(menuItems) } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(L("shelf.more"))
        }
        .islandMenu { menuItems }
        .help(L("shelf.itemHelp"))
    }

    private var menuItems: [PopupItem] {
        [
            PopupItem(title: L("shelf.open"), symbol: "arrow.up.forward.app") { shelf.open(url) },
            PopupItem(title: L("shelf.reveal"), symbol: "folder") { shelf.reveal(url) },
            .separator,
            PopupItem(title: L("share.airdrop"), symbol: "airplayaudio") { shelf.share(url, .sendViaAirDrop) },
            PopupItem(title: ShelfStore.outlookInstalled ? L("share.outlook") : L("share.mail"),
                      symbol: "envelope") { shelf.share(url, .composeEmail) },
            PopupItem(title: L("share.messages"), symbol: "message") { shelf.share(url, .composeMessage) },
            .separator,
            PopupItem(title: L("shelf.remove"), symbol: "xmark.circle") { shelf.remove(url) }
        ]
    }
}

// MARK: - Aviso de reunión en la isla cerrada

struct MeetingBannerView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var timer: TimerController
    let height: CGFloat

    var body: some View {
        if let item = calendar.upcoming {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let remaining = item.start.timeIntervalSince(ctx.date)
                let countdown = remaining > 0
                    ? L("meet.inMin", max(1, Int((remaining / 60).rounded(.up))))
                    : L("meet.nowUntil", Self.time.string(from: item.end))
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.color)
                    Text(countdown)
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(remaining > 0 ? Color.primary : item.color)
                        .fixedSize()
                    if state.hasNotch {
                        Spacer(minLength: state.notchSize.width + 8)
                        // Lado derecho: el temporizador si está en marcha; si no, el título
                        if let end = timer.endDate {
                            timerLabel(end: end, now: ctx.date)
                        } else {
                            Text(item.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.8))
                                .lineLimit(1)
                                .frame(maxWidth: 100, alignment: .trailing)
                        }
                    } else {
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let end = timer.endDate {
                            timerLabel(end: end, now: ctx.date)
                        }
                    }
                }
            }
            .frame(height: height)
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private func timerLabel(end: Date, now: Date) -> some View {
        let t = Int(max(0, end.timeIntervalSince(now)).rounded(.up))
        let text = t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                             : String(format: "%d:%02d", t / 60, t % 60)
        return HStack(spacing: 4) {
            TomatoIcon(size: 12, active: true)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.primary)
        }
        .fixedSize()
    }
}

// MARK: - Texto que se desplaza si no cabe (marquesina)

struct MarqueeText: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    var nsWeight: NSFont.Weight = .semibold
    var color: Color = .primary

    var body: some View {
        let textWidth = (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: nsWeight)
        ]).width + 2
        GeometryReader { g in
            if textWidth <= g.size.width {
                label.frame(width: g.size.width, alignment: .leading)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                    let gap: CGFloat = 36
                    let speed: CGFloat = 28            // puntos por segundo
                    let pause = 2.0                    // pausa al principio de cada vuelta
                    let travel = Double((textWidth + gap) / speed)
                    let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: travel + pause)
                    let offset = t < pause ? 0 : -CGFloat(t - pause) * speed
                    HStack(spacing: gap) { label; label }
                        .fixedSize()
                        .offset(x: offset)
                }
                .frame(width: g.size.width, alignment: .leading)
                .clipped()
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                )
            }
        }
        .frame(height: size * 1.35)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Animación de símbolo (macOS 14+)

extension View {
    @ViewBuilder
    func symbolReplaceTransition() -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }
}
