import AVFoundation
import Foundation

@MainActor
final class RecognitionViewModel: ObservableObject {
    @Published private(set) var detectedNote: PianoNote?
    @Published private(set) var centsOffset: Double = 0
    @Published private(set) var confidence: Double = 0
    @Published private(set) var frequency: Double = 0
    @Published private(set) var statusMessage = "Requesting microphone access."
    @Published private(set) var permission: AVAudioApplication.recordPermission = AVAudioApplication.shared.recordPermission
    @Published private(set) var isListening = false

    static var preview: RecognitionViewModel {
        let viewModel = RecognitionViewModel(previewMode: true)
        viewModel.detectedNote = PianoNote(midiNumber: 60, frequency: 261.63, centsOffset: -6.2)
        viewModel.centsOffset = -6.2
        viewModel.confidence = 0.84
        viewModel.frequency = 261.63
        viewModel.statusMessage = "Previewing the learner UI."
        viewModel.permission = .granted
        return viewModel
    }

    private let audioManager: AudioCaptureManager
    private let pitchDetector = PitchDetector()
    private var smoother = DetectionSmoother()
    private let previewMode: Bool
    // Ring buffer: accumulate tap chunks so the detector always gets >= 8192 samples.
    private var sampleBuffer: [Float] = []
    private let sampleBufferCapacity = 16_384   // keep last ~0.37 s at 44.1 kHz

    init(audioManager: AudioCaptureManager = AudioCaptureManager(), previewMode: Bool = false) {
        self.audioManager = audioManager
        self.previewMode = previewMode
        permission = audioManager.currentPermission()

        audioManager.onSamples = { [weak self] samples, sampleRate in
            guard let self else { return }

            // Append and trim to capacity
            self.sampleBuffer.append(contentsOf: samples)
            if self.sampleBuffer.count > self.sampleBufferCapacity {
                self.sampleBuffer.removeFirst(self.sampleBuffer.count - self.sampleBufferCapacity)
            }

            // Only analyse once we have enough data
            guard self.sampleBuffer.count >= 8_192 else { return }

            let candidate = self.pitchDetector.analyze(samples: self.sampleBuffer, sampleRate: sampleRate)
            let smoothed = self.smoother.push(candidate)

            Task { @MainActor in
                self.apply(smoothed)
            }
        }
    }

    var activeMIDINote: Int? {
        detectedNote?.midiNumber
    }

    var canStartListening: Bool {
        permission == .granted
    }

    var permissionStatusText: String {
        switch permission {
        case .granted:
            return "Microphone ready"
        case .denied:
            return "Microphone access denied"
        case .undetermined:
            return "Microphone permission pending"
        @unknown default:
            return "Unknown microphone state"
        }
    }

    var permissionIcon: String {
        permission == .granted ? "mic.fill" : "mic.slash.fill"
    }

    var frequencyText: String {
        frequency > 0 ? String(format: "%.1f Hz", frequency) : "Waiting"
    }

    var confidenceText: String {
        confidence > 0 ? String(format: "Confidence %.0f%%", confidence * 100.0) : "No stable note"
    }

    var feedbackText: String {
        guard let detectedNote else {
            return "Play one piano key at a time in a quiet room for the most stable reading."
        }

        let cents = centsOffset
        if abs(cents) < 6 {
            return "\(detectedNote.displayName) is centered."
        }
        if cents > 0 {
            return "\(detectedNote.displayName) is slightly sharp."
        }
        return "\(detectedNote.displayName) is slightly flat."
    }

    func prepareAudio() async {
        guard !previewMode else {
            return
        }

        permission = audioManager.currentPermission()
        guard permission != .granted else {
            statusMessage = "Ready to listen. Use a real device for microphone testing."
            return
        }

        let granted = await audioManager.requestPermission()
        permission = granted ? .granted : .denied
        statusMessage = granted
            ? "Ready to listen. Use a real device for microphone testing."
            : "Enable microphone access in Settings to detect piano notes."
    }

    func toggleListening() {
        guard !previewMode else {
            return
        }

        if isListening {
            audioManager.stop()
            isListening = false
            statusMessage = "Listening stopped."
            return
        }

        do {
            try audioManager.start()
            isListening = true
            statusMessage = "Listening for one piano note at a time."
        } catch {
            statusMessage = error.localizedDescription
            isListening = false
        }
    }

    private func apply(_ result: DetectionResult?) {
        detectedNote = result?.note
        centsOffset = result?.note.centsOffset ?? 0
        confidence = result?.confidence ?? 0
        frequency = result?.note.frequency ?? 0
    }
}