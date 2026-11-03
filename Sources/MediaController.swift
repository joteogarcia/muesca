import AppKit
import SwiftUI
import CoreImage

/// Lee lo que suena en Spotify o en Música (Apple Music) mediante AppleScript y permite controlarlo.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Muesca.log")
    static func write(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

final class MediaController: ObservableObject {

    enum Source: String, CaseIterable, Hashable {
        case spotify, music

        var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
        var scriptName: String { self == .spotify ? "Spotify" : "Music" }
        var displayName: String { self == .spotify ? "Spotify" : L("media.music") }

        var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
        var isInstalled: Bool { appURL != nil }
        var icon: NSImage? { appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } }

        func launch() {
            guard let url = appURL else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var artworkURL: String
        var duration: Double
        var album: String = ""
    }

    @Published private(set) var source: Source?
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .primary
    /// Colores dominantes de la carátula (tema «Según la carátula»); nil si no hay música.
    @Published private(set) var palette: ArtworkPalette?
    @Published private(set) var sourceIcon: NSImage?

    private var position: Double = 0
    private var positionDate = Date()

    private let queue = DispatchQueue(label: "muesca.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:] // solo se toca desde `queue`
    private var timer: Timer?
    private var artworkKey = ""

    /// La isla muestra la "actividad en vivo" solo si algo está sonando.
    var isActive: Bool { track != nil && isPlaying }

    func position(at date: Date) -> Double {
        let elapsed = isPlaying ? date.timeIntervalSince(positionDate) : 0
        return min(position + elapsed, track?.duration ?? .greatestFiniteMagnitude)
    }

    // MARK: Sondeo

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func poll() {
        // Solo consultamos apps que ya están abiertas (si no, AppleScript las abriría).
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = Source.allCases.filter { running.contains($0.bundleID) }

        queue.async { [weak self] in
            guard let self else { return }
            var playing: (Source, String)?
            var paused: (Source, String)?
            for s in candidates {
                guard let out = self.run(Self.queryScript(for: s)) else { continue }
                if out.hasPrefix("playing") { playing = (s, out); break }
                if paused == nil, out.hasPrefix("paused") { paused = (s, out) }
            }
            let result = playing ?? paused
            DispatchQueue.main.async { self.apply(result) }
        }
    }

    private func apply(_ result: (Source, String)?) {
        guard let (src, out) = result else {
            if track != nil { track = nil; isPlaying = false; source = nil; artwork = nil; artworkKey = ""; palette = nil }
            return
        }
        let p = out.components(separatedBy: "|~|")
        guard p.count >= 6 else { return }

        func num(_ s: String) -> Double {
            Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
        }

        let newTrack = Track(title: p[1], artist: p[2], artworkURL: p[3], duration: num(p[4]),
                             album: p.count > 6 ? p[6] : "")
        if source != src {
            source = src
            sourceIcon = src.icon
        }
        if track != newTrack { track = newTrack }
        let playing = p[0] == "playing"
        if playing != isPlaying { isPlaying = playing }
        position = num(p[5])
        positionDate = Date()

        let key = "\(src.rawValue)|\(newTrack.title)|\(newTrack.artist)"
        if key != artworkKey {
            artworkKey = key
            loadArtwork(for: src, track: newTrack, key: key)
        }
    }

    // MARK: Carátula

    private func loadArtwork(for src: Source, track: Track, key: String) {
        switch src {
        case .spotify:
            guard let url = URL(string: track.artworkURL), !track.artworkURL.isEmpty else { setArtwork(nil, key: key); return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                let img = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async { self?.setArtwork(img, key: key) }
            }.resume()
        case .music:
            queue.async { [weak self] in
                guard let self else { return }
                let path = self.run(Self.musicArtworkScript) ?? ""
                let img = path.isEmpty ? nil : NSImage(contentsOfFile: path)
                DispatchQueue.main.async { self.setArtwork(img, key: key) }
            }
        }
    }

    private func setArtwork(_ image: NSImage?, key: String) {
        guard key == artworkKey else { return } // ya cambió la canción
        artwork = image
        let p = image.flatMap(ArtworkPalette.extract)
        palette = p
        accent = p.map { Color(nsColor: $0.accent) } ?? .primary
    }

    // MARK: Controles

    /// Abre la app que está sonando (Spotify o Música).
    func openSourceApp() { source?.launch() }

    /// Salta a un punto de la canción (segundos).
    func seek(to seconds: Double) {
        guard let src = source, let d = track?.duration, d > 0 else { return }
        let t = min(max(seconds, 0), d - 1)
        position = t
        positionDate = Date()
        objectWillChange.send()
        let script = "tell application \"\(src.scriptName)\" to set player position to \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), t))"
        queue.async { [weak self] in _ = self?.run(script) }
    }

    func playPause() { isPlaying.toggle(); positionDate = Date(); send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    private func send(_ command: String) {
        guard let src = source else { return }
        let script = "tell application \"\(src.scriptName)\" to \(command)"
        queue.async { [weak self] in
            _ = self?.run(script)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.poll() }
        }
    }

    // MARK: AppleScript

    /// Ejecutar SIEMPRE desde `queue`.
    private func run(_ source: String) -> String? {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let s = NSAppleScript(source: source) else { return nil }
            compiled[source] = s
            script = s
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            Log.write("AppleScript error: \(error)")
            return nil
        }
        return result.stringValue
    }

    private static func queryScript(for s: Source) -> String {
        switch s {
        case .spotify:
            return """
            tell application "Spotify"
                if player state is stopped then return "stopped"
                set pState to player state as string
                set tr to current track
                return pState & "|~|" & (name of tr) & "|~|" & (artist of tr) & "|~|" & (artwork url of tr) & "|~|" & ((duration of tr) / 1000) & "|~|" & player position & "|~|" & (album of tr)
            end tell
            """
        case .music:
            return """
            tell application "Music"
                if player state is stopped then return "stopped"
                set pState to player state as string
                set tr to current track
                return pState & "|~|" & (name of tr) & "|~|" & (artist of tr) & "|~|" & "" & "|~|" & (duration of tr) & "|~|" & player position & "|~|" & (album of tr)
            end tell
            """
        }
    }

    private static let musicArtworkScript = """
    try
        tell application "Music"
            set artData to raw data of artwork 1 of current track
        end tell
        set p to (POSIX path of (path to temporary items)) & "muesca_artwork"
        set f to open for access (POSIX file p) with write permission
        set eof f to 0
        write artData to f
        close access f
        return p
    on error
        return ""
    end try
    """
}
