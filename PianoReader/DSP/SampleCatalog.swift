import Foundation

public enum SampleExpectation: Codable, Sendable {
    case single(Note)
    case chord(label: String, pitchClasses: [String])
    case noise
    case unknown
}

public struct SampleDescriptor: Codable, Sendable {
    public let fileURL: URL
    public let expectation: SampleExpectation

    public init(fileURL: URL, expectation: SampleExpectation) {
        self.fileURL = fileURL
        self.expectation = expectation
    }
}

public enum SampleCatalog {
    private static let supportedExtensions: Set<String> = ["wav", "m4a", "aac", "mp3"]

    public static func discover(in directoryURL: URL) throws -> [SampleDescriptor] {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return entries
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { SampleDescriptor(fileURL: $0, expectation: parseExpectation(from: $0)) }
    }

    // MARK: - Named chord lookup

    private static let namedChordPitchClasses: [String: [String]] = [
        "C_major": ["C", "E", "G"],
        "C_minor": ["C", "D#", "G"],
        "D_major": ["D", "F#", "A"],
        "D_minor": ["D", "F", "A"],
        "E_major": ["E", "G#", "B"],
        "E_minor": ["E", "G", "B"],
        "F_major": ["F", "A", "C"],
        "F_minor": ["F", "G#", "C"],
        "G_major": ["G", "B", "D"],
        "G_minor": ["G", "A#", "D"],
        "A_major": ["A", "C#", "E"],
        "A_minor": ["A", "C", "E"],
        "B_major": ["B", "D#", "F#"],
        "B_minor": ["B", "D", "F#"],
    ]

    // MARK: - Parsing

    private static func parseExpectation(from url: URL) -> SampleExpectation {
        let stem = url.deletingPathExtension().lastPathComponent

        // Noise: noise-1, noise_2, etc.
        let noisePattern = #"^noise[-_]\d+$"#
        if let regex = try? NSRegularExpression(pattern: noisePattern, options: .caseInsensitive) {
            let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
            if regex.firstMatch(in: stem, range: range) != nil {
                return .noise
            }
        }

        // Single note: C4_1, A#4_2
        let singlePattern = #"^([A-G](?:#)?\d+)_\d+$"#
        if let regex = try? NSRegularExpression(pattern: singlePattern) {
            let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
            if let match = regex.firstMatch(in: stem, range: range),
               let noteRange = Range(match.range(at: 1), in: stem),
               let note = Note(name: String(stem[noteRange])) {
                return .single(note)
            }
        }

        // Named chord: C_major_chord_1, D_minor_chord_1
        let namedChordPattern = #"^([A-G](?:#)?_[a-z]+)_chord_\d+$"#
        if let regex = try? NSRegularExpression(pattern: namedChordPattern) {
            let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
            if let match = regex.firstMatch(in: stem, range: range),
               let labelRange = Range(match.range(at: 1), in: stem) {
                let label = String(stem[labelRange])
                let pitchClasses = namedChordPitchClasses[label] ?? []
                return .chord(label: label + "_chord", pitchClasses: pitchClasses)
            }
        }

        // Dyad: C_A#_1, E_F_2  (two pitch classes separated by _)
        let dyadPattern = #"^([A-G](?:#)?)_([A-G](?:#)?)_\d+$"#
        if let regex = try? NSRegularExpression(pattern: dyadPattern) {
            let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
            if let match = regex.firstMatch(in: stem, range: range),
               let pc1Range = Range(match.range(at: 1), in: stem),
               let pc2Range = Range(match.range(at: 2), in: stem) {
                let pc1 = String(stem[pc1Range])
                let pc2 = String(stem[pc2Range])
                return .chord(label: "\(pc1)_\(pc2)", pitchClasses: [pc1, pc2])
            }
        }

        return .unknown
    }
}
