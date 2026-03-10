import SwiftUI

// Treble clef staff reference (diatonic steps from C4 = step 0):
//   Step 0  = C4  (ledger line below staff)
//   Step 1  = D4  (space below bottom line)
//   Step 2  = E4  (bottom line,    line 1)
//   Step 3  = F4  (1st space)
//   Step 4  = G4  (2nd line)
//   Step 5  = A4  (2nd space)
//   Step 6  = B4  (3rd / middle line)
//   Step 7  = C5  (3rd space)
//   Step 8  = D5  (4th line)
//   Step 9  = E5  (4th space)
//   Step 10 = F5  (top line,       line 5)
// Staff lines are at steps 2, 4, 6, 8, 10. Each step is one diatonic position.

struct StaffNoteView: View {
    let note: PianoNote?

    // Chromatic pitch class (0–11) → diatonic step within one octave (0–6).
    // Accidentals share the same step as their natural.
    private static let pitchClassStep: [Int] = [
        0,  // C
        0,  // C#
        1,  // D
        1,  // D#
        2,  // E
        3,  // F
        3,  // F#
        4,  // G
        4,  // G#
        5,  // A
        5,  // A#
        6,  // B
    ]

    private func diatonicStep(for midiNumber: Int) -> Int {
        let delta     = midiNumber - 60
        let octaves   = delta >= 0 ? delta / 12 : (delta - 11) / 12
        let pitchClass = ((delta % 12) + 12) % 12
        return octaves * 7 + Self.pitchClassStep[pitchClass]
    }

    // Y position on screen: step 10 (F5) is near top, step 0 (C4) is near bottom (below staff).
    private func staffY(step: Int, top: CGFloat, stepSize: CGFloat) -> CGFloat {
        top + CGFloat(10 - step) * stepSize
    }

    var body: some View {
        GeometryReader { geo in
            StaffCanvas(note: note,
                        diatonicStep: note.map { diatonicStep(for: $0.midiNumber) })
        }
    }
}

/// Pure-draw helper so all geometry calculations happen outside @ViewBuilder.
private struct StaffCanvas: View {
    let note: PianoNote?
    let diatonicStep: Int?

    private func yFor(step: Int, top: CGFloat, stepSize: CGFloat) -> CGFloat {
        top + CGFloat(10 - step) * stepSize
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let topPad: CGFloat = 52
            let bottomPad: CGFloat = 72
            let staffTop: CGFloat = topPad
            // Steps 2…10 = 8 intervals occupy the staff zone
            let stepSize: CGFloat = (h - topPad - bottomPad) / 8.0
            let lineGap: CGFloat = stepSize * 2
            let noteHeadHeight: CGFloat = lineGap
            let noteHeadWidth: CGFloat = lineGap * 1.35

            ZStack {
                Color.white

                // 5 staff lines at diatonic steps 2, 4, 6, 8, 10
                ForEach([2, 4, 6, 8, 10], id: \.self) { step in
                    Rectangle()
                        .fill(Color.black.opacity(0.72))
                        .frame(height: 1.2)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                        .position(x: w / 2, y: yFor(step: step, top: staffTop, stepSize: stepSize))
                }

                Text("𝄞")
                    .font(.system(size: h * 0.95))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .position(x: w * 0.17, y: h * 0.52)

                if let note, let step = diatonicStep {
                    let noteX = w * 0.56
                    let noteY = yFor(step: step, top: staffTop, stepSize: stepSize)

                    // Ledger line for middle C (step 0) or D4 below staff (step 1)
                    if step <= 1 {
                        Rectangle()
                            .fill(Color.black.opacity(0.60))
                            .frame(width: 36, height: 1.5)
                            .position(x: noteX, y: yFor(step: 0, top: staffTop, stepSize: stepSize))
                    }

                    // Stem (upward)
                    Rectangle()
                        .fill(Color(red: 0.13, green: 0.18, blue: 0.27))
                        .frame(width: 2.2, height: lineGap * 2.2)
                        .position(x: noteX + (noteHeadWidth * 0.43), y: noteY - lineGap * 1.1)

                    // Note head
                    Ellipse()
                        .fill(Color(red: 0.13, green: 0.18, blue: 0.27))
                        .frame(width: noteHeadWidth, height: noteHeadHeight)
                        .rotationEffect(.degrees(-10))
                        .position(x: noteX, y: noteY)

                    // Note label (top-left)
                    Text(note.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .position(x: w * 0.16, y: 24)
                } else {
                    Text("Current note on staff")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}