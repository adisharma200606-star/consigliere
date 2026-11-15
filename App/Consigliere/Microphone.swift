import AVFoundation
import CoreAudio

/// Chooses which microphone Consigliere listens with, and hands out a fresh audio engine for each listen.
///
/// Why this exists: when Bluetooth headphones (AirPods and the like) are connected, macOS makes *their*
/// microphone the default. Bluetooth cannot carry good stereo sound and a microphone at the same time, so the
/// moment anything opens the headphone microphone, the headphones drop into "headset mode": mono, muffled,
/// like a phone call. Music sounds bad until the microphone is let go.
///
/// So: if the default microphone is a Bluetooth one, listen with the Mac's own built-in microphone instead.
/// The headphones never notice and keep playing in full quality. A USB or other wired microphone is left
/// alone, because someone who plugged one in chose it.
///
/// And each listen gets its own engine, which is thrown away afterwards. An engine that has touched the
/// microphone keeps a hold on it even after `stop()`; only letting go of the engine itself releases it.
enum Microphone {

    /// A new engine with its input pointed at the right microphone. Throw it away (set it to nil) when done.
    static func makeEngine() -> AVAudioEngine {
        let engine = AVAudioEngine()
        guard let chosen = deviceToUse(), let unit = engine.inputNode.audioUnit else { return engine }
        var device = chosen
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr {
            // Not fatal: it just listens with the default microphone, as it did before.
            NSLog("Consigliere: could not switch to the built-in microphone (\(status)); using the default one")
        }
        return engine
    }

    /// The built-in microphone when the default one is Bluetooth; nil means "the default is fine, keep it".
    private static func deviceToUse() -> AudioDeviceID? {
        guard let current = defaultInput(), isBluetooth(current) else { return nil }
        return inputDevices().first { transport($0) == kAudioDeviceTransportTypeBuiltIn }
    }

    // MARK: - Asking Core Audio (the layer under AVFoundation that knows about devices)

    private static func defaultInput() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    /// Every device that has at least one input stream, i.e. every microphone.
    private static func inputDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }

        return devices.filter { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioObjectPropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    private static func transport(_ device: AudioDeviceID) -> UInt32 {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value
    }

    private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        let kind = transport(device)
        return kind == kAudioDeviceTransportTypeBluetooth || kind == kAudioDeviceTransportTypeBluetoothLE
    }
}
