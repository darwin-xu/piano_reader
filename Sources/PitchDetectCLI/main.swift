import Accelerate
import Foundation
import PitchDetectCore

// MARK: - Report types

struct SampleReport: Codable {
    let fileName: String
    let expected: String
    let predicted: String?
    let predictedNotes: [String]?
    let predictedFrequencyHz: Double?
    let confidence: Double?
    let centsError: Double?
    let status: String
}

struct ChordSampleReport: Codable {
    let fileName: String
    let expectedLabel: String
    let expectedPitchClasses: [String]
    let detectedPitchClasses: [String]
    let precision: Double
    let recall: Double
    let f1: Double
}

struct NoiseSampleReport: Codable {
    let fileName: String
    let detectedNotes: [String]
    let hasFalsePositive: Bool
}

struct NoiseMixSampleReport: Codable {
    let signalFile: String
    let noiseFile: String
    let snrDb: Double
    let expectedLabel: String
    let expectedPitchClasses: [String]
    let detectedPitchClasses: [String]
    let isCorrect: Bool
    let recall: Double
}

// MARK: - Summary types

struct EvaluationSummary: Codable {
    let directory: String
    let generatedAt: String
    let totalSamples: Int
    let singleNoteSamples: Int
    let chordSamples: Int
    let unknownSamples: Int
    let evaluatedSingleNoteSamples: Int
    let correctSingleNotePredictions: Int
    let singleNoteAccuracy: Double
    let meanAbsoluteCentsError: Double?
    let reports: [SampleReport]
}

struct ChordEvaluationSummary: Codable {
    let directory: String
    let generatedAt: String
    let totalChordSamples: Int
    let meanPrecision: Double
    let meanRecall: Double
    let meanF1: Double
    let fullyCorrectCount: Int
    let reports: [ChordSampleReport]
}

struct NoiseEvaluationSummary: Codable {
    let directory: String
    let generatedAt: String
    let totalNoiseSamples: Int
    let falsePositiveCount: Int
    let falsePositiveRate: Double
    let reports: [NoiseSampleReport]
}

struct NoiseMixSNRBucket: Codable {
    let snrDb: Double
    let singleNoteAccuracy: Double?
    let chordMeanRecall: Double?
    let totalTests: Int
}

struct NoiseMixEvaluationSummary: Codable {
    let generatedAt: String
    let snrLevels: [Double]
    let buckets: [NoiseMixSNRBucket]
    let reports: [NoiseMixSampleReport]
}

// MARK: - Helpers

func rootMeanSquare(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return 0 }
    var rms: Float = 0
    var s = samples
    vDSP_rmsqv(&s, 1, &rms, vDSP_Length(samples.count))
    return Double(rms)
}

func mixSignalAndNoise(signal: [Float], noise: [Float], snrDb: Double) -> [Float] {
    let signalRMS = rootMeanSquare(signal)
    let noiseRMS = rootMeanSquare(noise)
    guard noiseRMS > 0, signalRMS > 0 else { return signal }
    let noiseGain = Float(signalRMS / noiseRMS / pow(10.0, snrDb / 20.0))
    var mixed = [Float](repeating: 0, count: signal.count)
    for i in 0..<signal.count {
        mixed[i] = signal[i] + noise[i % noise.count] * noiseGain
    }
    return mixed
}

func computePrecisionRecallF1(expected: Set<String>, detected: Set<String>) -> (precision: Double, recall: Double, f1: Double) {
    guard !detected.isEmpty || !expected.isEmpty else {
        return (1.0, 1.0, 1.0)
    }
    let tp = expected.intersection(detected).count
    let precision = detected.isEmpty ? 0 : Double(tp) / Double(detected.count)
    let recall = expected.isEmpty ? 0 : Double(tp) / Double(expected.count)
    let f1 = (precision + recall) > 0 ? 2 * precision * recall / (precision + recall) : 0
    return (precision, recall, f1)
}

func expectedSingleNoteName(from expectedLabel: String) -> String? {
    guard expectedLabel.hasPrefix("single:") else { return nil }
    return String(expectedLabel.dropFirst("single:".count))
}

// MARK: - Evaluation runners

func evaluateSingleNote(
    directory: URL,
    multiDetector: HarmonicSalienceDetector,
    yinDetector: YINPitchDetector
) throws -> EvaluationSummary {
    let descriptors = try SampleCatalog.discover(in: directory)
    var reports: [SampleReport] = []

    for descriptor in descriptors {
        let clip = try AudioFileLoader.load(from: descriptor.fileURL)
        let multiResult = try multiDetector.analyzeMulti(audioClip: clip)
        let yinResult = try yinDetector.analyze(audioClip: clip)

        switch descriptor.expectation {
        case .single(let expectedNote):
            let multiNames = multiResult.detectedNotes.map(\.name)
            let dominant = yinResult.dominantPitch
            let centsError = dominant?.frequencyHz.map { Note.centsOffset(from: $0, to: expectedNote) }

            let multiCorrect = multiResult.detectedNotes.contains { $0.name == expectedNote.name }
            let predicted = multiCorrect ? expectedNote.name : multiResult.detectedNotes.first?.name

            reports.append(SampleReport(
                fileName: descriptor.fileURL.lastPathComponent,
                expected: "single:\(expectedNote.name)",
                predicted: predicted,
                predictedNotes: multiNames,
                predictedFrequencyHz: dominant?.frequencyHz,
                confidence: dominant?.confidence,
                centsError: centsError,
                status: "evaluated"
            ))

        case .chord(let label, _):
            reports.append(SampleReport(
                fileName: descriptor.fileURL.lastPathComponent,
                expected: "chord:\(label)",
                predicted: nil,
                predictedNotes: multiResult.detectedNotes.map(\.name),
                predictedFrequencyHz: nil,
                confidence: nil,
                centsError: nil,
                status: "chord-in-single-dir"
            ))

        case .noise:
            reports.append(SampleReport(
                fileName: descriptor.fileURL.lastPathComponent,
                expected: "noise",
                predicted: nil,
                predictedNotes: nil,
                predictedFrequencyHz: nil,
                confidence: nil,
                centsError: nil,
                status: "noise-in-single-dir"
            ))

        case .unknown:
            reports.append(SampleReport(
                fileName: descriptor.fileURL.lastPathComponent,
                expected: "unknown",
                predicted: nil,
                predictedNotes: multiResult.detectedNotes.map(\.name),
                predictedFrequencyHz: nil,
                confidence: nil,
                centsError: nil,
                status: "unknown-label"
            ))
        }
    }

    let singleReports = reports.filter { $0.status == "evaluated" }
    let correctReports = singleReports.filter {
        guard let predicted = $0.predicted,
              let expected = expectedSingleNoteName(from: $0.expected)
        else { return false }
        return expected == predicted
    }
    let centsErrors = singleReports.compactMap(\.centsError).map(abs)

    return EvaluationSummary(
        directory: directory.path,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        totalSamples: reports.count,
        singleNoteSamples: singleReports.count,
        chordSamples: reports.filter { $0.status == "chord-in-single-dir" }.count,
        unknownSamples: reports.filter { $0.status == "unknown-label" }.count,
        evaluatedSingleNoteSamples: singleReports.count,
        correctSingleNotePredictions: correctReports.count,
        singleNoteAccuracy: singleReports.isEmpty ? 0 : Double(correctReports.count) / Double(singleReports.count),
        meanAbsoluteCentsError: centsErrors.isEmpty ? nil : centsErrors.reduce(0, +) / Double(centsErrors.count),
        reports: reports
    )
}

func evaluateChord(
    directory: URL,
    multiDetector: HarmonicSalienceDetector
) throws -> ChordEvaluationSummary {
    let descriptors = try SampleCatalog.discover(in: directory)
    var reports: [ChordSampleReport] = []

    for descriptor in descriptors {
        guard case .chord(let label, let expectedPCs) = descriptor.expectation else { continue }
        let clip = try AudioFileLoader.load(from: descriptor.fileURL)
        let result = try multiDetector.analyzeMulti(audioClip: clip)
        let detectedPCs = Array(Set(result.detectedNotes.map(\.pitchClass)))
        let (precision, recall, f1) = computePrecisionRecallF1(
            expected: Set(expectedPCs),
            detected: Set(detectedPCs)
        )
        reports.append(ChordSampleReport(
            fileName: descriptor.fileURL.lastPathComponent,
            expectedLabel: label,
            expectedPitchClasses: expectedPCs.sorted(),
            detectedPitchClasses: detectedPCs.sorted(),
            precision: precision,
            recall: recall,
            f1: f1
        ))
    }

    let meanPrecision = reports.isEmpty ? 0 : reports.map(\.precision).reduce(0, +) / Double(reports.count)
    let meanRecall = reports.isEmpty ? 0 : reports.map(\.recall).reduce(0, +) / Double(reports.count)
    let meanF1 = reports.isEmpty ? 0 : reports.map(\.f1).reduce(0, +) / Double(reports.count)
    let fullyCorrect = reports.filter { $0.precision >= 1.0 && $0.recall >= 1.0 }.count

    return ChordEvaluationSummary(
        directory: directory.path,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        totalChordSamples: reports.count,
        meanPrecision: meanPrecision,
        meanRecall: meanRecall,
        meanF1: meanF1,
        fullyCorrectCount: fullyCorrect,
        reports: reports
    )
}

func evaluateNoise(
    directory: URL,
    multiDetector: HarmonicSalienceDetector
) throws -> NoiseEvaluationSummary {
    let descriptors = try SampleCatalog.discover(in: directory)
    var reports: [NoiseSampleReport] = []

    for descriptor in descriptors {
        let clip = try AudioFileLoader.load(from: descriptor.fileURL)
        let result = try multiDetector.analyzeMulti(audioClip: clip)
        let detectedNames = result.detectedNotes.map(\.name)
        reports.append(NoiseSampleReport(
            fileName: descriptor.fileURL.lastPathComponent,
            detectedNotes: detectedNames,
            hasFalsePositive: !detectedNames.isEmpty
        ))
    }

    let fpCount = reports.filter(\.hasFalsePositive).count
    return NoiseEvaluationSummary(
        directory: directory.path,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        totalNoiseSamples: reports.count,
        falsePositiveCount: fpCount,
        falsePositiveRate: reports.isEmpty ? 0 : Double(fpCount) / Double(reports.count),
        reports: reports
    )
}

func evaluateNoiseMix(
    singleNoteDir: URL,
    chordDir: URL,
    noiseDir: URL,
    multiDetector: HarmonicSalienceDetector,
    snrLevels: [Double]
) throws -> NoiseMixEvaluationSummary {
    let noiseDescriptors = try SampleCatalog.discover(in: noiseDir)
    let noiseClips = try noiseDescriptors.map { try AudioFileLoader.load(from: $0.fileURL) }

    let singleDescriptors = try SampleCatalog.discover(in: singleNoteDir)
    let chordDescriptors = try SampleCatalog.discover(in: chordDir)

    var reports: [NoiseMixSampleReport] = []

    for snr in snrLevels {
        for noiseClip in noiseClips {
            for descriptor in singleDescriptors {
                guard case .single(let expectedNote) = descriptor.expectation else { continue }
                let signalClip = try AudioFileLoader.load(from: descriptor.fileURL)
                let mixed = mixSignalAndNoise(signal: signalClip.samples, noise: noiseClip.samples, snrDb: snr)
                let mixedClip = AudioClip(fileURL: descriptor.fileURL, samples: mixed, sampleRate: signalClip.sampleRate)
                let result = try multiDetector.analyzeMulti(audioClip: mixedClip)
                let detectedPCs = result.detectedNotes.map(\.pitchClass)
                let isCorrect = result.detectedNotes.contains { $0.name == expectedNote.name }

                reports.append(NoiseMixSampleReport(
                    signalFile: descriptor.fileURL.lastPathComponent,
                    noiseFile: noiseClip.fileURL.lastPathComponent,
                    snrDb: snr,
                    expectedLabel: "single:\(expectedNote.name)",
                    expectedPitchClasses: [expectedNote.pitchClass],
                    detectedPitchClasses: detectedPCs,
                    isCorrect: isCorrect,
                    recall: isCorrect ? 1.0 : 0.0
                ))
            }
            for descriptor in chordDescriptors {
                guard case .chord(let label, let expectedPCs) = descriptor.expectation else { continue }
                guard !expectedPCs.isEmpty else { continue }
                let signalClip = try AudioFileLoader.load(from: descriptor.fileURL)
                let mixed = mixSignalAndNoise(signal: signalClip.samples, noise: noiseClip.samples, snrDb: snr)
                let mixedClip = AudioClip(fileURL: descriptor.fileURL, samples: mixed, sampleRate: signalClip.sampleRate)
                let result = try multiDetector.analyzeMulti(audioClip: mixedClip)
                let detectedPCs = Set(result.detectedNotes.map(\.pitchClass))
                let tp = Set(expectedPCs).intersection(detectedPCs).count
                let recall = Double(tp) / Double(expectedPCs.count)

                reports.append(NoiseMixSampleReport(
                    signalFile: descriptor.fileURL.lastPathComponent,
                    noiseFile: noiseClip.fileURL.lastPathComponent,
                    snrDb: snr,
                    expectedLabel: "chord:\(label)",
                    expectedPitchClasses: expectedPCs.sorted(),
                    detectedPitchClasses: detectedPCs.sorted(),
                    isCorrect: recall >= 1.0,
                    recall: recall
                ))
            }
        }
    }

    let buckets = snrLevels.map { snr -> NoiseMixSNRBucket in
        let snrReports = reports.filter { $0.snrDb == snr }
        let singleReports = snrReports.filter { $0.expectedLabel.hasPrefix("single:") }
        let chordReports = snrReports.filter { $0.expectedLabel.hasPrefix("chord:") }
        let singleAcc: Double? = singleReports.isEmpty ? nil :
            Double(singleReports.filter(\.isCorrect).count) / Double(singleReports.count)
        let chordRecall: Double? = chordReports.isEmpty ? nil :
            chordReports.map(\.recall).reduce(0, +) / Double(chordReports.count)
        return NoiseMixSNRBucket(
            snrDb: snr,
            singleNoteAccuracy: singleAcc,
            chordMeanRecall: chordRecall,
            totalTests: snrReports.count
        )
    }

    return NoiseMixEvaluationSummary(
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        snrLevels: snrLevels,
        buckets: buckets,
        reports: reports
    )
}

// MARK: - Output and printing

struct CombinedEvaluationRun: Codable {
    let runAt: String
    let singleNote: EvaluationSummary?
    let chord: ChordEvaluationSummary?
    let noise: NoiseEvaluationSummary?
    let noiseMix: NoiseMixEvaluationSummary?
}

func appendRun(_ run: CombinedEvaluationRun, workingDirectory: URL) throws {
    let outputDirectory = workingDirectory.appendingPathComponent("evaluation/results")
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let outputURL = outputDirectory.appendingPathComponent("results.json")
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var runs: [CombinedEvaluationRun] = []
    if let existingData = try? Data(contentsOf: outputURL),
       let existing = try? decoder.decode([CombinedEvaluationRun].self, from: existingData) {
        runs = existing
    }
    runs.append(run)
    let data = try encoder.encode(runs)
    try data.write(to: outputURL)
}

func printSingleNoteSummary(_ summary: EvaluationSummary) {
    print("=== Single-Note Evaluation ===")
    print("Samples: \(summary.totalSamples)")
    print("Evaluated: \(summary.evaluatedSingleNoteSamples)/\(summary.singleNoteSamples)")
    print(String(format: "Accuracy: %.2f%%", summary.singleNoteAccuracy * 100.0))
    if let mae = summary.meanAbsoluteCentsError {
        print(String(format: "Mean absolute cents error: %.2f", mae))
    }
    for report in summary.reports where report.status == "evaluated" {
        let match = report.predicted == expectedSingleNoteName(from: report.expected) ? "✓" : "✗"
        let notesStr = report.predictedNotes?.joined(separator: ",") ?? "–"
        print("  \(match) \(report.fileName): expected=\(report.expected) detected=[\(notesStr)]")
    }
    print()
}

func printChordSummary(_ summary: ChordEvaluationSummary) {
    print("=== Chord Evaluation ===")
    print("Samples: \(summary.totalChordSamples)")
    print(String(format: "Mean Precision: %.2f%%", summary.meanPrecision * 100))
    print(String(format: "Mean Recall:    %.2f%%", summary.meanRecall * 100))
    print(String(format: "Mean F1:        %.2f%%", summary.meanF1 * 100))
    print("Fully correct:  \(summary.fullyCorrectCount)/\(summary.totalChordSamples)")
    for report in summary.reports {
        let mark = (report.precision >= 1.0 && report.recall >= 1.0) ? "✓" : "✗"
        print("  \(mark) \(report.fileName): expected=\(report.expectedPitchClasses) detected=\(report.detectedPitchClasses) P=\(String(format:"%.0f%%",report.precision*100)) R=\(String(format:"%.0f%%",report.recall*100))")
    }
    print()
}

func printNoiseSummary(_ summary: NoiseEvaluationSummary) {
    print("=== Pure Noise Evaluation ===")
    print("Samples: \(summary.totalNoiseSamples)")
    print("False positives: \(summary.falsePositiveCount)")
    print(String(format: "FP rate: %.2f%%", summary.falsePositiveRate * 100))
    for report in summary.reports {
        let mark = report.hasFalsePositive ? "✗" : "✓"
        let notes = report.detectedNotes.isEmpty ? "none" : report.detectedNotes.joined(separator: ",")
        print("  \(mark) \(report.fileName): detected=[\(notes)]")
    }
    print()
}

func printNoiseMixSummary(_ summary: NoiseMixEvaluationSummary) {
    print("=== Noise-Mix SNR Table ===")
    let header = "SNR dB    Single-note Acc     Chord Recall        Tests"
    print(header)
    for bucket in summary.buckets {
        let sAcc = bucket.singleNoteAccuracy.map { String(format: "%.1f%%", $0 * 100) } ?? "–"
        let cRec = bucket.chordMeanRecall.map { String(format: "%.1f%%", $0 * 100) } ?? "–"
        let snrStr = String(format: "%.0f", bucket.snrDb).padding(toLength: 10, withPad: " ", startingAt: 0)
        let sAccStr = sAcc.padding(toLength: 20, withPad: " ", startingAt: 0)
        let cRecStr = cRec.padding(toLength: 20, withPad: " ", startingAt: 0)
        print("\(snrStr)\(sAccStr)\(cRecStr)\(bucket.totalTests)")
    }
    print()
}

// MARK: - Entry point

@main
struct PitchDetectCLI {
    static func main() throws {
        let arguments = CommandLine.arguments
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let multiDetector = HarmonicSalienceDetector()
        let yinDetector = YINPitchDetector()

        // Determine the samples base directory.
        // If an argument is given it is treated as the note_sample directory and
        // its parent is used as samplesBase so that sibling chord/noise
        // directories are also discovered automatically.
        // With no argument, samplesBase defaults to Samples/ under the CWD.
        let samplesBase: URL
        if arguments.count > 1 {
            let given = URL(fileURLWithPath: arguments[1], relativeTo: workingDirectory).standardizedFileURL
            samplesBase = given.deletingLastPathComponent()
        } else {
            samplesBase = workingDirectory.appendingPathComponent("Samples")
        }
        let singleNoteDir = samplesBase.appendingPathComponent("note_sample")
        let chordDir = samplesBase.appendingPathComponent("note_sample_chord")
        let noiseDir = samplesBase.appendingPathComponent("noise_sample")
        let snrLevels: [Double] = [-10, -5, 0, 5, 10]

        // 1. Single-note
        var singleSummary: EvaluationSummary? = nil
        if FileManager.default.fileExists(atPath: singleNoteDir.path) {
            singleSummary = try evaluateSingleNote(
                directory: singleNoteDir,
                multiDetector: multiDetector,
                yinDetector: yinDetector
            )
            printSingleNoteSummary(singleSummary!)
        }

        // 2. Chord
        var chordSummary: ChordEvaluationSummary? = nil
        if FileManager.default.fileExists(atPath: chordDir.path) {
            chordSummary = try evaluateChord(directory: chordDir, multiDetector: multiDetector)
            printChordSummary(chordSummary!)
        }

        // 3. Pure noise
        var noiseSummary: NoiseEvaluationSummary? = nil
        if FileManager.default.fileExists(atPath: noiseDir.path) {
            noiseSummary = try evaluateNoise(directory: noiseDir, multiDetector: multiDetector)
            printNoiseSummary(noiseSummary!)
        }

        // 4. Noise-mix
        var noiseMixSummary: NoiseMixEvaluationSummary? = nil
        let hasSingleOrChord = FileManager.default.fileExists(atPath: singleNoteDir.path)
            || FileManager.default.fileExists(atPath: chordDir.path)
        if FileManager.default.fileExists(atPath: noiseDir.path) && hasSingleOrChord {
            noiseMixSummary = try evaluateNoiseMix(
                singleNoteDir: singleNoteDir,
                chordDir: chordDir,
                noiseDir: noiseDir,
                multiDetector: multiDetector,
                snrLevels: snrLevels
            )
            printNoiseMixSummary(noiseMixSummary!)
        }

        // Append combined run to results.json
        let run = CombinedEvaluationRun(
            runAt: ISO8601DateFormatter().string(from: Date()),
            singleNote: singleSummary,
            chord: chordSummary,
            noise: noiseSummary,
            noiseMix: noiseMixSummary
        )
        try appendRun(run, workingDirectory: workingDirectory)
        print("Results appended → evaluation/results/results.json")
    }
}
