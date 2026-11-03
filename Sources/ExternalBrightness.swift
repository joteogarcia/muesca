import Foundation
import IOKit
import AppKit

/// Brillo de monitores externos por DDC/CI (protocolo estándar de los monitores),
/// usando el servicio de vídeo de los Mac con chip Apple.
final class ExternalBrightness {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private let create: CreateFn?
    private let readI2C: I2CFn?
    private let writeI2C: I2CFn?
    private let queue = DispatchQueue(label: "muesca.ddc", qos: .userInitiated)

    private var service: CFTypeRef?
    private(set) var value: Float?          // 0…1, último valor conocido
    private var maxValue: Int = 100
    private var pendingWrite: Float?
    private var writing = false

    init() {
        let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        create = h.flatMap { dlsym($0, "IOAVServiceCreateWithService") }.map { unsafeBitCast($0, to: CreateFn.self) }
        readI2C = h.flatMap { dlsym($0, "IOAVServiceReadI2C") }.map { unsafeBitCast($0, to: I2CFn.self) }
        writeI2C = h.flatMap { dlsym($0, "IOAVServiceWriteI2C") }.map { unsafeBitCast($0, to: I2CFn.self) }
        queue.async { [weak self] in self?.connect() }
    }

    var available: Bool { service != nil }

    /// Vuelve a buscar el monitor (al conectar/desconectar pantallas).
    func reconnect() {
        queue.async { [weak self] in
            self?.service = nil
            self?.value = nil
            self?.connect()
        }
    }

    private func connect() {
        guard let create else { return }
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        var s = IOIteratorNext(it)
        while s != 0 {
            let loc = IORegistryEntryCreateCFProperty(s, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            if loc == "External", service == nil, let av = create(kCFAllocatorDefault, s)?.takeRetainedValue() {
                service = av
            }
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
        if service != nil { readCurrent() }
    }

    private func readCurrent() {
        guard let service, let readI2C, let writeI2C else { return }
        var req: [UInt8] = [0x82, 0x01, 0x10, 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10]
        for _ in 0..<3 {
            _ = writeI2C(service, 0x37, 0x51, &req, UInt32(req.count))
            usleep(40_000)
            var r = [UInt8](repeating: 0, count: 12)
            if readI2C(service, 0x37, 0x51, &r, 12) == kIOReturnSuccess, r[2] == 0x02, r[4] == 0x10 {
                let mx = Int(r[6]) << 8 | Int(r[7])
                let cur = Int(r[8]) << 8 | Int(r[9])
                if mx > 0 {
                    maxValue = mx
                    value = Float(cur) / Float(mx)
                    return
                }
            }
            usleep(30_000)
        }
        value = value ?? 0.5
    }

    /// Cambia el brillo. Devuelve el nuevo valor (0…1) para el indicador, o nil si no hay monitor.
    func step(_ delta: Float) -> Float? {
        guard available else { return nil }
        let new = min(max((value ?? 0.5) + delta, 0), 1)
        value = new
        queue.async { [weak self] in self?.enqueueWrite(new) }
        return new
    }

    /// Agrupa pulsaciones rápidas: solo se envía el último valor.
    private func enqueueWrite(_ v: Float) {
        pendingWrite = v
        guard !writing else { return }
        writing = true
        while let next = pendingWrite {
            pendingWrite = nil
            write(next)
            usleep(50_000)
        }
        writing = false
    }

    private func write(_ v: Float) {
        guard let service, let writeI2C else { return }
        let n = Int((v * Float(maxValue)).rounded())
        let hi = UInt8((n >> 8) & 0xFF), lo = UInt8(n & 0xFF)
        var pkt: [UInt8] = [0x84, 0x03, 0x10, hi, lo, 0]
        pkt[5] = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ hi ^ lo
        _ = writeI2C(service, 0x37, 0x51, &pkt, UInt32(pkt.count))
    }
}
