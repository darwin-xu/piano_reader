import AVFoundation
import Foundation

final class AudioCaptureManager {
    enum AudioError: LocalizedError {
        case denied
        case engineUnavailable

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Microphone access was denied."
            case .engineUnavailable:
                return "The audio engine could not start."
            }
        }
    }

    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private let analysisQueue = DispatchQueue(label: "com.example.PianoReader.analysis", qos: .userInitiated)
    private var hasTapInstalled = false

    var onSamples: (([Float], Double) -> Void)?

    func currentPermission() -> AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw AudioError.denied
        }

        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setPreferredSampleRate(44_100)
        try session.setPreferredIOBufferDuration(0.023)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        if !hasTapInstalled {
            inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
                guard let self, let samples = buffer.floatChannelData?.pointee else {
                    return
                }

                let frameCount = Int(buffer.frameLength)
                let copiedSamples = Array(UnsafeBufferPointer(start: samples, count: frameCount))
                self.analysisQueue.async {
                    self.onSamples?(copiedSamples, inputFormat.sampleRate)
                }
            }
            hasTapInstalled = true
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AudioError.engineUnavailable
        }
    }

    func stop() {
        engine.stop()
        if hasTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        try? session.setActive(false)
    }
}