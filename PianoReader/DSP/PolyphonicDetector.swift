import Accelerate
import Foundation

/// Wraps HarmonicSalienceDetector for live audio streaming.
/// Converts the clip-based multi-pitch results into the [DetectionResult]
/// interface expected by RecognitionViewModel and PolyphonicSmoother.
struct PolyphonicDetector {
    private let detector = HarmonicSalienceDetector()

    func analyze(samples: [Float], sampleRate: Double) -> [DetectionResult] {
        let clip = AudioClip(
            fileURL: URL(fileURLWithPath: "/dev/null"),
            samples: samples,
            sampleRate: sampleRate
        )

        guard let result = try? detector.analyzeMulti(audioClip: clip) else {
            return []
        }

        let maxSalience = result.detectedNotes.map(\.salience).max() ?? 1.0

        // Compute RMS for amplitude field
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        return result.detectedNotes.compactMap { detected in
            guard let note = PianoNote.from(frequency: detected.frequencyHz) else {
                return nil
            }
            let confidence = maxSalience > 0 ? detected.salience / maxSalience : 0
            return DetectionResult(note: note, confidence: confidence, amplitude: rms)
        }
    }
}
