import AppKit
import SwiftUI
import CoreAudio
import CoreMediaIO
import IOKit.pwr_mgt
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif

// Funciones de prueba de la versión 1.31. Cada bloque es independiente:
// para quitar una, se borra su sección y su uso en NotchView / NotchController.

// MARK: - 1. Indicador de micrófono y cámara

final class PrivacyMonitor: ObservableObject {
    @Published private(set) var micInUse = false
    @Published private(set) var cameraInUse = false
    private var timer: Timer?

    func start() {
        poll()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let mic = Self.anyInputRunning()
        let cam = Self.anyCameraRunning()
        if mic != micInUse { withAnimation(.easeInOut(duration: 0.3)) { micInUse = mic } }
        if cam != cameraInUse { withAnimation(.easeInOut(duration: 0.3)) { cameraInUse = cam } }
    }

    private static func anyInputRunning() -> Bool {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return false }
        for id in ids {
            var sAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                   mScope: kAudioDevicePropertyScopeInput,
                                                   mElement: kAudioObjectPropertyElementMain)
            var sSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &sAddr, 0, nil, &sSize) == noErr, sSize > 0 else { continue }
            var rAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var rSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &rAddr, 0, nil, &rSize, &running) == noErr, running != 0 { return true }
        }
        return false
    }

    private static func anyCameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(sys, &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var rAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var u: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &rAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &running) == 0,
               running != 0 { return true }
        }
        return false
    }
}

// MARK: - 2. Mantener el Mac despierto (café)

final class CaffeineController: ObservableObject {
    @Published private(set) var active = false
    private var assertion: IOPMAssertionID = 0

    func toggle() { active ? stop() : start() }

    func start() {
        guard !active else { return }
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "Muesca: mantener el Mac despierto" as CFString,
                                             &assertion)
        if ok == kIOReturnSuccess { withAnimation { active = true } }
    }

    func stop() {
        guard active else { return }
        IOPMAssertionRelease(assertion)
        withAnimation { active = false }
    }
}

// MARK: - 3. Temporizador

final class TimerController: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var duration: TimeInterval = 0
    private var finishWork: DispatchWorkItem?
    weak var alerts: AlertCenter?

    var running: Bool { endDate != nil }

    func start(minutes: Int) {
        cancel()
        duration = TimeInterval(minutes * 60)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { endDate = Date().addingTimeInterval(duration) }
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func cancel() {
        finishWork?.cancel()
        finishWork = nil
        withAnimation { endDate = nil }
    }

    private func finish() {
        withAnimation { endDate = nil }
        NSSound(named: "Glass")?.play()
        alerts?.show(SystemMonitor.SysAlert(symbol: "timer", short: L("timer.done"),
                                            detail: L("timer.doneDetail"), color: .green), seconds: 8)
    }
}

extension AlertCenter {
    func show(_ a: SystemMonitor.SysAlert, seconds: Double) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { alert = a }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard self?.alert == a else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { self?.alert = nil }
        }
    }
}

// MARK: - 4. Letras sincronizadas (LRCLIB, gratis)

final class LyricsService: ObservableObject {
    struct Line { let time: Double; let text: String }
    @Published private(set) var lines: [Line] = []
    private var currentKey = ""

    // Traducción de la letra al idioma de Muesca (traductor de Apple, en el propio Mac)
    static var translateEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "translateLyrics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "translateLyrics") }
    }
    /// Índice de línea → traducción
    @Published private(set) var translations: [Int: String] = [:]
    /// La canción está en otro idioma: se reserva la segunda línea (fija durante toda la canción)
    @Published private(set) var translationExpected = false
    /// TranslationSession.Configuration (macOS 15+), guardada sin tipo para compilar en macOS 13
    @Published private(set) var translationConfig: Any?

    /// Busca la letra de ESA grabación: mismo álbum y duración (±2 s).
    /// Mejor sin letra que una letra de otra versión desincronizada.
    func load(title: String, artist: String, album: String, duration: Double) {
        let key = "\(artist)|\(title)|\(album)"
        guard key != currentKey else { return }
        currentKey = key
        lines = []
        guard !title.isEmpty else { return }

        Task { [weak self] in
            let titles = Array(NSOrderedSet(array: [title, Self.clean(title)])) as? [String] ?? [title]
            var lrc: String?
            // 1) Coincidencia exacta (álbum + duración) con /api/get
            for t in titles where lrc == nil {
                lrc = await Self.fetchExact(title: t, artist: artist, album: album, duration: duration)
            }
            // 2) Búsqueda, aceptando solo versiones de duración casi idéntica
            if lrc == nil {
                lrc = await Self.fetchSearch(title: Self.clean(title), artist: artist, album: album, duration: duration)
            }
            let parsed = lrc.map(Self.parse) ?? []
            await MainActor.run {
                guard self?.currentKey == key else { return }
                self?.lines = parsed
                self?.prepareTranslation()
            }
        }
    }

    private static func request(_ path: String, _ items: [URLQueryItem]) -> URLRequest? {
        var comps = URLComponents(string: "https://lrclib.net/api/\(path)")!
        comps.queryItems = items
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Muesca (uso personal)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        return req
    }

    private static func fetchExact(title: String, artist: String, album: String, duration: Double) async -> String? {
        var items = [URLQueryItem(name: "track_name", value: title),
                     URLQueryItem(name: "artist_name", value: artist),
                     URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        guard let req = request("get", items),
              let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lrc = obj["syncedLyrics"] as? String, !lrc.isEmpty else { return nil }
        if let d = obj["duration"] as? Double, abs(d - duration) > 2 { return nil }
        return lrc
    }

    private static func fetchSearch(title: String, artist: String, album: String, duration: Double) async -> String? {
        guard let req = request("search", [URLQueryItem(name: "track_name", value: title),
                                           URLQueryItem(name: "artist_name", value: artist)]),
              let (data, _) = try? await URLSession.shared.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let albumKey = album.lowercased()
        let candidates = arr.filter { item in
            guard let lrc = item["syncedLyrics"] as? String, !lrc.isEmpty,
                  let d = item["duration"] as? Double else { return false }
            return abs(d - duration) <= 2
        }
        // Preferir el mismo álbum; después, la duración más parecida
        let best = candidates.min { a, b in
            func score(_ x: [String: Any]) -> Double {
                let sameAlbum = (x["albumName"] as? String)?.lowercased().contains(albumKey) == true && !albumKey.isEmpty
                return abs(((x["duration"] as? Double) ?? 0) - duration) - (sameAlbum ? 10 : 0)
            }
            return score(a) < score(b)
        }
        return best?["syncedLyrics"] as? String
    }

    func clear() { currentKey = ""; lines = []; resetTranslation() }

    func line(at position: Double) -> String? {
        guard let i = index(at: position) else { return nil }
        return lines[i].text
    }

    /// Índice de la línea que suena (nil si es un hueco instrumental)
    func index(at position: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        let t = position + 0.3
        guard let i = lines.lastIndex(where: { $0.time <= t }), !lines[i].text.isEmpty else { return nil }
        return i
    }

    func translation(at position: Double) -> String? {
        guard let i = index(at: position) else { return nil }
        return translations[i]
    }

    // MARK: Traducción

    private func resetTranslation() {
        translations = [:]
        translationExpected = false
        translationConfig = nil
    }

    /// Detecta el idioma de la letra y, si no es el de Muesca, la traduce entera.
    func prepareTranslation() {
        resetTranslation()
        guard Self.translateEnabled, !lines.isEmpty else { return }
        let sample = lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let lang = recognizer.dominantLanguage, lang != .undetermined else { return }
        let source = lang.rawValue                          // "en", "fr"…
        let target = AppLanguage.resolved                   // "es" o "en"
        guard !source.hasPrefix(target) else { return }     // ya está en tu idioma
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            translationExpected = true
            let key = currentKey
            Task { [weak self] in await self?.startTranslation(source: source, target: target, key: key) }
        }
        #endif
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    @MainActor
    private func startTranslation(source: String, target: String, key: String) async {
        let src = Locale.Language(identifier: source), tgt = Locale.Language(identifier: target)
        let status = await LanguageAvailability().status(from: src, to: tgt)
        guard key == currentKey else { return }
        switch status {
        case .unsupported:
            translationExpected = false
        case .installed:
            if #available(macOS 26.0, *) {
                // Idiomas ya descargados: se traduce sin depender de ninguna vista
                await translate(with: TranslationSession(installedSource: src, target: tgt), key: key)
            } else {
                translationConfig = TranslationSession.Configuration(source: src, target: tgt)
            }
        default:
            // Hay que descargar el idioma: lo gestiona la vista (aviso de macOS)
            translationConfig = TranslationSession.Configuration(source: src, target: tgt)
        }
    }

    @available(macOS 15.0, *)
    @MainActor
    func translate(with session: TranslationSession, key: String? = nil) async {
        let key = key ?? currentKey
        let requests = lines.enumerated().compactMap { i, l in
            l.text.isEmpty ? nil : TranslationSession.Request(sourceText: l.text, clientIdentifier: String(i))
        }
        guard !requests.isEmpty,
              let responses = try? await session.translations(from: requests),
              key == currentKey else { return }
        var out: [Int: String] = [:]
        for r in responses {
            if let id = r.clientIdentifier, let i = Int(id) { out[i] = r.targetText }
        }
        withAnimation(.easeInOut(duration: 0.3)) { translations = out }
    }
    #endif

    /// "Deceiver - 2026 Remixed & Remastered" → "Deceiver"
    static func clean(_ title: String) -> String {
        var t = title
        if let r = t.range(of: " - ") { t = String(t[..<r.lowerBound]) }
        t = t.replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ lrc: String) -> [Line] {
        let regex = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\](.*)"#)
        var out: [Line] = []
        for raw in lrc.split(separator: "\n") {
            let s = String(raw)
            guard let m = regex?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let mr = Range(m.range(at: 1), in: s), let sr = Range(m.range(at: 2), in: s),
                  let tr = Range(m.range(at: 3), in: s),
                  let min = Double(s[mr]), let sec = Double(s[sr]) else { continue }
            let text = String(s[tr]).trimmingCharacters(in: .whitespaces)
            if isCredit(text) { continue }   // «作词 : …», «Composer: …»… no es letra
            out.append(Line(time: min * 60 + sec, text: text))
        }
        return out.sorted { $0.time < $1.time }
    }

    // Créditos que algunas fuentes meten como si fueran líneas de la letra.
    private static let creditRegex = try? NSRegularExpression(
        pattern: #"^(作词|作詞|作曲|编曲|編曲|词|詞|曲|制作人|製作人|监制|監製|混音|录音|和声|吉他|贝斯|鼓|lyrics?|lyricist|composer|composed|written|music|producer|produced|arranger|arranged|mixed|letra|m[uú]sica|compositor(es)?|autor(es)?)(\s+by)?\s*[:：]"#,
        options: [.caseInsensitive])

    static func isCredit(_ text: String) -> Bool {
        guard let r = creditRegex else { return false }
        return r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

struct LyricLineView: View {
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var lyrics: LyricsService

    // Las líneas ocupan SIEMPRE su altura, haya letra o no: así nada se mueve.
    // La de la traducción solo se reserva si la canción está en otro idioma.
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ZStack(alignment: .leading) {
                Color.clear
                if !lyrics.lines.isEmpty {
                    TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                        let current = lyrics.line(at: media.position(at: ctx.date))
                        let text = current ?? "♪"
                        Text(text)
                            .font(.system(size: 11.5, weight: .medium).italic())
                            .foregroundStyle(current == nil ? Color.primary.opacity(0.35) : media.accent)
                            .lineLimit(1)
                            .id(text)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: text)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 15, maxHeight: 15, alignment: .leading)

            if lyrics.translationExpected {
                ZStack(alignment: .leading) {
                    Color.clear
                    TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                        let text = lyrics.translation(at: media.position(at: ctx.date)) ?? ""
                        Text(text)
                            .font(.system(size: 10.5).italic())
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .lineLimit(1)
                            .id(text)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: text)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 13, maxHeight: 13, alignment: .leading)
            }
        }
        .background { LyricsTranslationHost() }
    }
}

/// Lanza la traducción cuando hace falta descargar el idioma (macOS muestra su aviso).
struct LyricsTranslationHost: View {
    @EnvironmentObject var lyrics: LyricsService

    var body: some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            Color.clear.translationTask(lyrics.translationConfig as? TranslationSession.Configuration) { session in
                await lyrics.translate(with: session)
            }
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }
}

// MARK: - 5. Gestos con el trackpad (deslizar para cambiar de canción)

final class SwipeCatcherView: NSView {
    var onSwipe: ((Int) -> Void)?
    private var accumulated: CGFloat = 0
    private var fired = false

    // Solo intercepta el desplazamiento; los clics pasan a los botones de encima.
    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
    }

    override func scrollWheel(with e: NSEvent) {
        if e.phase == .began { accumulated = 0; fired = false }
        guard e.hasPreciseScrollingDeltas, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else {
            super.scrollWheel(with: e); return
        }
        accumulated += e.scrollingDeltaX
        if !fired, abs(accumulated) > 70 {
            fired = true
            onSwipe?(accumulated < 0 ? 1 : -1)
        }
        if e.phase == .ended || e.phase == .cancelled { accumulated = 0; fired = false }
    }
}

struct SwipeCatcher: NSViewRepresentable {
    let onSwipe: (Int) -> Void
    func makeNSView(context: Context) -> SwipeCatcherView {
        let v = SwipeCatcherView()
        v.onSwipe = onSwipe
        return v
    }
    func updateNSView(_ v: SwipeCatcherView, context: Context) { v.onSwipe = onSwipe }
}

// MARK: - Vistas: indicadores y temporizador en la isla cerrada

/// Puntos de privacidad (micro naranja, cámara verde) y taza si el Mac se mantiene despierto.
struct StatusIndicators: View {
    @EnvironmentObject var privacy: PrivacyMonitor
    @EnvironmentObject var caffeine: CaffeineController

    var body: some View {
        HStack(spacing: 3) {
            if caffeine.active {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.8))
            }
            if privacy.cameraInUse {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                    .help(L("privacy.camera"))
            }
            if privacy.micInUse {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                    .help(L("privacy.mic"))
            }
        }
    }
}

struct TimerBannerView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var timer: TimerController
    let height: CGFloat

    var body: some View {
        if let end = timer.endDate {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let remaining = max(0, end.timeIntervalSince(ctx.date))
                let fraction = timer.duration > 0 ? remaining / timer.duration : 0
                HStack(spacing: 6) {
                    TomatoIcon(size: 13, active: true)
                    Text(format(remaining))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.primary)
                    if state.hasNotch { Spacer(minLength: state.notchSize.width + 8) } else { Spacer(minLength: 6) }
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
                        Circle().trim(from: 0, to: fraction)
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 14, height: 14)
                }
            }
            .frame(height: height)
        }
    }

    private func format(_ s: TimeInterval) -> String {
        let t = Int(s.rounded(.up))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Icono de tomate (Pomodoro), dibujado a mano
// Como la taza: en reposo, trazo del color del texto; activo, relleno en rojo.

struct TomatoIcon: View {
    var size: CGFloat = 14
    var active = false

    private var red: Color { Color(red: 0.95, green: 0.32, blue: 0.27) }

    var body: some View {
        let tint: Color = active ? red : .primary
        let line = max(1.2, size * 0.11)
        ZStack(alignment: .top) {
            Group {
                if active {
                    Ellipse().fill(tint)
                } else {
                    Ellipse().stroke(tint, lineWidth: line)
                }
            }
            .frame(width: size - line, height: size * 0.82)
            .offset(y: size * 0.2)
            // Hojas y rabito
            HStack(spacing: -size * 0.1) {
                Capsule().fill(tint).frame(width: size * 0.4, height: size * 0.14).rotationEffect(.degrees(-28))
                Capsule().fill(tint).frame(width: size * 0.4, height: size * 0.14).rotationEffect(.degrees(28))
            }
            .offset(y: size * 0.1)
            Capsule().fill(tint)
                .frame(width: size * 0.11, height: size * 0.24)
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size * 1.05)
        .accessibilityLabel(L("timer.menu"))
    }
}
