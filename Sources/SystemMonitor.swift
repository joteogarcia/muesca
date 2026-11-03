import AppKit
import SwiftUI
import IOKit
import Darwin

/// Rendimiento del sistema: CPU, memoria (presión), GPU, disco, red, batería,
/// procesos que más consumen y avisos.
final class SystemMonitor: ObservableObject {

    // MARK: Datos publicados

    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var pressure: Int32 = 1         // 1 normal · 2 aviso · 4 crítica
    @Published private(set) var gpu: Double?
    @Published private(set) var diskUsed: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 1
    @Published private(set) var downPerSec: Double = 0
    @Published private(set) var upPerSec: Double = 0
    @Published private(set) var netHistory: [Double] = []   // bajada + subida
    @Published private(set) var thermal: ProcessInfo.ThermalState = .nominal
    @Published private(set) var battery: BatteryHealth?
    @Published private(set) var topProcesses: [ProcessUsage] = []
    /// Los avisos van por un canal aparte para no redibujar toda la isla cada 2 s.
    let alerts = AlertCenter()

    struct BatteryHealth: Equatable {
        let healthPercent: Int
        let cycles: Int
        let onAC: Bool
        let watts: Double          // consumo del sistema (o + carga / − descarga)
        let charging: Bool
    }

    struct ProcessUsage: Identifiable, Equatable {
        let id: pid_t
        let name: String
        let cpu: Double            // %
        let memory: UInt64         // bytes
        let isApp: Bool
        var icon: NSImage? {
            NSRunningApplication(processIdentifier: id)?.icon
        }
    }

    struct SysAlert: Equatable {
        let symbol: String
        let short: String
        let detail: String
        let color: Color
    }

    var memory: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    var disk: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }
    var diskFree: Int64 { max(0, diskTotal - diskUsed) }

    // MARK: Estado interno

    private var timer: Timer?
    private var lastTicks: (used: UInt64, total: UInt64)?
    private var lastNet: (down: UInt64, up: UInt64, date: Date)?
    private var tick = 0
    private var detailActive = false
    private var cpuHighCount = 0
    private var lastAlert: [String: Date] = [:]
    private let historyLength = 30           // 30 × 2 s = 1 minuto
    private let psQueue = DispatchQueue(label: "muesca.ps", qos: .utility)

    func start() {
        updateDisk()
        update()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// El panel está a la vista: refrescar la lista de procesos.
    func setDetailActive(_ on: Bool) {
        detailActive = on
        if on { fetchTopProcesses() }
    }

    private func update() {
        updateCPU()
        updateMemory()
        updateNetwork()
        gpu = Self.gpuUtilization()
        thermal = ProcessInfo.processInfo.thermalState
        if tick % 5 == 0 { battery = Self.readBattery() }    // cada 10 s
        if tick % 15 == 0 { updateDisk() }                   // cada 30 s
        if detailActive { fetchTopProcesses() }
        checkAlerts()
        tick += 1
    }

    // MARK: CPU

    private func updateCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let used = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.1) + UInt64(info.cpu_ticks.3)
        let total = used + UInt64(info.cpu_ticks.2)
        if let last = lastTicks, total > last.total {
            cpu = Double(used - last.used) / Double(total - last.total)
            cpuHistory = Array((cpuHistory + [cpu]).suffix(historyLength))
        }
        lastTicks = (used, total)
    }

    // MARK: Memoria

    private func updateMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count)
            let app = internalPages - min(UInt64(stats.purgeable_count), internalPages)
            memoryUsed = min((app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page, memoryTotal)
        }
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 { pressure = level }
    }

    // MARK: GPU

    static func gpuUtilization() -> Double? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var best: Double?
        var service = IOIteratorNext(it)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any],
               let perf = d["PerformanceStatistics"] as? [String: Any],
               let u = perf["Device Utilization %"] as? NSNumber {
                best = max(best ?? 0, min(u.doubleValue / 100, 1))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return best
    }

    // MARK: Disco

    private func updateDisk() {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                         .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, total > 0 else { return }
        diskTotal = Int64(total)
        diskUsed = max(0, Int64(total) - (v.volumeAvailableCapacityForImportantUsage ?? 0))
    }

    // MARK: Red

    private func updateNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        defer { freeifaddrs(ifaddr) }
        var down: UInt64 = 0, up: UInt64 = 0
        var ptr = ifaddr
        while let p = ptr {
            let a = p.pointee
            if let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = a.ifa_data,
               !String(cString: a.ifa_name).hasPrefix("lo") {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(d.ifi_ibytes)
                up += UInt64(d.ifi_obytes)
            }
            ptr = a.ifa_next
        }
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.date)
            if dt > 0 {
                downPerSec = down >= last.down ? Double(down - last.down) / dt : downPerSec
                upPerSec = up >= last.up ? Double(up - last.up) / dt : upPerSec
                netHistory = Array((netHistory + [downPerSec + upPerSec]).suffix(historyLength))
            }
        }
        lastNet = (down, up, now)
    }

    // MARK: Batería

    static func readBattery() -> BatteryHealth? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }

        // Algunos datos están dentro de «BatteryData»
        let nested = d["BatteryData"] as? [String: Any] ?? [:]
        func int(_ k: String) -> Int64? { ((d[k] ?? nested[k]) as? NSNumber)?.int64Value }
        let design = int("DesignCapacity") ?? 0
        let full = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity") ?? 0
        let health = design > 0 ? Int((Double(full) / Double(design) * 100).rounded()) : 100
        let cycles = Int(int("CycleCount") ?? 0)
        let onAC = (d["ExternalConnected"] as? Bool) ?? false
        let charging = (d["IsCharging"] as? Bool) ?? false
        let volts = Double(int("Voltage") ?? 0) / 1000
        let amps = Double(int("InstantAmperage") ?? int("Amperage") ?? 0) / 1000
        var watts = abs(volts * amps)
        if onAC, let tel = d["PowerTelemetryData"] as? [String: Any],
           let sys = (tel["SystemPowerIn"] as? NSNumber)?.doubleValue, sys > 0 {
            watts = sys / 1000      // consumo real del Mac desde el cargador
        }
        return BatteryHealth(healthPercent: min(health, 100), cycles: cycles, onAC: onAC, watts: watts, charging: charging)
    }

    // MARK: Procesos que más consumen

    private func fetchTopProcesses(completion: ((ProcessUsage?) -> Void)? = nil) {
        psQueue.async { [weak self] in
            let list = Self.runPS()
            DispatchQueue.main.async {
                self?.topProcesses = Array(list.prefix(3))
                completion?(list.first)
            }
        }
    }

    private static func runPS() -> [ProcessUsage] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pid=,pcpu=,rss=,comm=", "-r"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return [] }

        var result: [ProcessUsage] = []
        for line in out.split(separator: "\n").prefix(12) {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = pid_t(parts[0]),
                  let pcpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  let rss = UInt64(parts[2]) else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? String(parts[3])
            result.append(ProcessUsage(id: pid, name: name, cpu: pcpu, memory: rss * 1024,
                                       isApp: app?.activationPolicy == .regular))
            if result.count == 3 { break }
        }
        return result
    }

    func activate(_ p: ProcessUsage) {
        NSRunningApplication(processIdentifier: p.id)?.activate(options: [])
    }

    func forceQuit(_ p: ProcessUsage) {
        NSRunningApplication(processIdentifier: p.id)?.forceTerminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.fetchTopProcesses() }
    }

    // MARK: Avisos en la isla cerrada

    private func checkAlerts() {
        cpuHighCount = cpu > 0.9 ? cpuHighCount + 1 : 0
        if cpuHighCount == 10 {          // ≥ 90 % durante 20 s
            let pct = Int((cpu * 100).rounded())
            fetchTopProcesses { [weak self] top in
                self?.raise("cpu", SysAlert(symbol: "cpu", short: L("alert.cpu", pct),
                                            detail: top?.name ?? "", color: .orange))
            }
        }
        if thermal == .serious || thermal == .critical {
            raise("thermal", SysAlert(symbol: "flame.fill", short: L("alert.thermal"),
                                      detail: L("alert.thermalDetail"), color: .red))
        }
        if diskTotal > 1, diskFree < 10 * 1_000_000_000 {
            let f = ByteCountFormatter(); f.countStyle = .file
            raise("disk", SysAlert(symbol: "internaldrive.fill", short: L("alert.disk"),
                                   detail: L("alert.diskDetail", f.string(fromByteCount: diskFree)), color: .orange))
        }
    }

    private func raise(_ kind: String, _ a: SysAlert) {
        if let last = lastAlert[kind], Date().timeIntervalSince(last) < 15 * 60 { return }
        lastAlert[kind] = Date()
        let center = alerts
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { center.alert = a }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard center.alert == a else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { center.alert = nil }
        }
    }
}

final class AlertCenter: ObservableObject {
    @Published var alert: SystemMonitor.SysAlert?
}
