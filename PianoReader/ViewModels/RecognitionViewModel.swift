import AVFoundation
import Foundation

@MainActor
final class RecognitionViewModel: ObservableObject {
    @Published private(set) var detectedNotes: [PianoNote] = []
    @Published private(set) var centsOffset: Double = 0
    @Published private(set) var confidence: Double = 0
    @Published private(set) var frequency: Double = 0
    @Published private(set) var statusMessage = "Requesting microphone access."
    @Published private(set) var permission: AVAudioApplication.recordPermission = AVAudioApplication.shared.recordPermission
    @Published private(set) var isListening = false

    /// Primary (highest-confidence) note for hero display.
    var detectedNote: PianoNote? { detectedNotes.first }

    static var preview: RecognitionViewModel {
        let viewModel = RecognitionViewModel(previewMode: true)
        viewModel.detectedNotes = [
            PianoNote(midiNumber: 60, frequency: 261.63, centsOffset: -6.2),
            PianoNote(midiNumber: 64, frequency: 329.63, centsOffset: 2.1),
            PianoNote(midiNumber: 67, frequency: 392.00, centsOffset: -1.0),
        ]
        viewModel.centsOffset = -6.2
        viewModel.confidence = 0.84
        viewModel.frequency = 261.63
        viewModel.statusMessage = "Previewing the learner UI."
        viewModel.permission = .granted
        return viewModel
    }

    private let audioManager: AudioCaptureManager
    private let polyDetector = PolyphonicDetector()
    private var polySmoother = PolyphonicSmoother()
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

            let candidates = self.polyDetector.analyze(samples: self.sampleBuffer, sampleRate: sampleRate)
            let smoothed = self.polySmoother.push(candidates)

            Task { @MainActor in
                self.apply(smoothed)
            }
        }
    }

    var activeMIDINotes: Set<Int> {
        Set(detectedNotes.map(\.midiNumber))
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
        guard !detectedNotes.isEmpty else {
            return "Play piano keys in a quiet room for the most stable reading."
        }
        let names = detectedNotes.map(\.displayName).joined(separator: ", ")
        if detectedNotes.count == 1 {
            let cents = centsOffset
            if abs(cents) < 6 { return "\(names) is centered." }
            return cents > 0 ? "\(names) is slightly sharp." : "\(names) is slightly flat."
        }
        return "\(detectedNotes.count) notes: \(names)"
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

    private func apply(_ results: [DetectionResult]) {
        detectedNotes = results.map(\.note)
        let primary = results.max(by: { $0.confidence < $1.confidence })
        centsOffset = primary?.note.centsOffset ?? 0
        confidence = primary?.confidence ?? 0
        frequency = primary?.note.frequency ?? 0
    }
}