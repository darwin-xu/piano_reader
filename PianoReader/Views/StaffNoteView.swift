import CoreText
import SwiftUI
import UIKit

// Grand staff reference using diatonic steps relative to middle C (C4 = step 0).
// Treble lines:  E4 G4 B4 D5 F5  -> steps 2, 4, 6, 8, 10
// Bass lines:    G2 B2 D3 F3 A3  -> steps -10, -8, -6, -4, -2
// Middle C sits between the staves on ledger line step 0.

struct StaffNoteView: View {
    let notes: [PianoNote]

    // Chromatic pitch class (0-11) to diatonic step within one octave.
    // Accidentals share the same diatonic position as their natural note.
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
        let delta = midiNumber - 60
        let octaves = delta >= 0 ? delta / 12 : (delta - 11) / 12
        let pitchClass = ((delta % 12) + 12) % 12
        return octaves * 7 + Self.pitchClassStep[pitchClass]
    }

    var body: some View {
        let pairs = notes.map { (note: $0, step: diatonicStep(for: $0.midiNumber)) }
        StaffCanvas(notes: notes, diatonicSteps: pairs.map(\.step))
    }
}

private struct StaffCanvas: View {
    let notes: [PianoNote]
    let diatonicSteps: [Int]

    private let trebleLineSteps = [2, 4, 6, 8, 10]
    private let bassLineSteps = [-10, -8, -6, -4, -2]

    private func yFor(step: Int, top: CGFloat, stepSize: CGFloat) -> CGFloat {
        top + CGFloat(12 - step) * stepSize
    }

    private func ledgerSteps(for step: Int) -> [Int] {
        if step == 0 {
            return [0]
        }

        if step > 10 {
            let highestLine = step.isMultiple(of: 2) ? step : step - 1
            return Array(stride(from: 12, through: highestLine, by: 2))
        }

        if step < -10 {
            let lowestLine = step.isMultiple(of: 2) ? step : step + 1
            return Array(stride(from: -12, through: lowestLine, by: -2))
        }

        return []
    }

    private func stemDirection(for step: Int) -> CGFloat {
        step >= 0 ? -1 : 1
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let topPad: CGFloat = 34
            let bottomPad: CGFloat = 34
            let usableHeight = max(height - topPad - bottomPad, 120)
            let stepSize = usableHeight / 24
            let lineGap = stepSize * 2
            let noteHeadHeight = lineGap * 0.96
            let noteHeadWidth = lineGap * 1.35
            let noteCount = notes.count
            let labelY: CGFloat = 22
            let smuflBrace = String(UnicodeScalar(0xE000)!)
            let trebleTopY = yFor(step: 10, top: topPad, stepSize: stepSize)
            let bassBottomY = yFor(step: -10, top: topPad, stepSize: stepSize)
            let braceCenterY = (trebleTopY + bassBottomY) / 2
            let braceSpan = bassBottomY - trebleTopY
            let braceBaseSize = lineGap * 10
            let braceVerticalScale = max(braceSpan / (braceBaseSize * 1.45), 1)
            let braceFont = UIFont(name: "Bravura", size: braceBaseSize) ?? .systemFont(ofSize: braceBaseSize)
            let trebleClefFont = UIFont.systemFont(ofSize: lineGap * 7.7)
            let bassClefFont = UIFont.systemFont(ofSize: lineGap * 4.3)
            let barLineX = width * 0.10
            let braceX = width * 0.07
            let staffStartX = barLineX
            let _ = Self.logBraceMetrics(
                braceCenterY: braceCenterY,
                trebleTopY: trebleTopY,
                bassBottomY: bassBottomY,
                height: height,
                topPad: topPad,
                bottomPad: bottomPad,
                stepSize: stepSize
            )

            ZStack {
                Color.white

                Text(smuflBrace)
                    .font(.custom("Bravura", size: braceBaseSize))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .scaleEffect(x: 1.0, y: braceVerticalScale, anchor: .center)
                    .overlay(
                        GlyphDebugBox(
                            text: smuflBrace,
                            font: braceFont,
                            color: .red,
                            scaleY: braceVerticalScale
                        )
                    )
                    .position(x: braceX, y: bassBottomY)

                Rectangle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 2.2, height: braceSpan)
                    .position(x: barLineX, y: braceCenterY)

                ForEach(trebleLineSteps, id: \.self) { step in
                    staffLine(at: yFor(step: step, top: topPad, stepSize: stepSize), startX: staffStartX, width: width)
                }

                ForEach(bassLineSteps, id: \.self) { step in
                    staffLine(at: yFor(step: step, top: topPad, stepSize: stepSize), startX: staffStartX, width: width)
                }

                Text("𝄞")
                    .font(.system(size: lineGap * 7.7))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .overlay(
                        GlyphDebugBox(
                            text: "𝄞",
                            font: trebleClefFont,
                            color: .green
                        )
                    )
                    .position(
                        x: width * 0.22,
                        y: yFor(step: 4, top: topPad, stepSize: stepSize) - lineGap * 1.25
                    )

                Text("𝄢")
                    .font(.system(size: lineGap * 4.3))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .overlay(
                        GlyphDebugBox(
                            text: "𝄢",
                            font: bassClefFont,
                            color: .blue
                        )
                    )
                    .position(
                        x: width * 0.22,
                        y: yFor(step: -6, top: topPad, stepSize: stepSize) - lineGap * 0.5
                    )

                if noteCount > 0 {
                    let baseX: CGFloat = noteCount == 1 ? width * 0.64 : width * 0.50
                    let availableWidth = width * 0.40
                    let spacing = noteCount > 1 ? min(noteHeadWidth * 1.8, availableWidth / CGFloat(noteCount)) : 0

                    ForEach(Array(zip(notes, diatonicSteps).enumerated()), id: \.offset) { index, pair in
                        let note = pair.0
                        let step = pair.1
                        let noteX = baseX + CGFloat(index) * spacing
                        let noteY = yFor(step: step, top: topPad, stepSize: stepSize)
                        let stemDirection = stemDirection(for: step)
                        let stemHeight = lineGap * 2.3

                        ForEach(ledgerSteps(for: step), id: \.self) { ledgerStep in
                            Rectangle()
                                .fill(Color.black.opacity(0.60))
                                .frame(width: 36, height: 1.4)
                                .position(x: noteX, y: yFor(step: ledgerStep, top: topPad, stepSize: stepSize))
                        }

                        Rectangle()
                            .fill(Color(red: 0.13, green: 0.18, blue: 0.27))
                            .frame(width: 2.1, height: stemHeight)
                            .position(
                                x: noteX + (noteHeadWidth * 0.42 * (stemDirection > 0 ? -1 : 1)),
                                y: noteY + stemDirection * (stemHeight * 0.5)
                            )

                        Ellipse()
                            .fill(Color(red: 0.13, green: 0.18, blue: 0.27))
                            .frame(width: noteHeadWidth, height: noteHeadHeight)
                            .rotationEffect(.degrees(-10))
                            .position(x: noteX, y: noteY)

                        if note.isBlackKey {
                            Text("♯")
                                .font(.system(size: noteHeadHeight * 1.2, weight: .semibold, design: .serif))
                                .foregroundStyle(Color(red: 0.13, green: 0.18, blue: 0.27))
                                .position(x: noteX - noteHeadWidth * 0.95, y: noteY - 2)
                        }
                    }

                    Text(notes.map(\.displayName).joined(separator: " · "))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .position(x: width * 0.42, y: labelY)
                } else {
                    Text("Current notes on grand staff")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .position(x: width * 0.44, y: labelY)
                }
            }
        }
    }

    private func staffLine(at y: CGFloat, startX: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.72))
            .frame(height: 1.2)
            .frame(width: width - startX - 12)
            .position(x: startX + (width - startX - 12) / 2, y: y)
    }

    private static func logBraceMetrics(
        braceCenterY: CGFloat,
        trebleTopY: CGFloat,
        bassBottomY: CGFloat,
        height: CGFloat,
        topPad: CGFloat,
        bottomPad: CGFloat,
        stepSize: CGFloat
    ) {
        print(
            "StaffCanvas braceCenterY=\(braceCenterY), trebleTopY=\(trebleTopY), bassBottomY=\(bassBottomY), height=\(height), topPad=\(topPad), bottomPad=\(bottomPad), stepSize=\(stepSize)"
        )
    }
}

private struct GlyphDebugBox: View {
    let text: String
    let font: UIFont
    let color: Color
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1

    var body: some View {
        let metrics = glyphMetrics()

        return ZStack {
            Rectangle()
                .stroke(color.opacity(0.9), lineWidth: 1.5)
                .frame(
                    width: max(metrics.bounds.width * scaleX, 1),
                    height: max(metrics.bounds.height * scaleY, 1)
                )
                .offset(
                    x: metrics.offset.width * scaleX,
                    y: metrics.offset.height * scaleY
                )
        }
        .frame(
            width: max(metrics.lineSize.width * scaleX, 1),
            height: max(metrics.lineSize.height * scaleY, 1)
        )
    }

    private func glyphMetrics() -> (bounds: CGRect, lineSize: CGSize, offset: CGSize) {
        guard !text.isEmpty else {
            return (.zero, .zero, .zero)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let lineHeight = ascent + descent
        let glyphBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .excludeTypographicLeading]).standardized.integral

        let lineCenterX = lineWidth * 0.5
        let lineCenterY = (ascent - descent) * 0.5
        let glyphCenterX = glyphBounds.midX
        let glyphCenterY = glyphBounds.midY

        return (
            glyphBounds,
            CGSize(width: lineWidth, height: lineHeight),
            CGSize(
                width: glyphCenterX - lineCenterX,
                height: -(glyphCenterY - lineCenterY)
            )
        )
    }
}
