import Foundation
import IOKit.ps

final class BatteryMonitor: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var charging = false
    @Published private(set) var hasBattery = false
    private var didInitialRead = false

    private var timer: Timer?
    /// Se llama al enchufar el cargador.
    var onChargingStarted: (() -> Void)?

    func start() {
        update()
        // Aviso inmediato de cambios de alimentación
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.update() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func update() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc["Current Capacity"] as? Int,
                  let max = desc["Max Capacity"] as? Int, max > 0 else { continue }
            hasBattery = true
            level = current * 100 / max
            let isCharging = desc["Is Charging"] as? Bool ?? false
            let onAC = (desc["Power Source State"] as? String) == "AC Power"
            let nowCharging = isCharging || onAC
            if nowCharging && !charging && hasBattery && didInitialRead { onChargingStarted?() }
            charging = nowCharging
            didInitialRead = true
            return
        }
    }

    var symbol: String {
        if charging { return "battery.100.bolt" }
        switch level {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }
}
