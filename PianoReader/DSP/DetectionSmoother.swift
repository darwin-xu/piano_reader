import Foundation

struct DetectionSmoother {
    private let confirmationCount = 2        // require 2 matching frames (was 3)
    private let historyLimit = 5
    private let minimumConfidence = 0.30     // match detector gate (was 0.56)
    private let missTolerance = 5            // allow 5 miss frames before clearing

    private var history: [DetectionResult] = []
    private var activeResult: DetectionResult?
    private var missCount = 0

    mutating func push(_ result: DetectionResult?) -> DetectionResult? {
        guard let result, result.confidence >= minimumConfidence else {
            missCount += 1
            if missCount >= missTolerance {
                history.removeAll(keepingCapacity: true)
                activeResult = nil
                missCount = 0
            }
            return activeResult
        }

        missCount = 0
        history.append(result)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }

        let matching = history.filter { $0.note.midiNumber == result.note.midiNumber }
        if matching.count >= confirmationCount {
            activeResult = result
        }

        return activeResult
    }
}