import AppKit
import SwiftUI
import Combine
import CoreAudio
import ServiceManagement

// MARK: - Medidas

enum Metrics {
    /// Tamaño fijo de cada ventana transparente (la isla se dibuja dentro).
    static let window = CGSize(width: 820, height: 290)
    /// Tamaño de la isla expandida.
    static let expanded = CGSize(width: 690, height: 234)
    /// Ancho extra (total) cuando hay música y la isla está cerrada sobre un notch.
    static let liveExtra: CGFloat = 84
    /// Ancho extra (total) en reposo sobre un notch: alas con tiempo/hora y fecha/batería.
    static let idleExtra: CGFloat = 230
    /// Ancho de la píldora en pantallas sin notch (con música / en reposo).
    static let pillWidth: CGFloat = 240
    static let pillIdleWidth: CGFloat = 270
}

// MARK: - Preferencias

enum DisplayMode: String, CaseIterable {
    case builtin, external, all

    var title: String { L("mode.\(rawValue)") }

    static var current: DisplayMode {
        get { DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "") ?? .all }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "displayMode") }
    }
}

/// Isla siempre visible u oculta hasta pasar el ratón.
enum IslandVisibility {
    static var autoHide: Bool {
        get { UserDefaults.standard.bool(forKey: "autoHide") }
        set { UserDefaults.standard.set(newValue, forKey: "autoHide") }
    }
}

extension Notification.Name {
    /// La vista pide abrir el menú de opciones o el de salidas de audio.
    static let showOptionsMenu = Notification.Name("Muesca.showOptionsMenu")
    static let showOutputMenu = Notification.Name("Muesca.showOutputMenu")
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    var isBuiltin: Bool { CGDisplayIsBuiltin(displayID) != 0 }
}

// MARK: - Estado de cada isla

final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = true
    @Published var autoHide = false
    /// Pestaña de la isla abierta: música, rendimiento o bandeja de archivos.
    enum Tab { case music, system, shelf }
    @Published var tab: Tab = .music
    // Aspecto: degradado de la carátula (nil = negro)
    @Published var bgGradient: [Color]?

    /// Cerrada y en modo oculto (sin indicador de volumen activo).
    func isHidden(hud: Bool) -> Bool { autoHide && !expanded && !hud }

    /// Hueco central que hay que respetar (el notch físico).
    var centerGap: CGFloat { hasNotch ? notchSize.width + 16 : 24 }

    func islandSize(mediaActive: Bool, hud: Bool = false, meeting: Bool = false) -> CGSize {
        if expanded { return Metrics.expanded }
        let hud = hud || meeting
        if isHidden(hud: hud) {
            // Solo queda la zona sensible: el notch, o una píldora invisible en la barra de menús.
            return hasNotch ? notchSize : CGSize(width: Metrics.pillWidth, height: notchSize.height)
        }
        let compact = mediaActive && !hud
        if !hasNotch {
            return CGSize(width: compact ? Metrics.pillWidth : Metrics.pillIdleWidth, height: notchSize.height)
        }
        let extra = compact ? Metrics.liveExtra : Metrics.idleExtra
        return CGSize(width: notchSize.width + extra, height: notchSize.height)
    }
}

// MARK: - Ventana

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Una isla en una pantalla

final class IslandWindow {
    let screen: NSScreen
    let state = NotchState()
    private let panel = NotchPanel()
    private unowned let controller: NotchController
    private var collapseWork: DispatchWorkItem?

    private let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.78)
    private let collapseAnimation = Animation.spring(response: 0.36, dampingFraction: 0.9)

    init(screen: NSScreen, controller: NotchController) {
        self.screen = screen
        self.controller = controller
        state.autoHide = IslandVisibility.autoHide
        applyAppearance()

        let root = NotchView()
            .environmentObject(state)
            .environmentObject(controller.media)
            .environmentObject(controller.battery)
            .environmentObject(controller.weather)
            .environmentObject(controller.calendar)
            .environmentObject(controller.audio)
            .environmentObject(controller.system)
            .environmentObject(controller.system.alerts)
            .environmentObject(controller.hud)
            .environmentObject(controller.shelf)
            .environmentObject(controller.privacy)
            .environmentObject(controller.caffeine)
            .environmentObject(controller.countdown)
            .environmentObject(controller.lyrics)
            .environment(\.locale, AppLanguage.locale)
        let host = FirstMouseHostingView(rootView: AnyView(root))
        if #available(macOS 13.0, *) { host.sizingOptions = [] }
        panel.contentView = host

        layout()
        panel.orderFrontRegardless()
    }

    private func layout() {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            state.notchSize = CGSize(width: screen.frame.width - left.width - right.width,
                                     height: screen.safeAreaInsets.top)
            state.hasNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            state.notchSize = CGSize(width: Metrics.pillWidth, height: menuBar > 20 ? menuBar : 25)
            state.hasNotch = false
        }
        let w = Metrics.window
        panel.setFrame(NSRect(x: screen.frame.midX - w.width / 2,
                              y: screen.frame.maxY - w.height,
                              width: w.width, height: w.height),
                       display: true)
    }

    func applyAppearance() {
        state.bgGradient = Appearance.artworkGradient(controller.media.palette)
    }

    func tick(mouse: NSPoint) {
        let size = state.islandSize(mediaActive: controller.media.isActive,
                                    hud: controller.hud.active,
                                    meeting: controller.calendar.upcoming != nil || controller.system.alerts.alert != nil
                                        || controller.countdown.running)
        let margin: CGFloat = state.expanded ? 14 : 8
        let rect = NSRect(x: screen.frame.midX - size.width / 2 - margin,
                          y: screen.frame.maxY - size.height - margin,
                          width: size.width + margin * 2,
                          height: size.height + margin + 2)
        let inside = rect.contains(mouse)

        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !state.expanded {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                withAnimation(expandAnimation) { state.expanded = true }
            }
        } else if state.expanded, collapseWork == nil, !controller.isMenuOpen {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                withAnimation(self.collapseAnimation) { self.state.expanded = false }
                self.collapseWork = nil
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    func close() {
        collapseWork?.cancel()
        panel.orderOut(nil)
        panel.close()
    }
}

// MARK: - Controlador general + menú de la barra

final class NotchController: NSObject, NSMenuDelegate {
    let media = MediaController()
    let battery = BatteryMonitor()
    let weather = WeatherService()
    let calendar = CalendarService()
    let audio = AudioOutputMonitor()
    let system = SystemMonitor()
    let hud = HUDController()
    let shelf = ShelfStore()
    let privacy = PrivacyMonitor()
    let caffeine = CaffeineController()
    let countdown = TimerController()
    let lyrics = LyricsService()
    private var trackSub: AnyCancellable?
    private(set) lazy var brightness = BrightnessMonitor(hud: hud)
    private lazy var keyTap = MediaKeyTap(audio: audio, brightness: brightness)

    /// Mientras hay un menú abierto la isla no se cierra.
    private(set) var isMenuOpen = false

    private var islands: [IslandWindow] = []
    private var accentSub: AnyCancellable?
    private var timer: Timer?
    private var statusItem: NSStatusItem?

    func show() {
        setupStatusItem()
        rebuild()
        media.start()
        battery.onChargingStarted = { [weak self] in
            guard let self else { return }
            self.hud.show(.battery, level: Float(self.battery.level) / 100)
        }
        battery.start()
        weather.start()
        calendar.start()
        audio.hud = hud
        audio.start()
        brightness.start()
        keyTap.update()
        system.start()
        privacy.start()
        countdown.alerts = system.alerts
        // Letras: buscar al cambiar de canción
        trackSub = media.$track
            .receive(on: RunLoop.main)
            .sink { [weak self] t in
                guard let t else { self?.lyrics.clear(); return }
                self?.lyrics.load(title: t.title, artist: t.artist, album: t.album, duration: t.duration)
            }

        // Tema «Según la carátula»: recolorear al cambiar de canción
        accentSub = media.$palette
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyAppearanceToAll() }

        NotificationCenter.default.addObserver(forName: .showPopupMenu, object: nil, queue: .main) { [weak self] note in
            guard let self, let items = note.object as? [PopupItem] else { return }
            let menu = PopupMenu.build(items)
            menu.title = "outputs"   // no lo repuebla menuNeedsUpdate
            menu.delegate = self
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        NotificationCenter.default.addObserver(forName: .showOptionsMenu, object: nil, queue: .main) { [weak self] _ in
            self?.popUpOptionsMenu()
        }
        NotificationCenter.default.addObserver(forName: .showOutputMenu, object: nil, queue: .main) { [weak self] _ in
            self?.popUpOutputMenu()
        }
        // Denon Remote: muestra en la isla el volumen del amplificador Denon
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.jorgeoteo.denonremote.volume"), object: nil, queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo, let level = info["level"] as? Double else { return }
            self?.hud.show(.volume, level: Float(max(0, min(1, level))), muted: info["muted"] as? Bool ?? false)
        }

        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            self.islands.forEach { $0.tick(mouse: mouse) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Se llama al cambiar de modo o al conectar/desconectar pantallas.
    func rebuild() {
        islands.forEach { $0.close() }
        islands = targetScreens().map { IslandWindow(screen: $0, controller: self) }
    }

    private func targetScreens() -> [NSScreen] {
        let all = NSScreen.screens
        let builtin = all.filter(\.isBuiltin)
        let external = all.filter { !$0.isBuiltin }
        let fallback = Array(all.prefix(1)) // la pantalla con la barra de menús
        switch DisplayMode.current {
        case .builtin: return builtin.isEmpty ? fallback : builtin
        case .external: return external.isEmpty ? fallback : external
        case .all: return all
        }
    }

    // MARK: Menú

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Muesca")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) { isMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }

    /// Botón ⚙︎ de la isla: el mismo menú que el icono de la barra.
    private func popUpOptionsMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Chip de salida de audio: lista de dispositivos para cambiar.
    private func popUpOutputMenu() {
        audio.refresh()
        let menu = NSMenu(title: "outputs")
        menu.delegate = self
        menu.addItem(header(L("menu.output")))
        for d in audio.devices {
            let mi = NSMenuItem(title: d.name, action: #selector(selectOutput(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = Int(d.id)
            mi.state = d.id == audio.current?.id ? .on : .off
            mi.image = NSImage(systemSymbolName: d.symbol, accessibilityDescription: nil)
            menu.addItem(mi)
        }
        // Bluetooth emparejados sin conectar
        let bt = audio.disconnectedBluetoothAudio()
        if !bt.isEmpty {
            menu.addItem(.separator())
            menu.addItem(header(L("menu.bluetooth")))
            for d in bt {
                let mi = NSMenuItem(title: d.name, action: #selector(connectBluetooth(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = d.address
                mi.image = NSImage(systemSymbolName: AudioOutputMonitor.bluetoothSymbol(for: d.name), accessibilityDescription: nil)
                menu.addItem(mi)
            }
        }

        // AirPlay: selector oficial del sistema
        menu.addItem(.separator())
        let airplay = NSMenuItem(title: L("menu.airplay"), action: #selector(showAirPlayPicker), keyEquivalent: "")
        airplay.target = self
        airplay.image = NSImage(systemSymbolName: "airplayaudio", accessibilityDescription: nil)
        menu.addItem(airplay)
        add(menu, L("menu.soundSettings"), #selector(openSoundSettings))
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func connectBluetooth(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String,
              let d = audio.disconnectedBluetoothAudio().first(where: { $0.address == address }) else { return }
        audio.connectBluetooth(d)
    }

    @objc private func showAirPlayPicker() {
        // Se abre tras cerrarse el menú, anclado al botón AirPlay de la isla.
        DispatchQueue.main.async { RoutePicker.show() }
    }

    @objc private func selectOutput(_ sender: NSMenuItem) {
        audio.select(AudioDeviceID(sender.tag))
    }

    @objc private func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title != "outputs" else { return }
        menu.removeAllItems()

        menu.addItem(header(L("menu.showOn")))
        for mode in DisplayMode.allCases {
            let mi = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode.rawValue
            mi.state = DisplayMode.current == mode ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        menu.addItem(header(L("menu.tools")))
        let caf = NSMenuItem(title: L("caffeine.menu"), action: #selector(toggleCaffeine), keyEquivalent: "")
        caf.target = self
        caf.state = caffeine.active ? .on : .off
        caf.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil)
        menu.addItem(caf)
        let timerItem = NSMenuItem(title: L("timer.menu"), action: nil, keyEquivalent: "")
        timerItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let tm = NSMenu()
        for m in [5, 10, 15, 25, 30, 45, 60] {
            let mi = NSMenuItem(title: L("timer.minutes", m), action: #selector(startTimer(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = m
            tm.addItem(mi)
        }
        if countdown.running {
            tm.addItem(.separator())
            add(tm, L("timer.cancel"), #selector(cancelTimer))
        }
        timerItem.submenu = tm
        menu.addItem(timerItem)

        menu.addItem(.separator())
        menu.addItem(header(L("menu.visibility")))
        for (hide, key) in [(false, "vis.always"), (true, "vis.hidden")] {
            let mi = NSMenuItem(title: L(key), action: #selector(selectVisibility(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = hide ? 1 : 0
            mi.state = IslandVisibility.autoHide == hide ? .on : .off
            menu.addItem(mi)
        }

        let replace = NSMenuItem(title: L("menu.replaceHUD"), action: #selector(toggleReplaceHUD), keyEquivalent: "")
        replace.target = self
        replace.state = MediaKeyTap.enabled ? (MediaKeyTap.isTrusted ? .on : .mixed) : .off
        menu.addItem(replace)
        if MediaKeyTap.enabled && !MediaKeyTap.isTrusted {
            add(menu, L("menu.grantAccessibility"), #selector(openAccessibility))
        }


        menu.addItem(.separator())
        menu.addItem(header(L("menu.weather")))
        let useLoc = NSMenuItem(title: L("menu.useLocation"), action: #selector(useLocation), keyEquivalent: "")
        useLoc.target = self
        useLoc.state = weather.manualCity.isEmpty ? .on : .off
        menu.addItem(useLoc)
        let cityTitle = weather.manualCity.isEmpty ? L("menu.chooseCity") : L("menu.city", weather.manualCity)
        let city = NSMenuItem(title: cityTitle, action: #selector(chooseCity), keyEquivalent: "")
        city.target = self
        city.state = weather.manualCity.isEmpty ? .off : .on
        menu.addItem(city)

        // Calendario: solo aparece si falta el permiso.
        if calendar.access != .granted {
            menu.addItem(.separator())
            menu.addItem(header(L("menu.calendar")))
            if calendar.access == .notDetermined {
                add(menu, L("menu.allowCalendar"), #selector(requestCalendar))
            } else {
                add(menu, L("menu.calendarSettings"), #selector(openCalendarPrivacy))
            }
        }


        menu.addItem(.separator())
        let login = NSMenuItem(title: L("menu.launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on
        case .requiresApproval: login.state = .mixed
        default: login.state = .off
        }
        menu.addItem(login)
        if SMAppService.mainApp.status == .requiresApproval {
            add(menu, L("menu.loginApproval"), #selector(openLoginItems))
        }

        menu.addItem(.separator())
        let help = NSMenuItem(title: L("menu.help"), action: #selector(showHelp), keyEquivalent: "?")
        help.target = self
        help.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        menu.addItem(help)
        add(menu, L("menu.about", AppInfo.version, AppInfo.build), #selector(showAbout))
        let madeBy = NSMenuItem(title: L("menu.madeBy", AppInfo.author, AppInfo.revisionDate), action: nil, keyEquivalent: "")
        madeBy.isEnabled = false
        menu.addItem(madeBy)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        menu.addItem(mi)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) else { return }
        DisplayMode.current = mode
        rebuild()
    }

    func applyAppearanceToAll() {
        islands.forEach { island in
            withAnimation(.easeInOut(duration: 0.3)) { island.applyAppearance() }
        }
    }

    @objc private func toggleCaffeine() { caffeine.toggle() }
    @objc private func startTimer(_ sender: NSMenuItem) { countdown.start(minutes: sender.tag) }
    @objc private func cancelTimer() { countdown.cancel() }

    @objc private func toggleReplaceHUD() {
        MediaKeyTap.enabled.toggle()
        keyTap.update()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func selectVisibility(_ sender: NSMenuItem) {
        IslandVisibility.autoHide = sender.tag == 1
        islands.forEach { island in
            withAnimation(.easeInOut(duration: 0.25)) { island.state.autoHide = IslandVisibility.autoHide }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            Log.write("Login item error: \(error)")
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    @objc private func useLocation() { weather.setManualCity("") }

    @objc private func chooseCity() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("city.title")
        alert.informativeText = L("city.info")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = weather.manualCity
        alert.accessoryView = field
        alert.addButton(withTitle: L("city.save"))
        alert.addButton(withTitle: L("city.cancel"))
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            weather.setManualCity(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    @objc private func openCalendar() { calendar.openCalendarApp() }
    @objc private func requestCalendar() { calendar.requestAccess() }
    @objc private func openCalendarPrivacy() { calendar.openPrivacySettings() }
    @objc private func quit() {
        caffeine.stop()
        NSApp.terminate(nil)
    }

    @objc private func showHelp() { HelpWindow.show() }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let credits = NSAttributedString(
            string: L("about.credits", AppInfo.author, AppInfo.revisionDate),
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.labelColor,
                         .paragraphStyle: style]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: AppInfo.version,
            .version: AppInfo.build,
            .credits: credits
        ])
    }
}
