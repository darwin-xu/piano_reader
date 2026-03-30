import AVFoundation
import CoreGraphics
import Foundation

@MainActor
final class RecognitionViewModel: ObservableObject {
    @Published private(set) var detectedNotes: [PianoNote] = []
    @Published private(set) var centsOffset: Double = 0
    @Published private(set) var confidence: Double = 0
    @Published private(set) var frequency: Double = 0
    @Published private(set) var waveformEnvelope: Array<CGFloat> = Array(repeating: 0, count: 40)
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
        viewModel.waveformEnvelope = [0.08, 0.14, 0.20, 0.34, 0.56, 0.74, 0.88, 0.80, 0.64, 0.42, 0.24, 0.16, 0.20, 0.30, 0.46, 0.66, 0.82, 0.72, 0.52, 0.30, 0.14, 0.10, 0.16, 0.28, 0.44, 0.62, 0.78, 0.70, 0.50, 0.28, 0.16, 0.10, 0.12, 0.18, 0.30, 0.48, 0.62, 0.50, 0.26, 0.12]
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
    private let waveformBinCount = 40

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

            let envelope = self.makeWaveformEnvelope(from: self.sampleBuffer)
            Task { @MainActor in
                self.waveformEnvelope = envelope
            }

            // Only analyse once we have enough data (16384 for HarmonicSalienceDetector)
            guard self.sampleBuffer.count >= 16_384 else { return }

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

    var waveformDetailText: String {
        if frequency > 0 {
            return String(format: "%.1f Hz", frequency)
        }
        return isListening ? "Listening" : "Tap to start"
    }

    var waveformNoteLabel: String {
        guard !detectedNotes.isEmpty else {
            return isListening ? "Listening for notes" : "Mic idle"
        }
        return detectedNotes.map(\.displayName).joined(separator: " · ")
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
            waveformEnvelope = Array(repeating: 0, count: waveformBinCount)
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

    private func makeWaveformEnvelope(from samples: [Float]) -> [CGFloat] {
        guard !samples.isEmpty else {
            return Array(repeating: 0, count: waveformBinCount)
        }

        let recentCount = min(samples.count, 6_144)
        let recent = Array(samples.suffix(recentCount))
        let maxPeak = recent.reduce(Float.zero) { max($0, abs($1)) }
        if maxPeak < 0.01 {
            return Array(repeating: 0, count: waveformBinCount)
        }
        let chunkSize = max(recent.count / waveformBinCount, 1)
        var envelope: [CGFloat] = []
        envelope.reserveCapacity(waveformBinCount)

        var index = 0
        while index < recent.count {
            let end = min(index + chunkSize, recent.count)
            let slice = recent[index..<end]
            var peak: Float = 0
            for sample in slice {
                peak = max(peak, abs(sample))
            }

            let normalized = min(CGFloat(peak) * 2.6, 1.0)
            envelope.append(normalized)
            index = end
        }

        if envelope.count < waveformBinCount {
            envelope.insert(contentsOf: Array(repeating: 0, count: waveformBinCount - envelope.count), at: 0)
        } else if envelope.count > waveformBinCount {
            envelope = Array(envelope.suffix(waveformBinCount))
        }

        let previous = waveformEnvelope
        return envelope.enumerated().map { offset, value in
            let prior = previous.indices.contains(offset) ? previous[offset] : value
            return (prior * 0.45) + (value * 0.55)
        }
    }
}
