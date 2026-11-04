import Foundation
import SwiftUI

// MARK: - Denon Remote: lo que suena en el amplificador (radio o tocadiscos)
//
// Muesca solo escucha los avisos que envía la app Denon Remote. Si no está
// instalada o está cerrada, no llega ningún aviso y Muesca funciona como siempre.

final class DenonLink: ObservableObject {
    struct NowPlaying: Equatable {
        enum Kind: String { case radio, phono }
        let kind: Kind
        let title: String       // emisora (vacío en el tocadiscos)
        let subtitle: String    // programa en emisión, si lo hay
        let playing: Bool
    }

    static let nowPlayingName = Notification.Name("com.jorgeoteo.denonremote.nowplaying")
    static let commandName = Notification.Name("com.jorgeoteo.denonremote.command")
    static let bundleID = "com.jorgeoteo.denonremote"

    @Published private(set) var nowPlaying: NowPlaying?
    private var lastSeen = Date.distantPast
    private var expiry: Timer?

    var isActive: Bool { nowPlaying?.playing == true }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.nowPlayingName, object: nil, queue: .main
        ) { [weak self] note in
            self?.handle(note.userInfo)
        }
        // Denon Remote repite el aviso cada pocos segundos; si deja de llegar
        // (app cerrada de golpe), se quita a los 30 s.
        expiry = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.nowPlaying != nil,
                  Date().timeIntervalSince(self.lastSeen) > 30 else { return }
            withAnimation(.easeInOut(duration: 0.3)) { self.nowPlaying = nil }
        }
        // Por si Denon Remote ya estaba sonando cuando arranca Muesca
        send("refresh")
    }

    private func handle(_ info: [AnyHashable: Any]?) {
        lastSeen = Date()
        guard let info, let k = info["kind"] as? String, let kind = NowPlaying.Kind(rawValue: k) else {
            if nowPlaying != nil { withAnimation(.easeInOut(duration: 0.3)) { nowPlaying = nil } }
            return
        }
        let np = NowPlaying(kind: kind,
                            title: info["title"] as? String ?? "",
                            subtitle: info["subtitle"] as? String ?? "",
                            playing: info["playing"] as? Bool ?? true)
        if np != nowPlaying { withAnimation(.easeInOut(duration: 0.3)) { nowPlaying = np } }
    }

    /// Órdenes para Denon Remote: volumeUp, volumeDown, stop, power, refresh
    func send(_ action: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Self.commandName, object: nil, userInfo: ["action": action], deliverImmediately: true)
    }

    func openApp() {
        Opener.app(Self.bundleID)
    }

    /// Texto principal: la emisora o «Tocadiscos»
    var title: String {
        guard let np = nowPlaying else { return "" }
        if np.kind == .phono { return L("denon.phono") }
        return np.title.isEmpty ? L("denon.radio") : np.title
    }

    /// Texto secundario: el programa, o «En directo» / «Vinilo»
    var subtitle: String {
        guard let np = nowPlaying else { return "" }
        if np.kind == .phono { return L("denon.vinyl") }
        return np.subtitle.isEmpty ? L("denon.live") : np.subtitle
    }
}

// MARK: - Vistas

/// Icono cuadrado (radio o disco), en lugar de la carátula
struct DenonBadge: View {
    let kind: DenonLink.NowPlaying.Kind
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.20), Color(white: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: kind == .radio ? "dot.radiowaves.left.and.right" : "opticaldisc")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.green.opacity(0.9))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Isla cerrada con notch: icono a la izquierda, ecualizador a la derecha
struct DenonActivityView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var denon: DenonLink
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            DenonBadge(kind: denon.nowPlaying?.kind ?? .radio, size: 22, corner: 6)
                .opensOnClick(L("denon.open")) { denon.openApp() }
            Spacer(minLength: state.notchSize.width)
            EqualizerBars(playing: denon.isActive, color: .green)
                .frame(width: 22)
        }
        .frame(height: height)
    }
}

/// Píldora en pantallas sin notch
struct DenonPillContent: View {
    @EnvironmentObject var denon: DenonLink

    var body: some View {
        DenonBadge(kind: denon.nowPlaying?.kind ?? .radio, size: 18, corner: 5)
            .opensOnClick(L("denon.open")) { denon.openApp() }
        MarqueeText(text: denon.title, size: 11, color: Color.primary.opacity(0.85))
        Spacer(minLength: 4)
        EqualizerBars(playing: denon.isActive, color: .green)
            .frame(width: 20)
    }
}

/// Tarjeta en la isla abierta (pestaña de música)
struct DenonCard: View {
    @EnvironmentObject var denon: DenonLink

    var body: some View {
        if let np = denon.nowPlaying {
            HStack(alignment: .center, spacing: 14) {
                DenonBadge(kind: np.kind, size: 104, corner: 18)
                    .overlay(alignment: .bottomTrailing) {
                        Text("DENON")
                            .font(.system(size: 8.5, weight: .heavy))
                            .tracking(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .offset(x: 6, y: 6)
                    }
                    .shadow(color: Color.green.opacity(0.3), radius: 10)
                    .opensOnClick(L("denon.open")) { denon.openApp() }

                VStack(alignment: .leading, spacing: 3) {
                    MarqueeText(text: denon.title, size: 15)
                    Text(denon.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        EqualizerBars(playing: np.playing, color: .green)
                            .frame(width: 22)
                        Text(np.kind == .radio ? L("denon.onRadio") : L("denon.onPhono"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.45))
                    }
                    .padding(.top, 4)
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        Button { denon.send("volumeDown") } label: { Image(systemName: "speaker.minus.fill") }
                            .buttonStyle(IconButtonStyle(size: 32))
                            .help(L("denon.volDown"))
                        if np.kind == .radio {
                            Button { denon.send("stop") } label: {
                                Image(systemName: "stop.fill").font(.system(size: 16, weight: .semibold))
                            }
                            .buttonStyle(IconButtonStyle(size: 40))
                            .help(L("denon.stop"))
                        } else {
                            Button { denon.send("power") } label: {
                                Image(systemName: "power").font(.system(size: 16, weight: .semibold))
                            }
                            .buttonStyle(IconButtonStyle(size: 40))
                            .help(L("denon.power"))
                        }
                        Button { denon.send("volumeUp") } label: { Image(systemName: "speaker.plus.fill") }
                            .buttonStyle(IconButtonStyle(size: 32))
                            .help(L("denon.volUp"))
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}
