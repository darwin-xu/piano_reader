import Foundation

public struct Note: Codable, Hashable, Sendable {
    public let midi: Int

    public init(midi: Int) {
        self.midi = midi
    }

    public init?(name: String) {
        let pattern = #"^([A-G])(#?)(-?\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, range: range),
              let letterRange = Range(match.range(at: 1), in: name),
              let sharpRange = Range(match.range(at: 2), in: name),
              let octaveRange = Range(match.range(at: 3), in: name),
              let octave = Int(name[octaveRange])
        else {
            return nil
        }

        let noteBase: [String: Int] = [
            "C": 0,
            "D": 2,
            "E": 4,
            "F": 5,
            "G": 7,
            "A": 9,
            "B": 11,
        ]

        let baseKey = String(name[letterRange])
        guard var semitone = noteBase[baseKey] else {
            return nil
        }
        if !name[sharpRange].isEmpty {
            semitone += 1
        }
        self.midi = (octave + 1) * 12 + semitone
    }

    public var frequencyHz: Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    public var name: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pc = ((midi % 12) + 12) % 12
        let octave = (midi / 12) - 1
        return "\(names[pc])\(octave)"
    }

    public var pitchClass: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pc = ((midi % 12) + 12) % 12
        return names[pc]
    }

    public static func nearest(to frequencyHz: Double) -> Note {
        let midi = Int(round(69.0 + 12.0 * log2(frequencyHz / 440.0)))
        return Note(midi: midi)
    }

    public static func centsOffset(from frequencyHz: Double, to note: Note) -> Double {
        1200.0 * log2(frequencyHz / note.frequencyHz)
    }
}
