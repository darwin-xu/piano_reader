import Foundation

struct DetectionSmoother {
    private let confirmationCount = 2        // require 2 matching frames (was 3)
    private let historyLimit = 5
    private let minimumConfidence = 0.30     // match detector gate (was 0.56)
    private let octaveJumpConfidenceBonus = 0.18

    private var history: [DetectionResult] = []
    private var activeResult: DetectionResult?

    mutating func push(_ result: DetectionResult?) -> DetectionResult? {
        guard let result, result.confidence >= minimumConfidence else {
            // Keep the last stable note visible instead of clearing on brief silence.
            return activeResult
        }

        let normalizedResult = suppressOctaveJumpIfNeeded(result)
        history.append(normalizedResult)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }

        let matching = history.filter { $0.note.midiNumber == normalizedResult.note.midiNumber }
        if matching.count >= confirmationCount {
            activeResult = normalizedResult
        }

        return activeResult
    }

    private func suppressOctaveJumpIfNeeded(_ result: DetectionResult) -> DetectionResult {
        guard let activeResult else {
            return result
        }

        let midiDelta = result.note.midiNumber - activeResult.note.midiNumber
        let samePitchClass = result.note.pitchClass == activeResult.note.pitchClass
        let isOctaveJump = abs(midiDelta) == 12
        let confidenceImprovedEnough = result.confidence >= activeResult.confidence + octaveJumpConfidenceBonus

        guard samePitchClass, isOctaveJump, !confidenceImprovedEnough else {
            return result
        }

        return DetectionResult(note: activeResult.note, confidence: result.confidence, amplitude: result.amplitude)
    }
}