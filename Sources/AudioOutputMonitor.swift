import AppKit
import CoreAudio
import IOBluetooth
import AudioToolbox
import SwiftUI

/// Salida de audio actual del sistema (altavoces, AirPods, DAC USB…) y cambio de salida.
final class AudioOutputMonitor: ObservableObject {

    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let transport: UInt32

        var symbol: String {
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn:
                return "laptopcomputer"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return AudioOutputMonitor.bluetoothSymbol(for: name)
            case kAudioDeviceTransportTypeUSB:
                return "hifispeaker.fill"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
                return "tv"
            case kAudioDeviceTransportTypeAirPlay:
                return "airplayaudio"
            default:
                return "speaker.wave.2.fill"
            }
        }
    }

    static func bluetoothSymbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("homepod") { return "homepod.fill" }
        return "headphones"
    }

    @Published private(set) var current: Device?
    @Published private(set) var devices: [Device] = []

    // Volumen de la salida actual
    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var volumeSettable = false
    /// Indicador compartido (volumen/brillo) de la isla.
    weak var hud: HUDController?

    var volumeSymbol: String {
        if muted || volume < 0.01 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var volumeTimer: Timer?
    private var lastSetByUs = Date.distantPast
    private var initialized = false

    private let system = AudioObjectID(kAudioObjectSystemObject)

    func start() {
        refresh()
        readVolume()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.readVolume() }
        RunLoop.main.add(t, forMode: .common)
        volumeTimer = t
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var addr = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { [weak self] _, _ in
                self?.refresh()
            }
        }
    }

    func refresh() {
        devices = deviceIDs().filter(hasOutput).compactMap(device)
        let def = defaultOutput()
        let newCurrent = devices.first { $0.id == def } ?? device(def)
        if newCurrent?.id != current?.id { initialized = false } // no mostrar HUD al cambiar de salida
        current = newCurrent
    }

    func select(_ id: AudioDeviceID) {
        var dev = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var addr = Self.address(selector)
            AudioObjectSetPropertyData(system, &addr, 0, nil, size, &dev)
        }
        refresh()
    }

    // MARK: Bluetooth

    struct PairedDevice {
        let name: String
        let address: String
    }

    /// Dispositivos de audio Bluetooth emparejados pero sin conectar (AirPods, auriculares, altavoces…).
    func disconnectedBluetoothAudio() -> [PairedDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let connectedNames = Set(devices.map(\.name))
        return paired
            .filter { $0.deviceClassMajor == 0x04 && !$0.isConnected() } // 0x04 = audio/vídeo
            .compactMap { d in
                guard let name = d.name, let addr = d.addressString, !connectedNames.contains(name) else { return nil }
                return PairedDevice(name: name, address: addr)
            }
    }

    /// Conecta un dispositivo Bluetooth y, cuando aparece como salida, lo selecciona.
    func connectBluetooth(_ paired: PairedDevice) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let device = IOBluetoothDevice(addressString: paired.address) else { return }
            let result = device.openConnection()
            if result != kIOReturnSuccess { Log.write("Bluetooth connect \(paired.name): \(result)") }
        }
        waitAndSelect(name: paired.name, attempts: 24)
    }

    private func waitAndSelect(name: String, attempts: Int) {
        refresh()
        if let d = devices.first(where: { $0.name == name }) {
            select(d.id)
            return
        }
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitAndSelect(name: name, attempts: attempts - 1)
        }
    }

    // MARK: Volumen

    private func volumeAddress() -> AudioObjectPropertyAddress {
        Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    }

    func readVolume() {
        guard let id = current?.id else { if volumeSettable { volumeSettable = false }; return }
        var vAddr = volumeAddress()
        guard AudioObjectHasProperty(id, &vAddr) else { if volumeSettable { volumeSettable = false }; return }

        var settable: DarwinBoolean = false
        AudioObjectIsPropertySettable(id, &vAddr, &settable)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(id, &vAddr, 0, nil, &size, &v)

        var mAddr = muteAddress()
        var m: UInt32 = 0
        if AudioObjectHasProperty(id, &mAddr) {
            var mSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &mAddr, 0, nil, &mSize, &m)
        }

        let changed = abs(v - volume) > 0.004 || (m != 0) != muted
        if settable.boolValue != volumeSettable { volumeSettable = settable.boolValue }
        guard changed else { initialized = true; return }
        volume = v
        muted = m != 0
        // Cambio desde fuera (teclas de volumen, Centro de control…) → indicador en la isla.
        if initialized, Date().timeIntervalSince(lastSetByUs) > 0.6 { showHUD() }
        initialized = true
    }

    func setVolume(_ value: Float) {
        guard let id = current?.id else { return }
        lastSetByUs = Date()
        var v = Float32(min(max(value, 0), 1))
        var addr = volumeAddress()
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if muted && v > 0 { setMute(false) }
        volume = v
    }

    func toggleMute() { setMute(!muted) }

    private func setMute(_ on: Bool) {
        guard let id = current?.id else { return }
        lastSetByUs = Date()
        var addr = muteAddress()
        guard AudioObjectHasProperty(id, &addr) else { return }
        var m: UInt32 = on ? 1 : 0
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        muted = on
    }

    func showHUD() {
        hud?.show(.volume, level: volume, muted: muted)
    }

    // MARK: CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func deviceIDs() -> [AudioDeviceID] {
        var addr = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func defaultOutput() -> AudioDeviceID {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id)
        return id
    }

    private func hasOutput(_ id: AudioDeviceID) -> Bool {
        var addr = Self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private func device(_ id: AudioDeviceID) -> Device? {
        guard id != 0 else { return nil }
        var nameAddr = Self.address(kAudioObjectPropertyName)
        var cfName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &cfName) {
            AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, $0)
        }
        guard status == noErr else { return nil }

        var tAddr = Self.address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var tSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &tAddr, 0, nil, &tSize, &transport)

        return Device(id: id, name: cfName as String, transport: transport)
    }
}
