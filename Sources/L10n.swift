import Foundation

// MARK: - Idioma de la app

enum AppLanguage: String, CaseIterable {
    case auto, es, en

    /// Siempre sigue el idioma de macOS (sin selector en el menú).
    static var setting: AppLanguage { .auto }

    /// Idioma efectivo: "es" o "en". En automático sigue el idioma del sistema.
    static var resolved: String {
        switch setting {
        case .es: return "es"
        case .en: return "en"
        case .auto:
            let first = Locale.preferredLanguages.first ?? "es"
            return first.hasPrefix("es") ? "es" : "en"
        }
    }

    /// Locale para fechas y horas.
    static var locale: Locale {
        switch setting {
        case .auto: return Locale.current
        case .es: return Locale(identifier: "es_ES")
        case .en: return Locale(identifier: "en_GB")
        }
    }

    var menuTitle: String {
        switch self {
        case .auto: return L("lang.auto")
        case .es: return "Español"
        case .en: return "English"
        }
    }
}

/// Texto traducido.
func L(_ key: String) -> String {
    let table = AppLanguage.resolved == "es" ? Strings.es : Strings.en
    return table[key] ?? Strings.es[key] ?? key
}

/// Texto traducido con argumentos (formato printf: %@, %d).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: AppLanguage.locale, arguments: args)
}

// MARK: - Datos de autoría y versión

enum AppInfo {
    static let author = "Jorge Oteo"

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }

    /// Fecha de la última revisión, escrita en el Info.plist al compilar (build.sh).
    static var revisionDate: String {
        guard let iso = Bundle.main.infoDictionary?["MuescaRevisionDate"] as? String else { return "—" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = AppLanguage.locale
        out.dateStyle = .long
        out.timeStyle = .none
        return out.string(from: date)
    }
}

// MARK: - Textos

enum Strings {
    static let es: [String: String] = [
        // Menú
        "menu.showOn": "Mostrar la isla en",
        "mode.builtin": "Pantalla del MacBook",
        "mode.external": "Monitores externos",
        "mode.all": "Todas las pantallas",
        "menu.visibility": "Visibilidad",
        "menu.tools": "Herramientas",
        "caffeine.menu": "Mantener el Mac despierto",
        "caffeine.on": "El Mac no se dormirá · clic para desactivar",
        "caffeine.off": "Mantener el Mac despierto",
        "timer.menu": "Temporizador",
        "timer.minutes": "%d minutos",
        "timer.cancel": "Cancelar temporizador",
        "timer.help": "Temporizador (Pomodoro): elige la duración",
        "timer.runningHelp": "Temporizador en marcha · clic para cambiar o cancelar",
        "timer.done": "¡Tiempo!",
        "timer.doneDetail": "Temporizador terminado",
        "privacy.mic": "Micrófono en uso",
        "privacy.camera": "Cámara en uso",
        "media.seekHelp": "Clic o arrastra para saltar a ese punto",
        "share.airdrop": "Enviar por AirDrop",
        "shelf.more": "Más opciones: abrir, mostrar, compartir…",
        "share.mail": "Enviar por Correo",
        "share.outlook": "Enviar por Outlook",
        "share.messages": "Enviar por Mensajes",
        "menu.replaceHUD": "Sustituir el HUD del sistema (volumen y brillo)",
        "menu.grantAccessibility": "Dar permiso de Accesibilidad…",
        "vis.always": "Siempre visible",
        "vis.hidden": "Oculta (aparece al pasar el ratón)",
        "menu.appearance": "Apariencia",
        "app.theme": "Tema",
        "theme.dark": "Oscuro",
        "theme.light": "Claro",
        "theme.system": "Automático (claro/oscuro del sistema)",
        "theme.wallpaper": "Según el fondo de pantalla",
        "theme.artwork": "Según la carátula de la música",
        "app.transparency": "Transparencia",
        "app.opaque": "Opaca",
        "app.corners": "Bordes",
        "corners.rounded": "Redondeados",
        "corners.square": "Rectos",
        "menu.weather": "Tiempo",
        "menu.useLocation": "Usar mi ubicación",
        "menu.chooseCity": "Elegir ciudad…",
        "menu.city": "Ciudad: %@…",
        "menu.calendar": "Calendario",
        "menu.openCalendar": "Abrir Calendario",
        "menu.allowCalendar": "Permitir acceso a mis calendarios",
        "menu.calendarSettings": "Dar acceso en Ajustes del Sistema…",
        "menu.language": "Idioma",
        "lang.auto": "Automático (idioma del sistema)",
        "menu.about": "Acerca de Muesca — versión %@ (%@)",
        "menu.madeBy": "Hecho por %@ · revisión del %@",
        "menu.quit": "Salir de Muesca",
        "menu.help": "Ayuda de Muesca…",
        "help.title": "Ayuda de Muesca",
        "menu.launchAtLogin": "Abrir al iniciar sesión",
        "menu.loginApproval": "Aprobar en Ajustes del Sistema…",
        "volume.help": "Volumen — clic en el altavoz para silenciar",
        "weather.open": "Abrir la app Tiempo",
        "sys.help": "Rendimiento del sistema",
        "tab.music": "Música",
        "tab.shelf": "Bandeja de archivos",
        "shelf.empty": "Arrastra aquí archivos para tenerlos a mano",
        "shelf.title": "Bandeja · %d",
        "shelf.clear": "Vaciar",
        "shelf.open": "Abrir",
        "shelf.reveal": "Mostrar en Finder",
        "shelf.remove": "Quitar de la bandeja",
        "shelf.itemHelp": "Arrástralo para usarlo · doble clic para abrir · ⋯ o clic derecho para compartir",
        "meet.inMin": "en %d min",
        "meet.now": "Ahora",
        "meet.nowUntil": "Ahora · hasta %@",
        "meet.join": "Unirse",
        "meet.joinHelp": "Abrir el enlace de la reunión",
        "sys.backToMusic": "Volver a la música",
        "sys.open": "Abrir Monitor de Actividad",
        "sys.memory": "Memoria",
        "sys.disk": "Disco",
        "sys.free": "%@ libres",
        "sys.network": "Red",
        "sys.gpu": "GPU",
        "sys.pressure.normal": "presión normal",
        "sys.pressure.warn": "presión alta",
        "sys.pressure.critical": "presión crítica",
        "sys.health": "Salud %d %%",
        "sys.cycles": "%d ciclos",
        "sys.drawAC": "Consumo %@",
        "sys.drawBattery": "Gasto %@",
        "sys.cpu1min": "CPU · último minuto",
        "sys.showApp": "Mostrar",
        "sys.forceQuit": "Forzar salida",
        "sys.processHelp": "Clic para mostrar · clic derecho para forzar salida",
        "alert.cpu": "CPU %d %%",
        "alert.thermal": "Mac caliente",
        "alert.thermalDetail": "Temperatura alta",
        "alert.disk": "Disco casi lleno",
        "alert.diskDetail": "Quedan %@",
        "sys.thermal.nominal": "Temp. normal",
        "sys.thermal.fair": "Temp. moderada",
        "sys.thermal.serious": "Temp. alta",
        "sys.thermal.critical": "Temp. crítica",
        "battery.open": "Ajustes de batería",
        "menu.output": "Salida de sonido",
        "menu.soundSettings": "Ajustes de sonido…",
        "menu.bluetooth": "Bluetooth (clic para conectar)",
        "menu.airplay": "AirPlay…",
        "airplay.help": "AirPlay y otras salidas",
        // Ciudad
        "city.title": "Ciudad para el tiempo",
        "city.info": "Escribe una ciudad, por ejemplo Madrid o Valencia.",
        "city.save": "Guardar",
        "city.cancel": "Cancelar",
        // Acerca de
        "about.credits": "Hecho por %@\nÚltima revisión: %@\n\nIsla dinámica para el notch: música, salida de sonido, tiempo y agenda.",
        // Isla
        "options.help": "Opciones: pantalla, tiempo, calendario…",
        // Denon Remote
        "denon.radio": "Radio",
        "denon.live": "En directo",
        "denon.phono": "Tocadiscos",
        "denon.vinyl": "Vinilo",
        "denon.onRadio": "Sonando en el Denon · radio",
        "denon.onPhono": "Sonando en el Denon · tocadiscos",
        "denon.open": "Abrir Denon Remote",
        "denon.stop": "Parar la radio",
        "denon.power": "Apagar el Denon",
        "denon.volUp": "Subir volumen del Denon",
        "denon.volDown": "Bajar volumen del Denon",
        "menu.translateLyrics": "Traducir la letra",
        "media.nothing": "Nada en reproducción",
        "media.nothingHint": "Pon música en Spotify o Música y aparecerá aquí",
        "media.open": "Abrir %@",
        "media.music": "Música",
        "output.help": "Salida de sonido — clic para cambiarla",
        "weather.help": "%@ · máx %d° · mín %d° — clic para abrir Tiempo",
        // Agenda
        "agenda.title": "Agenda",
        "agenda.modeMonth": "Ver el mes",
        "agenda.modeList": "Ver por días",
        "agenda.yesterday": "Ayer",
        "month.today": "Volver a hoy",
        "month.noEvents": "Sin eventos este día",
        "month.more": "y %d más",
        "agenda.empty": "Nada más por hoy ni mañana",
        "agenda.needAccess": "Para ver tus eventos, permite el acceso.",
        "agenda.allow": "Permitir acceso",
        "agenda.denied": "Muesca no tiene acceso a tus calendarios.",
        "agenda.openSettings": "Abrir Ajustes",
        "agenda.today": "Hoy",
        "agenda.tomorrow": "Mañana",
        "agenda.allDay": "Todo el día",
        "agenda.allDayShort": "Día",
        "agenda.nowUntil": "Ahora · hasta las %@",
        "agenda.untitled": "(Sin título)",
        // Tiempo
        "wx.0": "Despejado", "wx.1": "Mayormente despejado", "wx.2": "Parcialmente nublado",
        "wx.3": "Nublado", "wx.fog": "Niebla", "wx.drizzle": "Llovizna", "wx.rain": "Lluvia",
        "wx.snow": "Nieve", "wx.showers": "Chubascos", "wx.snowShowers": "Chubascos de nieve",
        "wx.storm": "Tormenta",
    ]

    static let en: [String: String] = [
        "menu.showOn": "Show the island on",
        "mode.builtin": "MacBook display",
        "mode.external": "External displays",
        "mode.all": "All displays",
        "menu.visibility": "Visibility",
        "menu.tools": "Tools",
        "caffeine.menu": "Keep the Mac awake",
        "caffeine.on": "The Mac won't sleep · click to turn off",
        "caffeine.off": "Keep the Mac awake",
        "timer.menu": "Timer",
        "timer.minutes": "%d minutes",
        "timer.cancel": "Cancel timer",
        "timer.help": "Timer (Pomodoro): choose a duration",
        "timer.runningHelp": "Timer running · click to change or cancel",
        "timer.done": "Time's up!",
        "timer.doneDetail": "Timer finished",
        "privacy.mic": "Microphone in use",
        "privacy.camera": "Camera in use",
        "media.seekHelp": "Click or drag to jump to that point",
        "share.airdrop": "Send via AirDrop",
        "shelf.more": "More: open, show, share…",
        "share.mail": "Send via Mail",
        "share.outlook": "Send via Outlook",
        "share.messages": "Send via Messages",
        "menu.replaceHUD": "Replace the system HUD (volume and brightness)",
        "menu.grantAccessibility": "Grant Accessibility permission…",
        "vis.always": "Always visible",
        "vis.hidden": "Hidden (shows on hover)",
        "menu.appearance": "Appearance",
        "app.theme": "Theme",
        "theme.dark": "Dark",
        "theme.light": "Light",
        "theme.system": "Automatic (system light/dark)",
        "theme.wallpaper": "Match wallpaper",
        "theme.artwork": "Match album art",
        "app.transparency": "Transparency",
        "app.opaque": "Opaque",
        "app.corners": "Corners",
        "corners.rounded": "Rounded",
        "corners.square": "Square",
        "menu.weather": "Weather",
        "menu.useLocation": "Use my location",
        "menu.chooseCity": "Choose city…",
        "menu.city": "City: %@…",
        "menu.calendar": "Calendar",
        "menu.openCalendar": "Open Calendar",
        "menu.allowCalendar": "Allow access to my calendars",
        "menu.calendarSettings": "Grant access in System Settings…",
        "menu.language": "Language",
        "lang.auto": "Automatic (system language)",
        "menu.about": "About Muesca — version %@ (%@)",
        "menu.madeBy": "Made by %@ · revised %@",
        "menu.quit": "Quit Muesca",
        "menu.help": "Muesca Help…",
        "help.title": "Muesca Help",
        "menu.launchAtLogin": "Open at login",
        "menu.loginApproval": "Approve in System Settings…",
        "volume.help": "Volume — click the speaker to mute",
        "weather.open": "Open the Weather app",
        "sys.help": "System performance",
        "tab.music": "Music",
        "tab.shelf": "File shelf",
        "shelf.empty": "Drop files here to keep them handy",
        "shelf.title": "Shelf · %d",
        "shelf.clear": "Clear",
        "shelf.open": "Open",
        "shelf.reveal": "Show in Finder",
        "shelf.remove": "Remove from shelf",
        "shelf.itemHelp": "Drag it out to use it · double-click to open",
        "meet.inMin": "in %d min",
        "meet.now": "Now",
        "meet.nowUntil": "Now · until %@",
        "meet.join": "Join",
        "meet.joinHelp": "Open the meeting link",
        "sys.backToMusic": "Back to music",
        "sys.open": "Open Activity Monitor",
        "sys.memory": "Memory",
        "sys.disk": "Disk",
        "sys.free": "%@ free",
        "sys.network": "Network",
        "sys.gpu": "GPU",
        "sys.pressure.normal": "normal pressure",
        "sys.pressure.warn": "high pressure",
        "sys.pressure.critical": "critical pressure",
        "sys.health": "Health %d %%",
        "sys.cycles": "%d cycles",
        "sys.drawAC": "Using %@",
        "sys.drawBattery": "Draining %@",
        "sys.cpu1min": "CPU · last minute",
        "sys.showApp": "Show",
        "sys.forceQuit": "Force Quit",
        "sys.processHelp": "Click to show · right-click to force quit",
        "alert.cpu": "CPU %d %%",
        "alert.thermal": "Mac is hot",
        "alert.thermalDetail": "High temperature",
        "alert.disk": "Disk almost full",
        "alert.diskDetail": "%@ left",
        "sys.thermal.nominal": "Temp. normal",
        "sys.thermal.fair": "Temp. moderate",
        "sys.thermal.serious": "Temp. high",
        "sys.thermal.critical": "Temp. critical",
        "battery.open": "Battery settings",
        "menu.output": "Sound output",
        "menu.soundSettings": "Sound settings…",
        "menu.bluetooth": "Bluetooth (click to connect)",
        "menu.airplay": "AirPlay…",
        "airplay.help": "AirPlay and other outputs",
        "city.title": "City for the weather",
        "city.info": "Type a city, for example Madrid or London.",
        "city.save": "Save",
        "city.cancel": "Cancel",
        "about.credits": "Made by %@\nLast revision: %@\n\nA dynamic island for the notch: music, sound output, weather and agenda.",
        "options.help": "Options: display, weather, calendar…",
        // Denon Remote
        "denon.radio": "Radio",
        "denon.live": "Live",
        "denon.phono": "Turntable",
        "denon.vinyl": "Vinyl",
        "denon.onRadio": "Playing on the Denon · radio",
        "denon.onPhono": "Playing on the Denon · turntable",
        "denon.open": "Open Denon Remote",
        "denon.stop": "Stop the radio",
        "denon.power": "Turn off the Denon",
        "denon.volUp": "Denon volume up",
        "denon.volDown": "Denon volume down",
        "menu.translateLyrics": "Translate lyrics",
        "media.nothing": "Nothing playing",
        "media.nothingHint": "Play something in Spotify or Music and it will show up here",
        "media.open": "Open %@",
        "media.music": "Music",
        "output.help": "Sound output — click to change it",
        "weather.help": "%@ · high %d° · low %d° — click to open Weather",
        "agenda.title": "Agenda",
        "agenda.modeMonth": "Show month",
        "agenda.modeList": "Show by day",
        "agenda.yesterday": "Yesterday",
        "month.today": "Back to today",
        "month.noEvents": "No events this day",
        "month.more": "and %d more",
        "agenda.empty": "Nothing else today or tomorrow",
        "agenda.needAccess": "Allow access to see your events.",
        "agenda.allow": "Allow access",
        "agenda.denied": "Muesca can't access your calendars.",
        "agenda.openSettings": "Open Settings",
        "agenda.today": "Today",
        "agenda.tomorrow": "Tomorrow",
        "agenda.allDay": "All day",
        "agenda.allDayShort": "All day",
        "agenda.nowUntil": "Now · until %@",
        "agenda.untitled": "(No title)",
        "wx.0": "Clear", "wx.1": "Mostly clear", "wx.2": "Partly cloudy",
        "wx.3": "Cloudy", "wx.fog": "Fog", "wx.drizzle": "Drizzle", "wx.rain": "Rain",
        "wx.snow": "Snow", "wx.showers": "Showers", "wx.snowShowers": "Snow showers",
        "wx.storm": "Thunderstorm",
    ]
}
