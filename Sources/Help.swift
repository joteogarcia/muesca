import AppKit
import SwiftUI

// MARK: - Contenido de la ayuda

struct HelpSection: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: [String]   // párrafos; los que empiezan por "• " se muestran como viñetas
}

enum HelpContent {
    static var sections: [HelpSection] { AppLanguage.resolved == "es" ? es : en }

    static let es: [HelpSection] = [
        HelpSection(icon: "sparkles", title: "Qué es Muesca", body: [
            "Muesca convierte el notch de tu MacBook (o el centro de la barra de menús en un monitor externo) en una isla dinámica: te muestra lo importante de un vistazo y se abre al pasar el ratón por encima."
        ]),
        HelpSection(icon: "capsule", title: "La isla cerrada", body: [
            "• Con música: carátula a un lado y ecualizador al otro (en el monitor externo, también el título).",
            "• Sin música: tiempo, hora, fecha y batería.",
            "• Al cambiar volumen o brillo, o al enchufar el cargador, aparece un indicador durante un segundo y medio.",
            "• 5 minutos antes de una reunión verás la cuenta atrás y el título del evento."
        ]),
        HelpSection(icon: "rectangle.expand.vertical", title: "La isla abierta", body: [
            "Pasa el ratón por el notch para abrirla. Junto a la fecha hay tres pestañas:",
            "• ♪ Música: carátula, título, progreso, controles, salida de sonido y volumen.",
            "• 🎛 Rendimiento: CPU, memoria (con su presión), GPU y disco; salud, ciclos y consumo de la batería; gráficas del último minuto de CPU y red; y las 3 apps que más consumen (clic para mostrarla, clic derecho para forzar salida). Si la CPU se queda al máximo, el Mac se calienta o queda poco disco, la isla cerrada te avisa.",
            "• 📥 Bandeja de archivos (ver abajo).",
            "A la derecha está tu agenda. El botón ▦ cambia entre los próximos eventos y el mes en cuadrícula; pulsa un día para ver sus eventos. Si un evento tiene enlace de Teams, Meet, Zoom o Webex, aparece el botón «Unirse»."
        ]),
        HelpSection(icon: "tray.and.arrow.down", title: "Bandeja de archivos", body: [
            "Es un bolsillo temporal para archivos: los dejas cuando los tienes en un sitio y los sacas cuando estás en otro, sin abrir dos ventanas de Finder ni copiar rutas.",
            "Cómo se usa: arrastra uno o varios archivos al notch (la isla se abre sola en la bandeja). Para usarlos, arrástralos hacia fuera. Doble clic abre el archivo; la ✕ lo quita; clic derecho → «Mostrar en Finder».",
            "Usos típicos:",
            "• Adjuntar a un correo o a Teams: vas soltando en el notch el PDF, el Excel y la presentación mientras navegas por carpetas, y luego los arrastras los tres al mensaje.",
            "• Mover entre Escritorios o pantallas: deja el archivo en el notch, cambia de Escritorio o de pantalla y sácalo allí.",
            "• Reunir material para un documento: capturas, logos y gráficos de varias carpetas, todos a mano cuando montes las diapositivas.",
            "• Subir a webs (portales, intranet, LinkedIn): arrastra desde la bandeja al navegador en vez de buscar en «Seleccionar archivo».",
            "• Tener a mano lo de hoy: los archivos con los que trabajas toda la mañana, a un doble clic.",
            "Importante: la bandeja guarda accesos a los archivos, no copias. No ocupa espacio, pero si mueves o borras el original, desaparece de la bandeja. «Vaciar» la deja limpia."
        ]),
        HelpSection(icon: "speaker.wave.2", title: "Sonido, volumen y brillo", body: [
            "• Clic en la etiqueta de salida para cambiar entre altavoces, auriculares USB, Bluetooth emparejados (se conectan con un clic) o AirPlay.",
            "• Arrastra la barra para el volumen; clic en el altavoz para silenciar.",
            "• Con «Sustituir el HUD del sistema», las teclas de volumen y brillo muestran el indicador solo en el notch. El brillo se aplica a la pantalla donde está el puntero (también monitores externos compatibles con DDC). Con ⌥ Opción + ⇧ Mayúsculas el ajuste es más fino."
        ]),
        HelpSection(icon: "hand.tap", title: "Atajos y clics", body: [
            "• Clic en la carátula: abre Spotify o Música.",
            "• Clic en el tiempo: abre la app Tiempo.",
            "• Clic en la batería: abre los ajustes de batería.",
            "• Clic en el icono de calendario: abre Calendario.",
            "• Taza ☕: mantiene el Mac despierto. Tomate: temporizador (Pomodoro), con los minutos que quedan a su lado."
        ]),
        HelpSection(icon: "gearshape", title: "Opciones (⚙︎)", body: [
            "• Pantalla: MacBook, monitores externos o todas.",
            "• Visibilidad: siempre visible u oculta hasta pasar el ratón.",
            "• Apariencia: tema (oscuro, claro, automático, según el fondo de pantalla o según la carátula), transparencia y bordes.",
            "• Tiempo: tu ubicación o una ciudad fija.",
            "• Abrir al iniciar sesión, Acerca de y Salir."
        ])
    ]

    static let en: [HelpSection] = [
        HelpSection(icon: "sparkles", title: "What Muesca is", body: [
            "Muesca turns your MacBook's notch (or the centre of the menu bar on an external display) into a dynamic island: it shows what matters at a glance and opens when you hover over it."
        ]),
        HelpSection(icon: "capsule", title: "The closed island", body: [
            "• With music: album art on one side and an equalizer on the other.",
            "• Without music: weather, time, date and battery.",
            "• When you change volume or brightness, or plug in the charger, an indicator appears for a moment.",
            "• 5 minutes before a meeting you'll see a countdown and the event title."
        ]),
        HelpSection(icon: "rectangle.expand.vertical", title: "The open island", body: [
            "Hover over the notch to open it. Next to the date there are three tabs:",
            "• ♪ Music: artwork, title, progress, controls, sound output and volume.",
            "• 🎛 Performance: CPU, memory, disk, network and temperature. Click a ring to open Activity Monitor.",
            "• 📥 File shelf (see below).",
            "Your agenda is on the right. The ▦ button switches between upcoming events and the month grid; click a day to see its events. Events with a Teams, Meet, Zoom or Webex link show a «Join» button."
        ]),
        HelpSection(icon: "tray.and.arrow.down", title: "File shelf", body: [
            "A temporary pocket for files: drop them where they are, pick them up where you need them — no need for two Finder windows.",
            "How: drag files onto the notch (the island opens on the shelf). Drag them out to use them. Double-click opens; ✕ removes; right-click → «Show in Finder».",
            "Typical uses:",
            "• Attaching to an email or Teams message.",
            "• Moving files between Spaces or displays.",
            "• Collecting material for a document or presentation.",
            "• Uploading to websites by dragging into the browser.",
            "• Keeping today's files one double-click away.",
            "Note: the shelf keeps references, not copies. If you move or delete the original, it disappears from the shelf."
        ]),
        HelpSection(icon: "speaker.wave.2", title: "Sound, volume and brightness", body: [
            "• Click the output label to switch between speakers, USB, paired Bluetooth devices (one click to connect) or AirPlay.",
            "• Drag the bar for volume; click the speaker to mute.",
            "• With «Replace the system HUD», volume and brightness keys show the indicator only in the notch. Hold ⌥ Option + ⇧ Shift for finer steps."
        ]),
        HelpSection(icon: "hand.tap", title: "Shortcuts and clicks", body: [
            "• Artwork: opens Spotify or Music. • Weather: opens Weather. • Battery: opens battery settings. • Calendar icon: opens Calendar."
        ]),
        HelpSection(icon: "gearshape", title: "Options (⚙︎)", body: [
            "• Display, visibility, weather city, open at login, About and Quit. The island takes the colours of the album art that is playing."
        ])
    ]
}

// MARK: - Ventana de ayuda

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "capsule.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("help.title")).font(.system(size: 22, weight: .bold))
                        Text(L("menu.madeBy", AppInfo.author, AppInfo.revisionDate) + " · v\(AppInfo.version)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(HelpContent.sections) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(section.title, systemImage: section.icon)
                            .font(.system(size: 15, weight: .semibold))
                        ForEach(Array(section.body.enumerated()), id: \.offset) { _, p in
                            if p.hasPrefix("• ") {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(String(p.dropFirst(2)))
                                }
                                .padding(.leading, 6)
                            } else {
                                Text(p)
                            }
                        }
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}

enum HelpWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 680),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = L("help.title")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HelpView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
