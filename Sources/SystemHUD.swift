import AppKit
import SwiftUI
import CoreGraphics
import ApplicationServices

// MARK: - Indicador (HUD) en la isla: volumen y brillo

final class HUDController: ObservableObject {
    enum Kind { case volume, brightness, battery }

    @Published private(set) var kind: Kind = .volume
    @Published private(set) var level: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var until: Date?

    private var token = 0

    var active: Bool { (until ?? .distantPast) > Date() }

    var symbol: String {
        switch kind {
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .battery:
            return "bolt.fill"
        case .volume:
            if muted || level < 0.01 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }

    func show(_ kind: Kind, level: Float, muted: Bool = false) {
        token += 1
        let t = token
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.kind = kind
            self.level = level
            self.muted = muted
            self.until = Date().addingTimeInterval(1.6)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak self] in
            guard let self, self.token == t else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { self.until = nil }
        }
    }
}

// MARK: - Brillo de la pantalla integrada (DisplayServices)

final class BrightnessMonitor {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?
    private weak var hud: HUDController?
    private var last: Float = -1
    private var lastSetByUs = Date.distantPast
    private var timer: Timer?
    let external = ExternalBrightness()

    init(hud: HUDController) {
        self.hud = hud
        let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getFn = h.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
        setFn = h.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    }

    /// Pantalla integrada del MacBook (si la tapa está abierta).
    var builtinDisplay: CGDirectDisplayID? {
        var n: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetActiveDisplayList(n, &ids, &n)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    var brightness: Float? {
        guard let id = builtinDisplay, let getFn else { return nil }
        var b: Float = 0
        return getFn(id, &b) == 0 ? b : nil
    }

    func start() {
        last = brightness ?? -1
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        guard let b = brightness else { return }
        defer { last = b }
        guard last >= 0, abs(b - last) > 0.004 else { return }
        // Cambio desde fuera (Centro de control, brillo automático…)
        if Date().timeIntervalSince(lastSetByUs) > 0.6 { hud?.show(.brightness, level: b) }
    }

    /// ¿El puntero está sobre la pantalla del MacBook?
    private var pointerOnBuiltin: Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return true }
        return screen.isBuiltin
    }

    /// Hay alguna pantalla cuyo brillo podemos controlar.
    var canControl: Bool { builtinDisplay != nil || external.available }

    /// Sube/baja el brillo de la pantalla donde está el puntero.
    @discardableResult
    func step(_ delta: Float) -> Bool {
        if !pointerOnBuiltin || builtinDisplay == nil {
            if let v = external.step(delta) {
                hud?.show(.brightness, level: v)
                return true
            }
            if builtinDisplay == nil { return false }
        }
        guard let id = builtinDisplay, let setFn, let current = brightness else { return false }
        let new = min(max(current + delta, 0), 1)
        lastSetByUs = Date()
        _ = setFn(id, new)
        last = new
        hud?.show(.brightness, level: new)
        return true
    }
}

// MARK: - Teclas de volumen y brillo (sustituye el HUD de macOS)

final class MediaKeyTap {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "replaceSystemHUD") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "replaceSystemHUD") }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private unowned let audio: AudioOutputMonitor
    private unowned let brightness: BrightnessMonitor

    // Códigos NX_KEYTYPE_* de las teclas especiales
    private let soundUp = 0, soundDown = 1, brightUp = 2, brightDown = 3, mute = 7

    init(audio: AudioOutputMonitor, brightness: BrightnessMonitor) {
        self.audio = audio
        self.brightness = brightness
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Pide el permiso de Accesibilidad (muestra el aviso del sistema).
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func update() {
        if Self.enabled {
            if !Self.isTrusted { Self.requestTrust() }
            install()
        } else {
            uninstall()
        }
    }

    private func install() {
        guard tap == nil else { return }
        guard Self.isTrusted else {
            // Reintentar hasta que se conceda el permiso
            if retryTimer == nil {
                retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    guard Self.isTrusted else { return }
                    self?.retryTimer?.invalidate(); self?.retryTimer = nil
                    if Self.enabled { self?.install() }
                }
            }
            return
        }
        // NX_SYSDEFINED (volumen, y brillo en algunos teclados) + keyDown/keyUp
        // (en Mac con chip Apple las teclas de brillo llegan como teclas 144/145)
        let mask = CGEventMask(1 << 14) | CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<MediaKeyTap>.fromOpaque(info).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: me
        ) else {
            Log.write("No se pudo crear el event tap")
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func uninstall() {
        retryTimer?.invalidate(); retryTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == 144 || keyCode == 145, brightness.canControl else {
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown {
                let flags = event.flags
                let fine = flags.contains(.maskAlternate) && flags.contains(.maskShift)
                let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0
                brightness.step(keyCode == 144 ? step : -step)
            }
            return nil
        }
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let code = (ns.data1 & 0xFFFF0000) >> 16
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
        let fine = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0

        switch code {
        case soundUp, soundDown, mute:
            guard audio.volumeSettable else { return Unmanaged.passUnretained(event) }
            if isDown {
                if code == mute { audio.toggleMute() }
                else { audio.setVolume(audio.volume + (code == soundUp ? step : -step)) }
                audio.showHUD()
            }
            return nil // nos lo quedamos: macOS no muestra su indicador
        case brightUp, brightDown:
            guard brightness.canControl else { return Unmanaged.passUnretained(event) }
            if isDown { brightness.step(code == brightUp ? step : -step) }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

// MARK: - Vista del indicador en la isla cerrada

struct SystemHUDView: View {
    @EnvironmentObject var state: NotchState
    @EnvironmentObject var hud: HUDController
    let height: CGFloat

    var body: some View {
        let level = hud.muted ? 0 : hud.level
        HStack(spacing: 8) {
            Image(systemName: hud.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hud.kind == .brightness ? Color.yellow : (hud.kind == .battery ? Color.green : Color.primary))
                .symbolEffectBounce(trigger: hud.until)
                .frame(width: 20)
            if state.hasNotch {
                Text("\(Int((level * 100).rounded()))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.primary.opacity(0.8))
                Spacer(minLength: state.notchSize.width + 8)
                VolumeBar(value: level, interactive: false)
                    .frame(width: 80)
            } else {
                VolumeBar(value: level, interactive: false)
                Text("\(Int((level * 100).rounded()))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .frame(width: 26, alignment: .trailing)
            }
        }
        .frame(height: height)
    }
}

extension View {
    /// Pequeño rebote del símbolo al aparecer (macOS 14+).
    @ViewBuilder
    func symbolEffectBounce<V: Equatable>(trigger: V) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
    }
}
