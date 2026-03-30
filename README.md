# PianoReader

Real-time piano pitch detection for iOS, built with Swift. Recognises single notes and chords from live audio or audio files using a two-stage detector:

1. **HarmonicSalienceDetector** — FFT-based harmonic salience across frames; handles polyphonic detection.
2. **YINPitchDetector** — time-domain autocorrelation for accurate monophonic pitch and cents estimation.

---

## Project structure

```
PianoReader/          iOS app (SwiftUI)
  Audio/              Live microphone capture
  DSP/                Core detection algorithms (also used by CLI)
  Models/             Data types (KeyboardLayout, PianoNote)
  ViewModels/         RecognitionViewModel
  Views/              PianoKeyboardView, StaffNoteView, WaveformEnvelopeView

Sources/
  PitchDetectCLI/     Command-line evaluation tool

Samples/
  note_sample/        Single-note WAV recordings (A#4_1.wav, C4_2.wav, …)
  note_sample_chord/  Chord WAV recordings (C_E_1.wav, D_minor_chord_1.wav, …)
  noise_sample/       Ambient noise recordings (noise-1.m4a, …)

evaluation/results/   JSON output from the last evaluation run
```

---

## Running the evaluation

All commands are run from the **repository root**.

### Full evaluation (recommended)

```bash
swift run PitchDetectCLI
```

Auto-discovers all three sample directories under `Samples/` and runs all four evaluation suites:

| Suite | Output file |
|---|---|
| === Single-Note Evaluation === | `evaluation/results/single-note-results.json` |
| === Chord Evaluation === | `evaluation/results/chord-results.json` |
| === Pure Noise Evaluation === | `evaluation/results/noise-results.json` |
| === Noise-Mix SNR Table === | `evaluation/results/noise-mix-results.json` |

`evaluation/results/latest-results.json` is also updated with the single-note summary.

### Single directory (derives siblings automatically)

```bash
swift run PitchDetectCLI Samples/note_sample
```

Passing any path inside `Samples/` uses its parent as the base, so chord and noise directories are still discovered and all four suites run. This is equivalent to the no-argument form when the directory layout matches the default.

### Sample output

```
=== Single-Note Evaluation ===
Samples: 30
Evaluated: 30/30
Accuracy: 100.00%
Mean absolute cents error: 7.58
  ✓ A#4_1.wav: expected=single:A#4 detected=[A#4]
  …

=== Chord Evaluation ===
Samples: 136
Mean Precision: 94.12%
Mean Recall:    91.18%
Mean F1:        92.63%
Fully correct:  128/136
  ✓ C_E_1.wav: expected=[C, E] detected=[C, E] P=100% R=100%
  …

=== Pure Noise Evaluation ===
Samples: 2
False positives: 0
FP rate: 0.00%
  ✓ noise-1.m4a: detected=[none]
  ✓ noise-2.m4a: detected=[none]

=== Noise-Mix SNR Table ===
SNR dB    Single-note Acc     Chord Recall        Tests
-10       100.0%              91.4%               166
-5        100.0%              91.7%               166
0         100.0%              92.0%               166
5         100.0%              92.5%               166
10        100.0%              93.4%               166
```

---

## Adding new samples

File names encode the ground truth:

| Pattern | Meaning |
|---|---|
| `A#4_1.wav` | Single note A#4, take 1 |
| `C_E_2.wav` | Dyad C + E, take 2 |
| `C_major_chord_1.wav` | Named chord (C, E, G), take 1 |
| `D_minor_chord_1.wav` | Named chord (D, F, A), take 1 |
| `noise-1.m4a` | Ambient noise (no expected note) |

Supported audio formats: `.wav`, `.m4a`, `.aac`, `.mp3`.

---

## Audio asset tracking (Git LFS)

WAV and M4A files are tracked with **Git LFS** (`.gitattributes`). Make sure Git LFS is installed before cloning:

```bash
git lfs install
```
