import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

// Nota: sin @State en todo el archivo. En SDKs recientes @State es una macro que
// solo compila con Xcode completo (no con las Command Line Tools).

// MARK: - Forma del notch (esquinas superiores "acampanadas" + inferiores redondeadas)

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Vista raíz

struct NotchView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var hudController: HUDController
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var shelf: ShelfStore
    @EnvironmentObject var alerts: AlertCenter
    @EnvironmentObject var timer: TimerController
    @Namespace private var ns

    var body: some View {
        let hud = hudController.active
        let sysAlert = alerts.alert
        let meeting = calendar.upcoming != nil || sysAlert != nil || timer.running
        let size = state.islandSize(mediaActive: media.isActive, hud: hud, meeting: meeting)
        let top: CGFloat = state.expanded ? 14 : 6
        let bottom: CGFloat = state.expanded ? 30 : (state.hasNotch ? 12 : 11)
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)
        let hidden = state.isHidden(hud: hud || meeting)
        // El halo sobra cuando toda la isla ya va teñida con la carátula
        let halo = state.expanded && state.tab == .music && media.track != nil && state.bgGradient == nil

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if state.expanded {
                    ExpandedView(ns: ns)
                        .padding(.horizontal, top + 18)
                        .padding(.bottom, 14)
                        .transition(.asymmetric(
                            insertion: AnyTransition.opacity
                                .combined(with: .scale(scale: 0.92, anchor: .top))
                                .animation(.easeOut(duration: 0.25).delay(0.08)),
                            removal: AnyTransition.opacity.animation(.easeIn(duration: 0.1))
                        ))
                } else if hidden {
                    EmptyView()
                } else if hud {
                    SystemHUDView(height: size.height)
                        .padding(.horizontal, top + 10)
                        .transition(.opacity)
                } else if let a = sysAlert {
                    SystemAlertView(alert: a, height: size.height)
                        .padding(.horizontal, top + 10)
                        .transition(.opacity)
                } else if calendar.upcoming != nil {
                    MeetingBannerView(height: size.height)
                        .padding(.horizontal, top + 10)
                        .transition(.opacity)
                } else if timer.running {
                    TimerBannerView(height: size.height)
                        .padding(.horizontal, top + 10)
                        .transition(.opacity)
                } else if !state.hasNotch {
                    PillView(ns: ns, height: size.height)
                        .padding(.horizontal, top + 10)
                        .transition(.opacity)
                } else if media.isActive {
                    LiveActivityView(ns: ns, height: size.height)
                        .padding(.horizontal, top + 8)
                        .transition(.opacity)
                } else {
                    IdleWingsView(height: size.height)
                        .padding(.horizontal, top + 10)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width + top * 2, height: size.height, alignment: .top)
            .overlay(alignment: .trailing) {
                if !state.expanded && !hidden {
                    StatusIndicators()
                        .padding(.trailing, top + 1)
                        .frame(height: size.height)
                }
            }
            .background(
                ZStack {
                    IslandBackground()
                    // Halo con el color de la carátula
                    if halo {
                        LinearGradient(colors: [media.accent.opacity(0.45), media.accent.opacity(0.12), .clear],
                                       startPoint: .bottomLeading, endPoint: .topTrailing)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: media.accent)
            )
            .clipShape(shape)
            // Soltar archivos en la isla → bandeja
            .onDrop(of: [UTType.fileURL], isTargeted: Binding(
                get: { false },
                set: { targeted in
                    if targeted && state.tab != .shelf {
                        withAnimation(.easeInOut(duration: 0.2)) { state.tab = .shelf }
                    }
                }
            )) { providers in
                shelf.add(providers)
                return true
            }
            .shadow(color: Color.black.opacity(state.expanded ? 0.45 : 0), radius: 14, x: 0, y: 6)
            // Oculta en pantallas sin notch: no se dibuja nada hasta pasar el ratón.
            .opacity(hidden && !state.hasNotch ? 0 : 1)

            Spacer(minLength: 0)
        }
        .frame(width: Metrics.window.width, height: Metrics.window.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Isla cerrada

/// Con notch y música: carátula a la izquierda, ecualizador a la derecha.
struct LiveActivityView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var media: MediaController
    let ns: Namespace.ID
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: media.artwork, size: 22, corner: 6)
                .matchedGeometryEffect(id: "artwork", in: ns)
                .opensOnClick(L("media.open", media.source?.displayName ?? "")) { media.openSourceApp() }
            Spacer(minLength: state.notchSize.width)
            EqualizerBars(playing: media.isPlaying, color: media.accent)
                .frame(width: 22)
        }
        .frame(height: height)
    }
}

/// Pantallas sin notch: píldora con tiempo + hora (o música si suena).
struct PillView: View {
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var weather: WeatherService
    let ns: Namespace.ID
    let height: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            if media.isActive {
                ArtworkView(image: media.artwork, size: 18, corner: 5)
                    .matchedGeometryEffect(id: "artwork", in: ns)
                    .opensOnClick(L("media.open", media.source?.displayName ?? "")) { media.openSourceApp() }
                MarqueeText(text: media.track?.title ?? "", size: 11, color: Color.primary.opacity(0.85))
                Spacer(minLength: 4)
                EqualizerBars(playing: media.isPlaying, color: media.accent)
                    .frame(width: 20)
            } else {
                CompactWeather()
                Spacer(minLength: 4)
                CompactDateTime(showDate: true)
                Spacer(minLength: 4)
                CompactBattery()
            }
        }
        .frame(height: height)
    }
}

/// Con notch y sin música: tiempo + hora a la izquierda, fecha + batería a la derecha.
struct IdleWingsView: View {
    @EnvironmentObject var state: NotchState
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                CompactWeather()
                CompactDateTime(showDate: false)
            }
            Spacer(minLength: state.notchSize.width + 8)
            HStack(spacing: 8) {
                CompactDate()
                CompactBattery()
            }
        }
        .frame(height: height)
    }
}

struct CompactWeather: View {
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        if let c = weather.current {
            HStack(spacing: 4) {
                Image(systemName: WeatherService.symbol(for: c.code, isDay: c.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 12))
                Text("\(Int(c.temperature.rounded()))°")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
            }
            .opensOnClick(L("weather.open")) { Opener.weather() }
        }
    }
}

/// Hora (y opcionalmente fecha corta delante).
struct CompactDateTime: View {
    let showDate: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 6) {
                if showDate {
                    Text(ctx.date, format: .dateTime.weekday(.abbreviated).day())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.primary)
            }
        }
    }
}

/// Fecha corta: "lun 2".
struct CompactDate: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            Text(ctx.date, format: .dateTime.weekday(.abbreviated).day())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.75))
        }
    }
}

struct CompactBattery: View {
    @EnvironmentObject var battery: BatteryMonitor

    var body: some View {
        if battery.hasBattery {
            let color: Color = battery.charging ? .green : (battery.level <= 20 ? .red : .primary)
            HStack(spacing: 3) {
                Text("\(battery.level)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.primary.opacity(0.8))
                Image(systemName: battery.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
            }
            .opensOnClick(L("battery.open")) { Opener.battery() }
        }
    }
}

// MARK: - Isla expandida

struct ExpandedView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var battery: BatteryMonitor
    let ns: Namespace.ID

    @EnvironmentObject var caffeine: CaffeineController
    @EnvironmentObject var countdown: TimerController

    /// Temporizador (Pomodoro): tomate + minutos restantes cuando corre.
    private var tomatoButton: some View {
        Button {
            var items = [5, 10, 15, 25, 30, 45, 60].map { m in
                PopupItem(title: L("timer.minutes", m), symbol: "timer") { countdown.start(minutes: m) }
            }
            if countdown.running {
                items.append(.separator)
                items.append(PopupItem(title: L("timer.cancel"), symbol: "xmark.circle") { countdown.cancel() })
            }
            PopupMenu.show(items)
        } label: {
            HStack(spacing: 4) {
                TomatoIcon(size: 15, active: countdown.running)
                if let end = countdown.endDate {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("\(max(1, Int((end.timeIntervalSince(ctx.date) / 60).rounded(.up))))'")
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .padding(.horizontal, countdown.running ? 8 : 0)
            .frame(minWidth: 28, minHeight: 28)
            .background(Capsule().fill(Color.primary.opacity(countdown.running ? 0.16 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(countdown.running ? L("timer.runningHelp") : L("timer.help"))
    }

    private var caffeineButton: some View {
        Button { caffeine.toggle() } label: {
            Image(systemName: caffeine.active ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(caffeine.active ? Color.orange : Color.primary)
        }
        .buttonStyle(IconButtonStyle(size: 28))
        .help(caffeine.active ? L("caffeine.on") : L("caffeine.off"))
    }

    private var optionsButton: some View {
        Button {
            NotificationCenter.default.post(name: .showOptionsMenu, object: nil)
        } label: {
            Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(IconButtonStyle(size: 28))
        .help(L("options.help"))
    }

    var body: some View {
        VStack(spacing: 10) {
            // Fila superior
            Group {
                if state.hasNotch {
                    // Con notch: a ambos lados del notch físico
                    HStack(spacing: 0) {
                        HStack(spacing: 10) {
                            ClockView()
                            TabSwitcher()
                        }
                        Spacer(minLength: state.centerGap)
                        HStack(spacing: 12) {
                            WeatherBadge()
                            if battery.hasBattery { BatteryView() }
                        }
                        caffeineButton.padding(.leading, 12)
                        tomatoButton.padding(.leading, 4)
                        optionsButton.padding(.leading, 6)
                    }
                } else {
                    // Sin notch: hora y tiempo centrados
                    ZStack {
                        HStack(spacing: 0) {
                            TabSwitcher()
                            Spacer(minLength: 0)
                            caffeineButton
                            tomatoButton.padding(.leading, 4)
                            optionsButton.padding(.leading, 6)
                        }
                        // Hora · tiempo · batería, centrados
                        HStack(spacing: 16) {
                            ClockView()
                            WeatherBadge()
                            if battery.hasBattery { BatteryView() }
                        }
                    }
                }
            }
            .frame(height: state.notchSize.height)

            HStack(alignment: .top, spacing: 16) {
                Group {
                    if state.tab == .system {
                        SystemPanel()
                            .transition(.opacity)
                    } else if state.tab == .shelf {
                        ShelfView()
                            .transition(.opacity)
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            if media.track != nil { MediaCard(ns: ns) } else { EmptyMediaView() }
                            HStack(spacing: 10) {
                                OutputChip()
                                    .background(alignment: .trailing) {
                                        // Ancla invisible del selector AirPlay (se abre desde el menú de salida)
                                        AirPlayButton()
                                            .frame(width: 1, height: 1)
                                            .opacity(0.01)
                                            .allowsHitTesting(false)
                                    }
                                VolumeControl()
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1, height: 150)

                // 60 % música · 40 % agenda
                AgendaView()
                    .frame(width: 248, alignment: .topLeading)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Selector de pestaña: música · rendimiento · bandeja
struct TabSwitcher: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var shelf: ShelfStore

    var body: some View {
        HStack(spacing: 2) {
            tab(.music, "music.note", L("tab.music"))
            tab(.system, "gauge.with.dots.needle.50percent", L("sys.help"))
            tab(.shelf, shelf.items.isEmpty ? "tray" : "tray.full.fill", L("tab.shelf"))
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func tab(_ t: NotchState.Tab, _ symbol: String, _ help: String) -> some View {
        let selected = state.tab == t
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { state.tab = t }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(selected ? 1 : 0.55))
                .frame(width: 28, height: 22)
                .background(Capsule().fill(Color.primary.opacity(selected ? 0.18 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 6) {
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.primary)
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.55))
            }
        }
    }
}

struct WeatherBadge: View {
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        if let c = weather.current {
            HStack(spacing: 5) {
                Image(systemName: WeatherService.symbol(for: c.code, isDay: c.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 17))
                Text("\(Int(c.temperature.rounded()))°")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
                if !weather.place.isEmpty {
                    Text(weather.place)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineLimit(1)
                        .frame(maxWidth: 68, alignment: .leading)
                }
            }
            .opensOnClick(L("weather.help", WeatherService.description(for: c.code), Int(c.high.rounded()), Int(c.low.rounded()))) { Opener.weather() }
        }
    }
}

struct BatteryView: View {
    @EnvironmentObject var battery: BatteryMonitor

    var body: some View {
        let color: Color = battery.charging ? .green : (battery.level <= 20 ? .red : .primary)
        HStack(spacing: 4) {
            Text("\(battery.level)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.primary.opacity(0.8))
            Image(systemName: battery.symbol)
                .font(.system(size: 18))
                .foregroundStyle(color)
        }
        .opensOnClick(L("battery.open")) { Opener.battery() }
    }
}

// MARK: - Música

struct MediaCard: View {
    @EnvironmentObject var media: MediaController
    let ns: Namespace.ID

    var body: some View {
        if let track = media.track {
            HStack(alignment: .center, spacing: 14) {
                ArtworkView(image: media.artwork, size: 104, corner: 18)
                    .matchedGeometryEffect(id: "artwork", in: ns)
                    .overlay(alignment: .bottomTrailing) {
                        if let icon = media.sourceIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 26, height: 26)
                                .offset(x: 6, y: 6)
                        }
                    }
                    .shadow(color: media.accent.opacity(0.35), radius: 10)
                    .opensOnClick(L("media.open", media.source?.displayName ?? "")) { media.openSourceApp() }

                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(text: track.title, size: 15)
                    Text(track.artist)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(1)
                    LyricLineView()
                    ProgressRow()
                        .padding(.top, 6)
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        Button { media.previous() } label: { Image(systemName: "backward.fill") }
                            .buttonStyle(IconButtonStyle(size: 32))
                        Button { media.playPause() } label: {
                            Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .symbolReplaceTransition()
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: media.isPlaying)
                        }
                        .buttonStyle(IconButtonStyle(size: 40))
                        Button { media.next() } label: { Image(systemName: "forward.fill") }
                            .buttonStyle(IconButtonStyle(size: 32))
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            }
            // Deslizar con dos dedos: ← siguiente · → anterior
            .background(SwipeCatcher { dir in dir > 0 ? media.next() : media.previous() })
        }
    }
}

struct ProgressRow: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let duration = media.track?.duration ?? 0
            let pos = media.position(at: ctx.date)
            let fraction = duration > 0 ? min(max(pos / duration, 0), 1) : 0

            HStack(spacing: 8) {
                Text(format(pos)).frame(width: 34, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.15)).frame(height: 4)
                        Capsule().fill(media.accent).frame(width: g.size.width * fraction, height: 4)
                        Circle().fill(Color.primary)
                            .frame(width: 9, height: 9)
                            .offset(x: g.size.width * fraction - 4.5)
                            .opacity(duration > 0 ? 0.9 : 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    // Clic o arrastre para saltar a ese punto
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                        guard duration > 0, g.size.width > 0 else { return }
                        media.seek(to: Double(min(max(v.location.x / g.size.width, 0), 1)) * duration)
                    })
                }
                .frame(height: 12)
                .help(L("media.seekHelp"))
                Text("-" + format(max(duration - pos, 0))).frame(width: 40, alignment: .trailing)
            }
            .frame(height: 12)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.primary.opacity(0.5))
        }
    }

    private func format(_ seconds: Double) -> String {
        let t = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct EmptyMediaView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ArtworkView(image: nil, size: 80, corner: 15)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("media.nothing"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(L("media.nothingHint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    ForEach(MediaController.Source.allCases.filter(\.isInstalled), id: \.self) { source in
                        Button { source.launch() } label: {
                            if let icon = source.icon {
                                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(L("media.open", source.displayName))
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Salida de sonido

struct OutputChip: View {
    @EnvironmentObject var audio: AudioOutputMonitor

    var body: some View {
        if let device = audio.current {
            Button {
                NotificationCenter.default.post(name: .showOutputMenu, object: nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: device.symbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text(device.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
                .foregroundStyle(Color.primary.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(L("output.help"))
        }
    }
}

// MARK: - AirPlay (selector oficial de Apple)

enum RoutePicker {
    static weak var view: AVRoutePickerView?

    /// Abre el selector como si se pulsara el botón AirPlay de la isla.
    static func show() {
        guard let v = view else { return }
        func findButton(_ view: NSView) -> NSButton? {
            if let b = view as? NSButton { return b }
            for sub in view.subviews { if let b = findButton(sub) { return b } }
            return nil
        }
        findButton(v)?.performClick(nil)
    }
}

struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.isRoutePickerButtonBordered = false
        v.setRoutePickerButtonColor(.systemBlue, for: .active)
        v.setRoutePickerButtonColor(.systemBlue, for: .activeHighlighted)
        tint(v, dark: context.environment.colorScheme == .dark)
        RoutePicker.view = v
        return v
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        tint(nsView, dark: context.environment.colorScheme == .dark)
        RoutePicker.view = nsView
    }

    private func tint(_ v: AVRoutePickerView, dark: Bool) {
        let base: NSColor = dark ? .white : .black
        v.setRoutePickerButtonColor(base.withAlphaComponent(0.85), for: .normal)
        v.setRoutePickerButtonColor(base, for: .normalHighlighted)
    }
}

// MARK: - Volumen

struct VolumeControl: View {
    @EnvironmentObject var audio: AudioOutputMonitor

    var body: some View {
        if audio.volumeSettable {
            HStack(spacing: 8) {
                Button { audio.toggleMute() } label: {
                    Image(systemName: audio.volumeSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.85))

                VolumeBar(value: audio.muted ? 0 : audio.volume) { audio.setVolume($0) }
            }
            .help(L("volume.help"))
        }
    }
}

/// Barra de volumen arrastrable (sin @State: el valor vive en AudioOutputMonitor).
struct VolumeBar: View {
    let value: Float
    var interactive = true
    let onChange: (Float) -> Void

    init(value: Float, interactive: Bool = true, onChange: @escaping (Float) -> Void = { _ in }) {
        self.value = value
        self.interactive = interactive
        self.onChange = onChange
    }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15)).frame(height: 5)
                Capsule().fill(Color.primary)
                    .frame(width: max(5, g.size.width * CGFloat(value)), height: 5)
                    .animation(.easeOut(duration: 0.12), value: value)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                guard interactive, g.size.width > 0 else { return }
                onChange(Float(min(max(v.location.x / g.size.width, 0), 1)))
            })
        }
        .frame(height: 16)
    }
}

// MARK: - Agenda

struct AgendaView: View {
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                if calendar.agendaMode == .month && calendar.access == .granted {
                    MonthHeader()
                } else {
                    Text(L("agenda.title"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
                Spacer()
                if calendar.access == .granted {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            calendar.agendaMode = calendar.agendaMode == .month ? .upcoming : .month
                            calendar.selectedDay = nil
                        }
                        calendar.loadMonth()
                    } label: {
                        Image(systemName: calendar.agendaMode == .month ? "list.bullet" : "square.grid.3x3")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(IconButtonStyle(size: 26))
                    .help(calendar.agendaMode == .month ? L("agenda.modeList") : L("agenda.modeMonth"))
                }
                Button { calendar.openCalendarApp() } label: {
                    Image(systemName: "calendar").font(.system(size: 16, weight: .semibold))
                }
                    .buttonStyle(IconButtonStyle(size: 32))
                    .help(L("menu.openCalendar"))
            }

            switch calendar.access {
            case .granted where calendar.agendaMode == .month:
                MonthGridView()
            case .granted:
                if calendar.items.isEmpty {
                    Text(L("agenda.empty"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.55))
                } else {
                    ForEach(calendar.items.prefix(3)) { item in
                        EventRow(item: item)
                    }
                }
            case .notDetermined:
                Text(L("agenda.needAccess"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.55))
                Button(L("agenda.allow")) { calendar.requestAccess() }
                    .buttonStyle(PillButtonStyle())
            case .denied:
                Text(L("agenda.denied"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.55))
                Button(L("agenda.openSettings")) { calendar.openPrivacySettings() }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }
}

struct EventRow: View {
    @EnvironmentObject var calendar: CalendarService
    let item: CalendarService.Item

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(item.color)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(item.label)
                    .font(.system(size: 10.5, weight: item.isNow ? .semibold : .regular))
                    .foregroundStyle(item.isNow ? item.color : Color.primary.opacity(0.55))
                    .lineLimit(1)
            }
            if item.joinURL != nil {
                Spacer(minLength: 4)
                Button(L("meet.join")) { calendar.join(item) }
                    .buttonStyle(PillButtonStyle())
                    .help(L("meet.joinHelp"))
            }
        }
    }
}

// MARK: - Piezas reutilizables

/// Abre apps o ajustes del sistema.
enum Opener {
    static func app(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    static func weather() { app("com.apple.weather") }
    static func battery() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension View {
    /// Hace clicable cualquier elemento (con cursor de mano y tooltip).
    func opensOnClick(_ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { self.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .help(help)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct EqualizerBars: View {
    let playing: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let speed = 3.0 + Double(i) * 1.3
                    let h = playing ? 4 + 10 * abs(sin(t * speed + Double(i))) : 3
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: h)
                }
            }
            .frame(height: 14)
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 1 : 0.88))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.25 : 0.08)))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.3 : 0.15)))
            .contentShape(Capsule())
    }
}
