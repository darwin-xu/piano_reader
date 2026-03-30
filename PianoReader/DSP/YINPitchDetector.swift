import Foundation

public struct YINConfiguration: Sendable {
    public let frameSize: Int
    public let hopSize: Int
    public let minimumFrequencyHz: Double
    public let maximumFrequencyHz: Double
    public let yinThreshold: Double
    public let minimumRMS: Double
    public let minimumConfidence: Double
    public let relativeRMSWindowFloor: Double
    public let maximumAnalyzedFrames: Int

    public init(
        frameSize: Int = 4096,
        hopSize: Int = 1024,
        minimumFrequencyHz: Double = 55.0,
        maximumFrequencyHz: Double = 4186.0,
        yinThreshold: Double = 0.10,
        minimumRMS: Double = 0.01,
        minimumConfidence: Double = 0.75,
        relativeRMSWindowFloor: Double = 0.75,
        maximumAnalyzedFrames: Int = 4
    ) {
        self.frameSize = frameSize
        self.hopSize = hopSize
        self.minimumFrequencyHz = minimumFrequencyHz
        self.maximumFrequencyHz = maximumFrequencyHz
        self.yinThreshold = yinThreshold
        self.minimumRMS = minimumRMS
        self.minimumConfidence = minimumConfidence
        self.relativeRMSWindowFloor = relativeRMSWindowFloor
        self.maximumAnalyzedFrames = maximumAnalyzedFrames
    }
}

private struct AnalysisWindow {
    let frameIndex: Int
    let samples: [Float]
    let rms: Double
}

public struct YINPitchDetector: PitchDetector {
    public let configuration: YINConfiguration

    public init(configuration: YINConfiguration = YINConfiguration()) {
        self.configuration = configuration
    }

    public func analyze(audioClip: AudioClip) throws -> ClipDetection {
        let windows = makeAnalysisWindows(samples: audioClip.samples)
        let selectedWindows = selectWindowsForAnalysis(windows)
        let analyzedFrames = selectedWindows.map { window in
            analyzeFrame(
                window.samples,
                frameIndex: window.frameIndex,
                sampleRate: audioClip.sampleRate
            )
        }

        let voicedFrames = analyzedFrames.filter { $0.isVoiced }
        let dominantPitch = aggregate(frames: voicedFrames)

        return ClipDetection(
            dominantPitch: dominantPitch,
            voicedFrameCount: voicedFrames.count,
            totalFrameCount: windows.count,
            analysisSampleRate: audioClip.sampleRate,
            frameSize: configuration.frameSize,
            hopSize: configuration.hopSize,
            frames: analyzedFrames
        )
    }

    private func makeAnalysisWindows(samples: [Float]) -> [AnalysisWindow] {
        guard samples.count >= configuration.frameSize else {
            let padded = samples + [Float](repeating: 0, count: max(0, configuration.frameSize - samples.count))
            return [
                AnalysisWindow(
                    frameIndex: 0,
                    samples: padded,
                    rms: rootMeanSquare(padded)
                )
            ]
        }

        var windows: [AnalysisWindow] = []
        var frameIndex = 0
        var start = 0
        while start + configuration.frameSize <= samples.count {
            let frame = Array(samples[start..<(start + configuration.frameSize)])
            windows.append(
                AnalysisWindow(
                    frameIndex: frameIndex,
                    samples: frame,
                    rms: rootMeanSquare(frame)
                )
            )
            start += configuration.hopSize
            frameIndex += 1
        }

        if start < samples.count {
            var padded = Array(samples[start..<samples.count])
            padded.append(contentsOf: repeatElement(0, count: configuration.frameSize - padded.count))
            windows.append(
                AnalysisWindow(
                    frameIndex: frameIndex,
                    samples: padded,
                    rms: rootMeanSquare(padded)
                )
            )
        }

        return windows
    }

    private func selectWindowsForAnalysis(_ windows: [AnalysisWindow]) -> [AnalysisWindow] {
        guard windows.count > configuration.maximumAnalyzedFrames else {
            return windows
        }

        let peakRMS = windows.map(\.rms).max() ?? 0
        let absoluteFloor = max(configuration.minimumRMS, peakRMS * configuration.relativeRMSWindowFloor)
        let gatedWindows = windows.filter { $0.rms >= absoluteFloor }
        let candidateWindows = gatedWindows.isEmpty ? windows : gatedWindows
        let strongest = candidateWindows
            .sorted { lhs, rhs in
                if lhs.rms == rhs.rms {
                    return lhs.frameIndex < rhs.frameIndex
                }
                return lhs.rms > rhs.rms
            }
            .prefix(configuration.maximumAnalyzedFrames)

        return strongest.sorted { $0.frameIndex < $1.frameIndex }
    }

    private func analyzeFrame(_ frame: [Float], frameIndex: Int, sampleRate: Double) -> DetectionFrame {
        let rms = rootMeanSquare(frame)
        let timestamp = Double(frameIndex * configuration.hopSize) / sampleRate

        guard rms >= configuration.minimumRMS else {
            return DetectionFrame(
                frameIndex: frameIndex,
                timestampSeconds: timestamp,
                frequencyHz: nil,
                confidence: 0,
                rms: rms,
                noteName: nil,
                centsOffset: nil,
                isVoiced: false
            )
        }

        let tauMin = max(2, Int(sampleRate / configuration.maximumFrequencyHz))
        let tauMax = min(frame.count / 2, Int(sampleRate / configuration.minimumFrequencyHz))
        guard tauMax > tauMin else {
            return DetectionFrame(
                frameIndex: frameIndex,
                timestampSeconds: timestamp,
                frequencyHz: nil,
                confidence: 0,
                rms: rms,
                noteName: nil,
                centsOffset: nil,
                isVoiced: false
            )
        }

        var difference = [Double](repeating: 0, count: tauMax + 1)
        for tau in tauMin...tauMax {
            var sum = 0.0
            let limit = frame.count - tau
            for index in 0..<limit {
                let delta = Double(frame[index] - frame[index + tau])
                sum += delta * delta
            }
            difference[tau] = sum
        }

        var cumulative = [Double](repeating: 1, count: tauMax + 1)
        var runningTotal = 0.0
        if tauMin > 1 {
            cumulative[0] = 1
            cumulative[1] = 1
        }
        for tau in tauMin...tauMax {
            runningTotal += difference[tau]
            cumulative[tau] = runningTotal == 0 ? 1 : (difference[tau] * Double(tau) / runningTotal)
        }

        let tau = selectTau(from: cumulative, tauMin: tauMin, tauMax: tauMax)
        let confidence = max(0, min(1, 1.0 - cumulative[tau]))
        guard confidence >= configuration.minimumConfidence else {
            return DetectionFrame(
                frameIndex: frameIndex,
                timestampSeconds: timestamp,
                frequencyHz: nil,
                confidence: confidence,
                rms: rms,
                noteName: nil,
                centsOffset: nil,
                isVoiced: false
            )
        }

        let refinedTau = parabolicInterpolation(values: cumulative, tau: tau)
        let frequency = sampleRate / refinedTau
        let note = Note.nearest(to: frequency)
        let centsOffset = Note.centsOffset(from: frequency, to: note)

        return DetectionFrame(
            frameIndex: frameIndex,
            timestampSeconds: timestamp,
            frequencyHz: frequency,
            confidence: confidence,
            rms: rms,
            noteName: note.name,
            centsOffset: centsOffset,
            isVoiced: true
        )
    }

    private func selectTau(from cumulative: [Double], tauMin: Int, tauMax: Int) -> Int {
        for tau in tauMin...tauMax {
            if cumulative[tau] < configuration.yinThreshold {
                var bestTau = tau
                while bestTau + 1 <= tauMax && cumulative[bestTau + 1] < cumulative[bestTau] {
                    bestTau += 1
                }
                return bestTau
            }
        }

        var bestTau = tauMin
        var bestValue = cumulative[tauMin]
        if tauMin < tauMax {
            for tau in (tauMin + 1)...tauMax where cumulative[tau] < bestValue {
                bestValue = cumulative[tau]
                bestTau = tau
            }
        }
        return bestTau
    }

    private func parabolicInterpolation(values: [Double], tau: Int) -> Double {
        guard tau > 1, tau + 1 < values.count else {
            return Double(tau)
        }

        let x0 = values[tau - 1]
        let x1 = values[tau]
        let x2 = values[tau + 1]
        let denominator = 2 * (2 * x1 - x2 - x0)
        guard abs(denominator) > .ulpOfOne else {
            return Double(tau)
        }
        let offset = (x2 - x0) / denominator
        return Double(tau) + offset
    }

    private func rootMeanSquare(_ frame: [Float]) -> Double {
        guard !frame.isEmpty else {
            return 0
        }
        let sumSquares = frame.reduce(0.0) { partialResult, sample in
            let value = Double(sample)
            return partialResult + value * value
        }
        return sqrt(sumSquares / Double(frame.count))
    }

    private func aggregate(frames: [DetectionFrame]) -> DetectionFrame? {
        let validFrames = frames.filter {
            $0.isVoiced && $0.frequencyHz != nil && $0.noteName != nil
        }
        guard !validFrames.isEmpty else {
            return nil
        }

        let groupedByNote = Dictionary(grouping: validFrames, by: { $0.noteName ?? "unknown" })
        let dominantGroup = groupedByNote.max { lhs, rhs in
            let lhsScore = lhs.value.reduce(0.0) { $0 + $1.confidence }
            let rhsScore = rhs.value.reduce(0.0) { $0 + $1.confidence }
            return lhsScore < rhsScore
        }?.value ?? validFrames

        let sortedFrequencies = dominantGroup.compactMap(\.frequencyHz).sorted()
        guard !sortedFrequencies.isEmpty else {
            return dominantGroup.max(by: { $0.confidence < $1.confidence })
        }
        let medianFrequency = sortedFrequencies[sortedFrequencies.count / 2]
        let note = Note.nearest(to: medianFrequency)
        let averageConfidence = dominantGroup.reduce(0.0) { $0 + $1.confidence } / Double(dominantGroup.count)
        let averageRMS = dominantGroup.reduce(0.0) { $0 + $1.rms } / Double(dominantGroup.count)
        let medianTimestamp = dominantGroup[dominantGroup.count / 2].timestampSeconds

        return DetectionFrame(
            frameIndex: dominantGroup[dominantGroup.count / 2].frameIndex,
            timestampSeconds: medianTimestamp,
            frequencyHz: medianFrequency,
            confidence: averageConfidence,
            rms: averageRMS,
            noteName: note.name,
            centsOffset: Note.centsOffset(from: medianFrequency, to: note),
            isVoiced: true
        )
    }
}
