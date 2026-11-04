import CoreAudio
import Foundation

/// Where the Mac is playing sound right now, to tell whether the microphone will hear the call.
enum OutputRoute {
    struct Device: Equatable {
        var name: String
        /// Sound comes out into the room (built-in or external speakers, a display, AirPlay),
        /// rather than into headphones.
        var isSpeakers: Bool
    }

    static func current() -> Device? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        let name = string(id, kAudioObjectPropertyName) ?? "Output"
        let transport = uint32(id, kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal) ?? 0
        return Device(name: name, isSpeakers: isSpeakers(transport: transport, name: name, dataSource: {
            uint32(id, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
        }))
    }

    static func isSpeakers(transport: UInt32, name: String, dataSource: () -> UInt32?) -> Bool {
        let lower = name.lowercased()
        if ["headphone", "headset", "airpods", "buds", "earphone"].contains(where: lower.contains) { return false }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            // The built-in output is one device whose data source says whether headphones are plugged in.
            return dataSource() != fourCC("hdpn")
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            // Nearly always headphones; a Bluetooth speaker is the rare case the after-Stop check covers.
            return false
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeUnknown:
            return false
        default:
            // USB, HDMI, DisplayPort, Thunderbolt, AirPlay: speakers or a display's speakers.
            return true
        }
    }

    static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address),
              AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
