import Accelerate
import Foundation

public struct HarmonicSalienceConfiguration: Sendable {
    public let frameSize: Int
    public let hopFraction: Double
    public let nHarmonics: Int
    public let midiLow: Int
    public let midiHigh: Int
    public let salienceThresholdRatio: Double
    public let maxNotes: Int
    public let minimumRMS: Double
    /// Semitone intervals for aggressive ghost suppression (non-chord
    /// harmonics that almost never appear as real chord intervals).
    /// 5/3→9  2/1→12  5/2→16  3/1→19  4/1→24  5/1→28
    public let suppressIntervals: [Int]
    /// Strength threshold for distant-interval suppression.
    public let suppressStrength: Double
    /// Semitone intervals that also appear as common chord intervals.
    /// 5/4→4  4/3→5  3/2→7 — uses a higher threshold so real chord tones
    /// (whose salience is comparable) survive while single-note ghosts
    /// (whose salience is much weaker) are still removed.
    public let chordSuppressIntervals: [Int]
    /// Strength threshold for chord-interval suppression (higher = more
    /// conservative).
    public let chordSuppressStrength: Double
    /// Minimum ratio of peak salience to median salience across all MIDI
    /// candidates.  Signals with a flat spectrum (noise) have a ratio near 1
    /// and are rejected.
    public let peakProminenceRatio: Double

    public init(
        frameSize: Int = 16384,
        hopFraction: Double = 0.5,
        nHarmonics: Int = 5,
        midiLow: Int = 28,
        midiHigh: Int = 108,
        salienceThresholdRatio: Double = 0.15,
        maxNotes: Int = 6,
        minimumRMS: Double = 0.005,
        suppressIntervals: [Int] = [9, 12, 16, 19, 24, 28],
        suppressStrength: Double = 2.0,
        chordSuppressIntervals: [Int] = [4, 5, 7],
        chordSuppressStrength: Double = 3.0,
        peakProminenceRatio: Double = 3.0
    ) {
        self.frameSize = frameSize
        self.hopFraction = hopFraction
        self.nHarmonics = nHarmonics
        self.midiLow = midiLow
        self.midiHigh = midiHigh
        self.salienceThresholdRatio = salienceThresholdRatio
        self.maxNotes = maxNotes
        self.minimumRMS = minimumRMS
        self.suppressIntervals = suppressIntervals
        self.suppressStrength = suppressStrength
        self.chordSuppressIntervals = chordSuppressIntervals
        self.chordSuppressStrength = chordSuppressStrength
        self.peakProminenceRatio = peakProminenceRatio
    }
}

public struct HarmonicSalienceDetector: MultiPitchDetector {
    public let configuration: HarmonicSalienceConfiguration

    public init(configuration: HarmonicSalienceConfiguration = HarmonicSalienceConfiguration()) {
        self.configuration = configuration
    }

    public func analyzeMulti(audioClip: AudioClip) throws -> MultiPitchClipDetection {
        let samples = audioClip.samples
        let sampleRate = audioClip.sampleRate
        let frameSize = configuration.frameSize
        let hopSize = max(1, Int(Double(frameSize) * configuration.hopFraction))
        let nyquist = sampleRate / 2.0

        // FFT setup
        let log2n = vDSP_Length(log2(Double(frameSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return MultiPitchClipDetection(detectedNotes: [], frameCount: 0, sampleRate: sampleRate)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Pre-compute Hann window
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))

        let halfN = frameSize / 2
        let midiRange = configuration.midiLow...configuration.midiHigh
        var accumulatedSalience = [Double](repeating: 0, count: 128)

        // Process frames
        var frameCount = 0
        var start = 0
        while start + frameSize <= samples.count {
            let frame = Array(samples[start..<(start + frameSize)])

            // RMS gate
            var rms: Float = 0
            vDSP_rmsqv(frame, 1, &rms, vDSP_Length(frameSize))
            guard Double(rms) >= configuration.minimumRMS else {
                start += hopSize
                frameCount += 1
                continue
            }

            // Apply window
            var windowed = [Float](repeating: 0, count: frameSize)
            vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(frameSize))

            // Pack into split complex
            var realp = [Float](repeating: 0, count: halfN)
            var imagp = [Float](repeating: 0, count: halfN)
            realp.withUnsafeMutableBufferPointer { rBuf in
                imagp.withUnsafeMutableBufferPointer { iBuf in
                    var splitComplex = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                    windowed.withUnsafeBufferPointer { src in
                        src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                        }
                    }
                    // FFT
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                    // Magnitude spectrum
                    var magnitudes = [Float](repeating: 0, count: halfN)
                    vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

                    // Normalize
                    var scale = Float(1.0 / Double(frameSize))
                    vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfN))

                    // Compute salience for each MIDI pitch
                    let binResolution = sampleRate / Double(frameSize)
                    for midi in midiRange {
                        let f0 = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
                        var salience = 0.0
                        for h in 1...self.configuration.nHarmonics {
                            let harmonicFreq = f0 * Double(h)
                            guard harmonicFreq < nyquist else { break }
                            let bin = Int(round(harmonicFreq / binResolution))
                            guard bin >= 0, bin < halfN else { continue }
                            salience += Double(magnitudes[bin]) / Double(h)
                        }
                        // Keep max across frames
                        if salience > accumulatedSalience[midi] {
                            accumulatedSalience[midi] = salience
                        }
                    }
                }
            }

            start += hopSize
            frameCount += 1
        }

        // Handle short clips (< 1 frame)
        if frameCount == 0 && !samples.isEmpty {
            var padded = samples
            padded.append(contentsOf: repeatElement(Float(0), count: max(0, frameSize - samples.count)))
            let shortClip = AudioClip(fileURL: audioClip.fileURL, samples: padded, sampleRate: sampleRate)
            return try analyzeMulti(audioClip: shortClip)
        }

        // Peak picking on accumulated salience
        var peaks: [(midi: Int, salience: Double)] = []
        let peakSalience = accumulatedSalience[midiRange].max() ?? 0
        let threshold = peakSalience * configuration.salienceThresholdRatio

        guard peakSalience > 0 else {
            return MultiPitchClipDetection(detectedNotes: [], frameCount: frameCount, sampleRate: sampleRate)
        }

        // Peak prominence check: reject flat-spectrum signals (noise)
        let sortedSaliences = midiRange.map({ accumulatedSalience[$0] }).sorted()
        let medianSalience = sortedSaliences[sortedSaliences.count / 2]
        if medianSalience > 0,
           peakSalience / medianSalience < configuration.peakProminenceRatio {
            return MultiPitchClipDetection(detectedNotes: [], frameCount: frameCount, sampleRate: sampleRate)
        }

        for midi in midiRange {
            let s = accumulatedSalience[midi]
            guard s >= threshold else { continue }
            // Local maximum: must be greater than both neighbors
            let left = midi > midiRange.lowerBound ? accumulatedSalience[midi - 1] : 0
            let right = midi < midiRange.upperBound ? accumulatedSalience[midi + 1] : 0
            if s >= left && s >= right {
                peaks.append((midi: midi, salience: s))
            }
        }

        // Two-tier harmonic suppression.
        var suppressed = Set<Int>()
        let distantSet = Set(configuration.suppressIntervals)
        let chordSet   = Set(configuration.chordSuppressIntervals)
        for i in 0..<peaks.count {
            guard !suppressed.contains(peaks[i].midi) else { continue }
            for j in (i + 1)..<peaks.count {
                guard !suppressed.contains(peaks[j].midi) else { continue }
                let interval = abs(peaks[i].midi - peaks[j].midi)
                let strength: Double
                if distantSet.contains(interval) {
                    strength = configuration.suppressStrength
                } else if chordSet.contains(interval) {
                    strength = configuration.chordSuppressStrength
                } else {
                    continue
                }
                if peaks[i].salience > peaks[j].salience * strength {
                    suppressed.insert(peaks[j].midi)
                } else if peaks[j].salience > peaks[i].salience * strength {
                    suppressed.insert(peaks[i].midi)
                }
            }
        }

        let finalPeaks = peaks
            .filter { !suppressed.contains($0.midi) }
            .sorted { $0.salience > $1.salience }
            .prefix(configuration.maxNotes)
            .sorted { $0.midi < $1.midi }

        let detectedNotes = finalPeaks.map { peak in
            let note = Note(midi: peak.midi)
            return DetectedNote(
                midi: peak.midi,
                name: note.name,
                pitchClass: note.pitchClass,
                frequencyHz: note.frequencyHz,
                salience: peak.salience
            )
        }

        return MultiPitchClipDetection(
            detectedNotes: detectedNotes,
            frameCount: frameCount,
            sampleRate: sampleRate
        )
    }
}
