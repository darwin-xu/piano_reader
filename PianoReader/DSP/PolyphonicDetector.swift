import Accelerate
import Foundation

/// FFT-based polyphonic pitch detector.
/// Builds a chromatic energy spectrum from FFT magnitudes, picks prominent peaks,
/// and uses harmonic-relationship analysis to separate fundamentals from overtones.
struct PolyphonicDetector {
    private let windowSize = 8_192
    private let noiseFloor: Float = 0.012           // raised — reject quiet ambient
    private let maxNotes = 6
    private let peakThresholdRatio: Float = 0.18    // fraction of max chromatic energy to qualify as a peak
    private let harmonicTolerance: Double = 0.8     // semitone tolerance for harmonic matching
    private let spectralFlatnessLimit: Float = 0.25 // above this the signal is noise-like; reject
    private let minHarmonicsPresent = 2             // candidate must have ≥2 of first 4 harmonics

    // Harmonic intervals in semitones (harmonics 2–8 above a fundamental):
    //   h2 = 12.00,  h3 = 19.02,  h4 = 24.00,  h5 = 27.86,
    //   h6 = 31.02,  h7 = 33.69,  h8 = 36.00
    private let harmonicSemitones: [Double] = [12.0, 19.02, 24.0, 27.86, 31.02, 33.69, 36.0]

    // MARK: - Public

    func analyze(samples: [Float], sampleRate: Double) -> [DetectionResult] {
        guard samples.count >= windowSize else { return [] }

        let frame = Array(samples.suffix(windowSize))
        let amplitude = rms(frame)
        guard amplitude > noiseFloor else { return [] }

        let windowed = hanningWindow(dcRemove(frame))
        let magnitudes = fftMagnitudes(windowed)
        let binHz = sampleRate / Double(windowSize)

        // Reject broadband noise: spectral flatness close to 1.0 means uniform energy (noise).
        let flatness = spectralFlatness(magnitudes)
        guard flatness < spectralFlatnessLimit else { return [] }

        let chromatic = buildChromaticSpectrum(magnitudes: magnitudes, binHz: binHz)
        let candidates = findCandidateNotes(chromatic)
        let fundamentals = suppressHarmonics(candidates)

        // Validate each candidate has real harmonic partials (piano-like tone)
        let validated = fundamentals.filter { verifyHarmonicity(midi: $0.midi, magnitudes: magnitudes, binHz: binHz) }

        var results: [DetectionResult] = []
        let maxChrom = chromatic.max() ?? 1
        for (midi, magnitude) in validated.prefix(maxNotes) {
            let freq = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
            guard let note = PianoNote.from(frequency: freq) else { continue }
            let magScore = min(Double(magnitude) / Double(maxChrom), 1.0)
            let ampScore = min(Double(amplitude) / 0.08, 1.0)
            let confidence = magScore * 0.6 + ampScore * 0.4
            guard confidence >= 0.35 else { continue }
            results.append(DetectionResult(note: note, confidence: confidence, amplitude: amplitude))
        }
        return results
    }

    // MARK: - Spectral flatness (noise rejection)

    /// Geometric mean / arithmetic mean of magnitude spectrum.
    /// Values near 1.0 = white noise; near 0.0 = tonal (peaked).
    private func spectralFlatness(_ magnitudes: [Float]) -> Float {
        let N = magnitudes.count
        guard N > 0 else { return 1 }
        // Work in log domain for geometric mean to avoid underflow
        var logSum: Double = 0
        var linSum: Double = 0
        var count = 0
        for m in magnitudes where m > 0 {
            logSum += Double(log(m))
            linSum += Double(m)
            count += 1
        }
        guard count > 0, linSum > 0 else { return 1 }
        let logGeoMean = logSum / Double(count)
        let geoMean = exp(logGeoMean)
        let ariMean = linSum / Double(count)
        return Float(geoMean / ariMean)
    }

    // MARK: - Harmonicity validation

    /// Checks that a candidate fundamental has clear harmonic partials at integer
    /// multiples (2×, 3×, 4×, 5×). Real piano tones always have these;
    /// speech, clicks, and environmental noise generally don't.
    private func verifyHarmonicity(midi: Int, magnitudes: [Float], binHz: Double) -> Bool {
        let f0 = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        let f0Bin = Int(f0 / binHz)
        guard f0Bin > 0, f0Bin < magnitudes.count else { return false }
        let f0Mag = magnitudes[f0Bin]
        guard f0Mag > 0 else { return false }

        // Compute local median (noise floor estimate) over a wide band
        let bandLo = max(0, f0Bin - 100)
        let bandHi = min(magnitudes.count - 1, f0Bin + 100)
        let sorted = Array(magnitudes[bandLo...bandHi]).sorted()
        let medianNoise = sorted[sorted.count / 2]

        var harmonicsFound = 0
        for h in 2...5 {
            let hBin = Int(Double(f0Bin) * Double(h))
            let win = max(1, Int(Double(hBin) * 0.015))
            let lo = max(0, hBin - win)
            let hi = min(magnitudes.count - 1, hBin + win)
            guard lo <= hi else { continue }
            let peakMag = magnitudes[lo...hi].max() ?? 0
            // Harmonic must be clearly above the local noise floor
            if peakMag > medianNoise * 3.0 {
                harmonicsFound += 1
            }
        }
        return harmonicsFound >= minHarmonicsPresent
    }

    // MARK: - Preprocessing

    private func rms(_ buf: [Float]) -> Float {
        var v: Float = 0
        vDSP_rmsqv(buf, 1, &v, vDSP_Length(buf.count))
        return v
    }

    private func dcRemove(_ buf: [Float]) -> [Float] {
        var out = buf
        var mean: Float = 0
        vDSP_meanv(out, 1, &mean, vDSP_Length(out.count))
        var neg = -mean
        vDSP_vsadd(out, 1, &neg, &out, 1, vDSP_Length(out.count))
        return out
    }

    private func hanningWindow(_ buf: [Float]) -> [Float] {
        var win = [Float](repeating: 0, count: buf.count)
        vDSP_hann_window(&win, vDSP_Length(buf.count), Int32(vDSP_HANN_NORM))
        var out = [Float](repeating: 0, count: buf.count)
        vDSP_vmul(buf, 1, win, 1, &out, 1, vDSP_Length(buf.count))
        return out
    }

    // MARK: - FFT

    private func fftMagnitudes(_ samples: [Float]) -> [Float] {
        let N = samples.count
        let log2n = vDSP_Length(log2(Float(N)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        var realp = [Float](repeating: 0, count: N / 2)
        var imagp = [Float](repeating: 0, count: N / 2)

        realp.withUnsafeMutableBufferPointer { rBuf in
            imagp.withUnsafeMutableBufferPointer { iBuf in
                var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                samples.withUnsafeBytes { raw in
                    let ptr = raw.bindMemory(to: Float.self).baseAddress!
                    vDSP_ctoz(UnsafePointer<DSPComplex>(OpaquePointer(ptr)),
                              2, &split, 1, vDSP_Length(N / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, rBuf.baseAddress!, 1, vDSP_Length(N / 2))
            }
        }

        // realp now holds squared magnitudes — take sqrt
        var mags = realp
        var count = Int32(mags.count)
        vvsqrtf(&mags, realp, &count)
        return mags
    }

    // MARK: - Chromatic spectrum

    /// Maps FFT bins → per-MIDI-note energy (MIDI 21–108, index 0 = MIDI 21).
    private func buildChromaticSpectrum(magnitudes: [Float], binHz: Double) -> [Float] {
        var spectrum = [Float](repeating: 0, count: 88)
        for midi in 21...108 {
            let freq = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
            let center = Int(freq / binHz)
            let win = max(1, Int(Double(center) * 0.02))
            let lo = max(0, center - win)
            let hi = min(magnitudes.count - 1, center + win)
            guard lo <= hi else { continue }
            spectrum[midi - 21] = magnitudes[lo...hi].max() ?? 0
        }
        return spectrum
    }

    // MARK: - Peak picking

    private func findCandidateNotes(_ spectrum: [Float]) -> [(midi: Int, mag: Float)] {
        guard let peak = spectrum.max(), peak > 0 else { return [] }
        let threshold = peak * peakThresholdRatio

        var out: [(midi: Int, mag: Float)] = []
        for i in 1..<(spectrum.count - 1) {
            if spectrum[i] > spectrum[i - 1],
               spectrum[i] > spectrum[i + 1],
               spectrum[i] > threshold {
                out.append((midi: i + 21, mag: spectrum[i]))
            }
        }
        // Edges
        if spectrum.count > 1 {
            if spectrum[0] > spectrum[1], spectrum[0] > threshold {
                out.append((midi: 21, mag: spectrum[0]))
            }
            let last = spectrum.count - 1
            if spectrum[last] > spectrum[last - 1], spectrum[last] > threshold {
                out.append((midi: 108, mag: spectrum[last]))
            }
        }
        return out.sorted { $0.mag > $1.mag }      // strongest first
    }

    // MARK: - Harmonic suppression

    /// Removes peaks that are likely overtones of stronger, lower-frequency peaks.
    private func suppressHarmonics(_ candidates: [(midi: Int, mag: Float)]) -> [(midi: Int, mag: Float)] {
        var result: [(midi: Int, mag: Float)] = []

        for cand in candidates {
            var explained = false
            for lower in candidates {
                guard lower.midi < cand.midi else { continue }
                let delta = Double(cand.midi - lower.midi)
                for (i, hs) in harmonicSemitones.enumerated() {
                    guard abs(delta - hs) < harmonicTolerance else { continue }
                    // Expected decay: magnitude of harmonic n ≈ fundamental / n
                    let harmonicNumber = i + 2
                    let expectedRatio: Float = 1.0 / Float(harmonicNumber)
                    let actualRatio = cand.mag / max(lower.mag, 0.001)
                    if actualRatio < expectedRatio * 2.5 {
                        explained = true
                        break
                    }
                }
                if explained { break }
            }
            if !explained { result.append(cand) }
        }
        return result.sorted { $0.midi < $1.midi }
    }
}
