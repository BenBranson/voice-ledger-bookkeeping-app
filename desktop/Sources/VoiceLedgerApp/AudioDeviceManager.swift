import CoreAudio
import Foundation

/// Owner directive (2026-09-06): "Voice Ledger should have a settings menu
/// for audio input to pick from macbook mic or Maono 200w usb and pick
/// for audio output such as macbooks speakers or my bluetooth Soundcore
/// q45 and Soundcore Space One."
///
/// **Honest scope**: this sets macOS's SYSTEM-WIDE default input/output
/// device (`kAudioHardwarePropertyDefault{Input,Output}Device`), not a
/// Voice-Ledger-only route. A true per-app-only route would mean replacing
/// `AVAudioPlayer` playback with an `AVAudioEngine` graph and overriding
/// each audio unit's `kAudioOutputUnitProperty_CurrentDevice` — real,
/// buildable work, but a materially bigger change than this file. Setting
/// the system default is what "pick a mic/speakers from within Voice
/// Ledger instead of System Settings" actually needs, and `AudioSettingsView`
/// says so explicitly rather than implying a narrower effect than this
/// really has (CLAUDE.md rule 6: no feature claims a capability it doesn't
/// have proof of). `VoiceEngine`'s existing `.AVAudioEngineConfigurationChange`
/// observer already reacts to a default-device change made this way — see
/// that file's own doc comment — so switching devices mid-conversation
/// doesn't require new handling here.
enum AudioDeviceManager {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func inputDevices() -> [Device] {
        devices(withChannelsFor: kAudioDevicePropertyScopeInput)
    }

    static func outputDevices() -> [Device] {
        devices(withChannelsFor: kAudioDevicePropertyScopeOutput)
    }

    static func currentDefaultInput() -> Device? {
        currentDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    static func currentDefaultOutput() -> Device? {
        currentDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    /// Throws a plain, readable error rather than silently no-op'ing — a
    /// settings screen that "picks" a device but doesn't actually apply it
    /// is exactly the kind of unverified claim CLAUDE.md rule 6 rules out.
    static func setDefaultInput(_ device: Device) throws {
        try setDefaultDevice(device, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    static func setDefaultOutput(_ device: Device) throws {
        try setDefaultDevice(device, selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    // MARK: - CoreAudio plumbing

    struct AudioDeviceError: LocalizedError {
        let osStatus: OSStatus
        var errorDescription: String? { "CoreAudio error \(osStatus)" }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceIDs) == noErr else { return [] }
        return deviceIDs
    }

    /// A device has usable channels in a given scope (input/output) when
    /// its stream configuration for that scope has at least one channel —
    /// the standard CoreAudio way to tell a mic-only device from a
    /// speakers-only one (most USB/Bluetooth audio devices expose both
    /// scopes with one side empty).
    private static func hasChannels(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return false }
        let bufferListPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListPointer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer) == noErr else { return false }
        let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    /// `Unmanaged<CFString>`, not a plain `CFString?` `inout`, for the two
    /// string-property lookups below — CoreAudio hands back a +1 CF object
    /// reference through that pointer, and letting Swift's ARC treat that
    /// memory slot as an ordinary object reference (the plain-optional
    /// form) risks a double-release. `takeRetainedValue()` claims that +1
    /// reference correctly.
    private static func cfStringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var unmanagedResult: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &unmanagedResult) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr, let unmanagedResult else { return nil }
        return unmanagedResult.takeRetainedValue() as String
    }

    private static func name(of deviceID: AudioDeviceID) -> String? {
        cfStringProperty(deviceID, selector: kAudioObjectPropertyName)
    }

    private static func uid(of deviceID: AudioDeviceID) -> String? {
        cfStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func devices(withChannelsFor scope: AudioObjectPropertyScope) -> [Device] {
        allDeviceIDs().compactMap { deviceID in
            guard hasChannels(deviceID, scope: scope), let name = name(of: deviceID), let uid = uid(of: deviceID) else { return nil }
            return Device(id: deviceID, uid: uid, name: name)
        }
    }

    private static func currentDefaultDevice(selector: AudioObjectPropertySelector) -> Device? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &deviceID) == noErr,
              let name = name(of: deviceID), let uid = uid(of: deviceID) else { return nil }
        return Device(id: deviceID, uid: uid, name: name)
    }

    private static func setDefaultDevice(_ device: Device, selector: AudioObjectPropertySelector) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = device.id
        let status = AudioObjectSetPropertyData(systemObject, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID)
        guard status == noErr else { throw AudioDeviceError(osStatus: status) }
    }
}
