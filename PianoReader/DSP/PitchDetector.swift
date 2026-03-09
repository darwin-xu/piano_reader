import Accelerate
import Foundation

// YIN pitch estimator with FFT-based difference function (O(N log N) instead of O(N²)).
// Uses Harmonic Product Spectrum cross-check to eliminate octave errors.
struct PitchDetector {
    // MARK: - Configuration
    private let noiseFloor: Float = 0.006          // RMS gate; piano at normal distance needs ~0.006
    private let minimumFrequency: Double = 245.0   // single visible scale: around B3/C4 lower bound
    private let maximumFrequency: Double = 700.0   // allow upper staff notes like D5 while avoiding higher-octave false matches
    private let yinThreshold: Float = 0.10         // lower = stricter; 0.10 is good for piano
    private let windowSize = 8_192                 // must be power-of-2 for FFT

    // MARK: - Public interface

    func analyze(samples: [Float], sampleRate: Double) -> DetectionResult? {
        guard samples.count >= windowSize else { return nil }

        let frame = Array(samples.suffix(windowSize))
        let amplitude = rms(frame)
        guard amplitude > noiseFloor else { return nil }

        let windowed = hanningWindow(dcRemove(frame))
        guard let (frequency, clarity) = estimateYIN(windowed, sampleRate: sampleRate) else { return nil }

        // HPS cross-check: confirm the frequency isn't an octave error
        let confirmedFrequency = harmonicProductSpectrum(windowed, sampleRate: sampleRate,
                                                          candidate: frequency)

        guard let note = PianoNote.from(frequency: confirmedFrequency) else { return nil }

        // Confidence blends: YIN clarity (inverted), amplitude, and cents accuracy
        let clarityScore  = Double(max(0, 1 - clarity))
        let ampScore      = min(Double(amplitude) / 0.08, 1.0)
        let centsPenalty  = min(abs(note.centsOffset) / 50.0, 1.0)
        let confidence    = (clarityScore * 0.55) + (ampScore * 0.30) + ((1 - centsPenalty) * 0.15)

        guard confidence >= 0.30 else { return nil }

        return DetectionResult(note: note, confidence: confidence, amplitude: amplitude)
    }

    // MARK: - Preprocessing

    private func rms(_ samples: [Float]) -> Float {
        var value: Float = 0
        vDSP_rmsqv(samples, 1, &value, vDSP_Length(samples.count))
        return value
    }

    private func dcRemove(_ samples: [Float]) -> [Float] {
        var out = samples
        var mean: Float = 0
        vDSP_meanv(out, 1, &mean, vDSP_Length(out.count))
        var neg = -mean
        vDSP_vsadd(out, 1, &neg, &out, 1, vDSP_Length(out.count))
        return out
    }

    private func hanningWindow(_ samples: [Float]) -> [Float] {
        var window = [Float](repeating: 0, count: samples.count)
        vDSP_hann_window(&window, vDSP_Length(samples.count), Int32(vDSP_HANN_NORM))
        var out = [Float](repeating: 0, count: samples.count)
        vDSP_vmul(samples, 1, window, 1, &out, 1, vDSP_Length(samples.count))
        return out
    }

    // MARK: - YIN with FFT-based difference function

    private func estimateYIN(_ samples: [Float], sampleRate: Double) -> (frequency: Double, clarity: Float)? {
        let N = samples.count
        let minLag = max(2, Int(sampleRate / maximumFrequency))
        let maxLag = min(N / 2 - 1, Int(sampleRate / minimumFrequency))
        guard minLag < maxLag else { return nil }

        // Compute difference function via FFT-based autocorrelation:
        //   d(τ) = r(0) + r(0) - 2·r(τ)   where r is the autocorrelation
        let autocorr = fftAutocorrelation(samples)
        let r0 = autocorr[0]
        var diff = [Float](repeating: 0, count: maxLag + 1)
        for lag in 1...maxLag {
            diff[lag] = max(0, (r0 + r0) - 2 * autocorr[lag])
        }

        // Cumulative Mean Normalised Difference Function (CMNDF)
        var cmndf = [Float](repeating: 1, count: maxLag + 1)
        var cumSum: Float = 0
        for lag in 1...maxLag {
            cumSum += diff[lag]
            cmndf[lag] = cumSum == 0 ? 1 : diff[lag] * Float(lag) / cumSum
        }

        guard let bestIndex = pickLag(cmndf, minLag: minLag, maxLag: maxLag) else { return nil }
        let refined = parabolicInterpolate(cmndf, index: bestIndex)
        let frequency = sampleRate / refined
        guard frequency >= minimumFrequency, frequency <= maximumFrequency else { return nil }

        return (frequency, cmndf[bestIndex])
    }

    /// Power-of-2 FFT autocorrelation.  Returns unnormalised r[τ] for τ = 0…N-1.
    private func fftAutocorrelation(_ samples: [Float]) -> [Float] {
        let N = samples.count
        let fftN = N * 2                // zero-pad to 2N to avoid circular aliasing
        let log2n = vDSP_Length(log2(Float(fftN)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: N)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        // Pack real signal into split-complex
        var realp = [Float](repeating: 0, count: fftN / 2)
        var imagp = [Float](repeating: 0, count: fftN / 2)
        realp.withUnsafeMutableBufferPointer { rBuf in
            imagp.withUnsafeMutableBufferPointer { iBuf in
                var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                let inputCopy = samples + [Float](repeating: 0, count: N) // zero-pad
                inputCopy.withUnsafeBytes { rawBytes in
                    let floatPtr = rawBytes.bindMemory(to: Float.self).baseAddress!
                    vDSP_ctoz(UnsafePointer<DSPComplex>(OpaquePointer(floatPtr)),
                              2, &split, 1, vDSP_Length(fftN / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // Power spectrum: |X|²
                vDSP_zvmags(&split, 1, rBuf.baseAddress!, 1, vDSP_Length(fftN / 2))
                // Zero the imaginary; we're working with real power spectrum
                vDSP_vclr(iBuf.baseAddress!, 1, vDSP_Length(fftN / 2))
                // Inverse FFT to get autocorrelation
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                // Unpack
                var output = [Float](repeating: 0, count: fftN)
                output.withUnsafeMutableBytes { rawOut in
                    let floatOut = rawOut.bindMemory(to: Float.self).baseAddress!
                    vDSP_ztoc(&split, 1,
                              UnsafeMutablePointer<DSPComplex>(OpaquePointer(floatOut)),
                              2, vDSP_Length(fftN / 2))
                }
                // Normalise by fftN
                var scale = 1.0 / Float(fftN)
                vDSP_vsmul(output, 1, &scale, &output, 1, vDSP_Length(N))
                // Copy first N samples back into realp for return
                for i in 0..<N { rBuf[i] = output[i] }
            }
        }
        return realp
    }

    private func pickLag(_ cmndf: [Float], minLag: Int, maxLag: Int) -> Int? {
        var lag = minLag
        while lag <= maxLag {
            if cmndf[lag] < yinThreshold {
                // Move to local minimum
                while lag + 1 <= maxLag, cmndf[lag + 1] < cmndf[lag] { lag += 1 }
                return lag
            }
            lag += 1
        }
        // Fallback: global minimum below a relaxed threshold
        let slice = cmndf[minLag...maxLag]
        guard let minVal = slice.min(), minVal < 0.20 else { return nil }
        return cmndf.firstIndex(of: minVal)
    }

    private func parabolicInterpolate(_ values: [Float], index: Int) -> Double {
        guard index > 0, index + 1 < values.count else { return Double(index) }
        let l = Double(values[index - 1])
        let c = Double(values[index])
        let r = Double(values[index + 1])
        let denom = l - 2 * c + r
        guard abs(denom) > .ulpOfOne else { return Double(index) }
        return Double(index) + 0.5 * (l - r) / denom
    }

    // MARK: - Harmonic Product Spectrum (octave error guard)

    /// Given a YIN candidate, computes HPS over a short FFT magnitude spectrum to find the
    /// most likely fundamental. If HPS agrees within a minor-third (3 semitones) of the
    /// YIN candidate (or its octave), we keep the HPS result; otherwise falls back to YIN.
    private func harmonicProductSpectrum(_ samples: [Float], sampleRate: Double, candidate: Double) -> Double {
        let N = samples.count
        let log2n = vDSP_Length(log2(Float(N)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return candidate }
        defer { vDSP_destroy_fftsetup(setup) }

        var realp = [Float](repeating: 0, count: N / 2)
        var imagp = [Float](repeating: 0, count: N / 2)
        var magnitudes = [Float](repeating: 0, count: N / 2)

        realp.withUnsafeMutableBufferPointer { rBuf in
            imagp.withUnsafeMutableBufferPointer { iBuf in
                var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                let inputCopy = samples
                inputCopy.withUnsafeBytes { rawBytes in
                    let floatPtr = rawBytes.bindMemory(to: Float.self).baseAddress!
                    vDSP_ctoz(UnsafePointer<DSPComplex>(OpaquePointer(floatPtr)),
                              2, &split, 1, vDSP_Length(N / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(N / 2))
            }
        }

        // Apply HPS: multiply magnitude spectrum downsampled by 2 and 3
        let halfLen = N / 6   // safe region for 3 harmonics
        var hps = Array(magnitudes[0..<halfLen])
        for (i, _) in hps.enumerated() {
            if 2 * i < magnitudes.count { hps[i] *= magnitudes[2 * i] }
            if 3 * i < magnitudes.count { hps[i] *= magnitudes[3 * i] }
        }

        let binHz = sampleRate / Double(N)
        let minBin = max(1, Int(minimumFrequency / binHz))
        let maxBin = min(halfLen - 1, Int(maximumFrequency / binHz))
        guard minBin < maxBin else { return candidate }

        let searchSlice = hps[minBin...maxBin]
        guard let peakVal = searchSlice.max(), peakVal > 0,
              let peakBin = hps.firstIndex(of: peakVal) else { return candidate }

        let hpsFrequency = Double(peakBin) * binHz

        // Accept HPS if it's within 3 semitones of the YIN candidate (or its octave)
        func semitoneDist(_ a: Double, _ b: Double) -> Double {
            guard a > 0, b > 0 else { return 100 }
            return abs(12 * log2(a / b))
        }

        let distDirect = semitoneDist(hpsFrequency, candidate)
        let distOctaveUp = semitoneDist(hpsFrequency, candidate * 2)
        let distOctaveDown = semitoneDist(hpsFrequency, candidate / 2)

        if distDirect <= 3 { return candidate }           // YIN was right
        if distOctaveUp <= 3 { return candidate * 2 }    // YIN was an octave too low
        if distOctaveDown <= 3 { return candidate / 2 }  // YIN was an octave too high
        return candidate                                  // unclear; keep YIN
    }
}