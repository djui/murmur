import AppKit
import AudioToolbox
import AVFoundation
import CoreAudio

struct AudioProcess: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let objectID: AudioObjectID
}

/// Captures the sound other apps play, through a Core Audio process tap.
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.djui.Murmur.tap", qos: .userInitiated)
    private(set) var format: AVAudioFormat?

    /// Called on the tap queue with each buffer, valid only for the duration of the call.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Taps every app except Murmur, or only the app with `bundleID`.
    func start(bundleID: String? = nil) throws {
        let description: CATapDescription
        if let bundleID, let process = Self.audioProcesses().first(where: { $0.bundleID == bundleID }) {
            description = CATapDescription(stereoMixdownOfProcesses: [process.objectID])
        } else {
            let own = Self.processObject(pid: ProcessInfo.processInfo.processIdentifier)
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: own.map { [$0] } ?? [])
        }
        description.uuid = UUID()
        description.name = "Murmur"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "create the system audio tap")
        tapID = tap

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd), "read the tap format")
        guard let format = AVAudioFormat(streamDescription: &asbd) else { throw TapError.message("Unsupported tap format") }
        self.format = format

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Murmur Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create the capture device")

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            guard let self, let format = self.format,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            self.onBuffer?(buffer)
        }, "start capturing")
        try check(AudioDeviceStart(aggregateID, procID), "start capturing")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
        procID = nil
    }

    deinit { stop() }

    // MARK: - Helpers

    enum TapError: LocalizedError {
        case status(OSStatus, String), message(String)
        var errorDescription: String? {
            switch self {
            case .status(let s, let what): "Couldn’t \(what) (error \(s)). Check System Settings › Privacy & Security › Screen & System Audio Recording."
            case .message(let m): m
            }
        }
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw TapError.status(status, what) }
    }

    static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            throw TapError.message("No audio output device")
        }
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &uidSize, &uid) == noErr, let uid else {
            throw TapError.message("No audio output device")
        }
        return uid.takeRetainedValue() as String
    }

    static func processObject(pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    /// Apps that currently have an audio connection, for choosing the "Others" source.
    static func audioProcesses() -> [AudioProcess] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr else { return [] }
        var seen = Set<String>()
        var out: [AudioProcess] = []
        for object in objects {
            var bundle: Unmanaged<CFString>?
            var bSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(object, &a, 0, nil, &bSize, &bundle) == noErr,
                  let id = bundle?.takeRetainedValue() as String?, !id.isEmpty,
                  id != Bundle.main.bundleIdentifier, !seen.contains(id) else { continue }
            seen.insert(id)
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName
                ?? id.split(separator: ".").last.map(String.init) ?? id
            out.append(AudioProcess(bundleID: id, name: name, objectID: object))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Mono Float samples from any float PCM buffer.
func monoSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    guard frames > 0, channels > 0, let data = buffer.floatChannelData else { return [] }
    var out = [Float](repeating: 0, count: frames)
    if buffer.format.isInterleaved {
        let p = data[0]
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels { sum += p[f * channels + c] }
            out[f] = sum / Float(channels)
        }
    } else {
        for c in 0..<channels {
            let p = data[c]
            for f in 0..<frames { out[f] += p[f] }
        }
        if channels > 1 { for f in 0..<frames { out[f] /= Float(channels) } }
    }
    return out
}
