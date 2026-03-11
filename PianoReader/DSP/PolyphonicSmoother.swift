import Foundation

/// Temporal smoothing for polyphonic detection.
/// Tracks each MIDI note independently — a note must appear in multiple consecutive
/// frames to be confirmed, and persists briefly after disappearing.
struct PolyphonicSmoother {
    private let confirmationFrames = 3
    private let decayFrames = 3

    private var trackers: [Int: NoteTracker] = [:]

    private struct NoteTracker {
        var result: DetectionResult
        var hitCount: Int
        var missCount: Int
        var isConfirmed: Bool
    }

    mutating func push(_ raw: [DetectionResult]) -> [DetectionResult] {
        let present = Set(raw.map { $0.note.midiNumber })

        // Update / create trackers for present notes
        for r in raw {
            let midi = r.note.midiNumber
            if var t = trackers[midi] {
                t.result = r
                t.hitCount += 1
                t.missCount = 0
                if t.hitCount >= confirmationFrames { t.isConfirmed = true }
                trackers[midi] = t
            } else {
                trackers[midi] = NoteTracker(result: r, hitCount: 1, missCount: 0, isConfirmed: false)
            }
        }

        // Increment miss for absent notes
        for midi in trackers.keys where !present.contains(midi) {
            trackers[midi]!.missCount += 1
            if trackers[midi]!.missCount > decayFrames {
                trackers[midi]!.isConfirmed = false
            }
            if trackers[midi]!.missCount > decayFrames * 3 {
                trackers.removeValue(forKey: midi)
            }
        }

        let confirmed = trackers.values
            .filter(\.isConfirmed)
            .map(\.result)
            .sorted { $0.note.midiNumber < $1.note.midiNumber }

        return confirmed
    }
}
