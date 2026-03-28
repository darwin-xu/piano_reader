import CoreText
import SwiftUI
import UIKit

// Grand staff reference using diatonic steps relative to middle C (C4 = step 0).
// Treble lines:  E4 G4 B4 D5 F5  -> steps 2, 4, 6, 8, 10
// Bass lines:    G2 B2 D3 F3 A3  -> steps -10, -8, -6, -4, -2
// Middle C sits between the staves on ledger line step 0.

struct StaffNoteView: View {
    let notes: [PianoNote]
    private static let exampleNotes: [PianoNote] = [
        PianoNote(midiNumber: 48, frequency: 130.81, centsOffset: 0),
        PianoNote(midiNumber: 50, frequency: 146.83, centsOffset: 0),
        PianoNote(midiNumber: 52, frequency: 164.81, centsOffset: 0),
        PianoNote(midiNumber: 53, frequency: 174.61, centsOffset: 0),
        PianoNote(midiNumber: 55, frequency: 196.00, centsOffset: 0),
        PianoNote(midiNumber: 57, frequency: 220.00, centsOffset: 0),
        PianoNote(midiNumber: 59, frequency: 246.94, centsOffset: 0),
        PianoNote(midiNumber: 60, frequency: 261.63, centsOffset: 0),
        PianoNote(midiNumber: 62, frequency: 293.66, centsOffset: 0),
        PianoNote(midiNumber: 64, frequency: 329.63, centsOffset: 0),
        PianoNote(midiNumber: 65, frequency: 349.23, centsOffset: 0),
        PianoNote(midiNumber: 67, frequency: 392.00, centsOffset: 0),
        PianoNote(midiNumber: 69, frequency: 440.00, centsOffset: 0),
        PianoNote(midiNumber: 71, frequency: 493.88, centsOffset: 0),
    ]

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
    private let scrollDuration: TimeInterval = 6
    @State private var noteHistory: [ScrollingNoteEvent] = []

    private func diatonicStep(for midiNumber: Int) -> Int {
        let delta = midiNumber - 60
        let octaves = delta >= 0 ? delta / 12 : (delta - 11) / 12
        let pitchClass = ((delta % 12) + 12) % 12
        return octaves * 7 + Self.pitchClassStep[pitchClass]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            StaffCanvas(
                currentNotes: notes,
                scrollingNotes: visibleNotes(at: context.date)
            )
        }
        .onAppear {
            if !notes.isEmpty {
                let now = Date()
                append(notes: notes, at: now)
            }
        }
        .onChange(of: notes.map(\.midiNumber)) {
            if !notes.isEmpty {
                let now = Date()
                append(notes: notes, at: now)
            }
        }
    }

    private func visibleNotes(at date: Date) -> [VisibleScrollingNote] {
        if notes.isEmpty {
            return repeatingExampleNotes(at: date)
        }

        return noteHistory
            .filter { date.timeIntervalSince($0.timestamp) <= scrollDuration }
            .sorted { $0.timestamp < $1.timestamp }
            .map { event in
                let age = max(date.timeIntervalSince(event.timestamp), 0)
                return VisibleScrollingNote(
                    id: event.id,
                    note: event.note,
                    step: event.step,
                    age: age
                )
            }
    }

    private func append(notes: [PianoNote], at date: Date) {
        noteHistory.removeAll { date.timeIntervalSince($0.timestamp) > scrollDuration }
        noteHistory.append(
            contentsOf: notes.map { note in
                ScrollingNoteEvent(
                    note: note,
                    step: diatonicStep(for: note.midiNumber),
                    timestamp: date
                )
            }
        )
    }

    private func repeatingExampleNotes(at date: Date) -> [VisibleScrollingNote] {
        let noteCount = Self.exampleNotes.count
        guard noteCount > 0 else { return [] }

        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: scrollDuration)
        let spacing = scrollDuration / Double(noteCount)

        return Self.exampleNotes.enumerated().map { index, note in
            let age = phase - Double(index) * spacing
            let wrappedAge = age >= 0 ? age : age + scrollDuration
            return VisibleScrollingNote(
                id: UUID(),
                note: note,
                step: diatonicStep(for: note.midiNumber),
                age: wrappedAge
            )
        }
    }
}

private struct StaffCanvas: View {
    let currentNotes: [PianoNote]
    let scrollingNotes: [VisibleScrollingNote]

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

    private func noteGlyph(for step: Int) -> String {
        let scalar: UInt32
        if step >= 0 {
            // Treble staff: middle line is step 6 (B4).
            scalar = step >= 6 ? 0xE1D6 : 0xE1D5
        } else {
            // Bass staff: middle line is step -6 (D3).
            scalar = step >= -6 ? 0xE1D6 : 0xE1D5
        }
        return String(UnicodeScalar(scalar)!)
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
            let labelY: CGFloat = 22
            let smuflBrace = String(UnicodeScalar(0xE000)!)
            let smuflTrebleClef = String(UnicodeScalar(0xE050)!)
            let smuflBassClef = String(UnicodeScalar(0xE062)!)
            
            // Left and right margin of the grand sheet
            let margin: CGFloat = 10

            let trebleTopY = yFor(step: 10, top: topPad, stepSize: stepSize)
            let bassBottomY = yFor(step: -10, top: topPad, stepSize: stepSize)
            
            let braceCenterY = (trebleTopY + bassBottomY) / 2
            let braceSpan = bassBottomY - trebleTopY
            let braceBaseSize = lineGap * 10
            let braceVerticalScale = max(braceSpan / (braceBaseSize * 1.45), 1)
            let braceFont = UIFont(name: "Bravura", size: braceBaseSize) ?? .systemFont(ofSize: braceBaseSize)
            let braceWidth = glyphMetrics(for: smuflBrace, font: braceFont).bounds.width
            let braceCenterX = margin + braceWidth / 2
            
            // X position for the sheet bar
            let barLineX = margin + braceWidth
            
            let clefLeftX: CGFloat = barLineX + 10
            let trebleClefSize = lineGap * 4
            let trebleClefFont = UIFont(name: "Bravura", size: trebleClefSize) ?? .systemFont(ofSize: trebleClefSize)
            let trebleClefWidth = glyphMetrics(for: smuflTrebleClef, font: trebleClefFont).bounds.width
            let trebleClefCenterX = clefLeftX + trebleClefWidth / 2

            let bassClefSize = lineGap * 4
            let bassClefFont = UIFont(name: "Bravura", size: bassClefSize) ?? .systemFont(ofSize: bassClefSize)
            let bassClefWidth = glyphMetrics(for: smuflBassClef, font: bassClefFont).bounds.width
            let bassClefCenterX = clefLeftX + bassClefWidth / 2
            let noteGlyphSize = lineGap * 3.2
            
            //let noteStartX = clefLeftX + max(trebleClefWidth, bassClefWidth) + lineGap * 0.9
            let noteStartX = max(clefLeftX + trebleClefWidth, clefLeftX + bassClefWidth) + 10
            let noteEndX = width - margin
            let notePointsPerSecond = noteGlyphSize * 1.6

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
                    .position(x: braceCenterX, y: bassBottomY)

                Rectangle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 2.2, height: braceSpan)
                    .position(x: barLineX, y: braceCenterY)

                ForEach(trebleLineSteps, id: \.self) { step in
                    staffLine(
                        at: yFor(step: step, top: topPad, stepSize: stepSize),
                        startX: staffStartX,
                        width: width,
                        rightMargin: margin
                    )
                }

                ForEach(bassLineSteps, id: \.self) { step in
                    staffLine(
                        at: yFor(step: step, top: topPad, stepSize: stepSize),
                        startX: staffStartX,
                        width: width,
                        rightMargin: margin
                    )
                }

                Rectangle()
                    .stroke(Color.orange.opacity(0.9), lineWidth: 1.5)
                    .frame(
                        width: max(noteEndX - noteStartX, 1),
                        height: max(usableHeight, 1)
                    )
                    .position(
                        x: noteStartX + (noteEndX - noteStartX) / 2,
                        y: topPad + usableHeight / 2
                    )

                Text(smuflTrebleClef)
                    .font(.custom("Bravura", size: trebleClefSize))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .overlay(
                        GlyphDebugBox(
                            text: smuflTrebleClef,
                            font: trebleClefFont,
                            color: .green
                        )
                    )
                    .position(
                        x: trebleClefCenterX,
                        y: yFor(step: 4, top: topPad, stepSize: stepSize) - lineGap * 0
                    )

                Text(smuflBassClef)
                    .font(.custom("Bravura", size: bassClefSize))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .overlay(
                        GlyphDebugBox(
                            text: smuflBassClef,
                            font: bassClefFont,
                            color: .blue
                        )
                    )
                    .position(
                        x: bassClefCenterX,
                        y: yFor(step: -4, top: topPad, stepSize: stepSize) - lineGap * 0
                    )

                let noteHeadFont = UIFont(name: "Bravura", size: noteGlyphSize) ?? .systemFont(ofSize: noteGlyphSize)
                let sharpFont = UIFont.systemFont(ofSize: lineGap * 1.2, weight: .semibold)

                ForEach(scrollingNotes) { entry in
                    let noteX = noteEndX - CGFloat(entry.age) * notePointsPerSecond
                    let noteY = yFor(step: entry.step, top: topPad, stepSize: stepSize)
                    let noteGlyph = noteGlyph(for: entry.step)
                    let ledgers = ledgerSteps(for: entry.step)

                    let noteHeadHalfWidth = max(glyphMetrics(for: noteGlyph, font: noteHeadFont).bounds.width / 2, 1)
                    let ledgerHalfWidth: CGFloat = ledgers.isEmpty ? noteHeadHalfWidth : max(noteHeadHalfWidth, 18)
                    let accidentalOffsetX: CGFloat = entry.note.isBlackKey ? lineGap * 1.1 : 0
                    let accidentalHalfWidth: CGFloat = entry.note.isBlackKey ? max(glyphMetrics(for: "♯", font: sharpFont).bounds.width / 2, 1) : 0

                    let leftEdge = noteX - ledgerHalfWidth - accidentalOffsetX - accidentalHalfWidth
                    let rightEdge = noteX + ledgerHalfWidth

                    if leftEdge >= noteStartX && rightEdge <= noteEndX {
                        ForEach(ledgers, id: \.self) { ledgerStep in
                            Rectangle()
                                .fill(Color.black.opacity(0.60))
                                .frame(width: 36, height: 1.4)
                                .position(x: noteX, y: yFor(step: ledgerStep, top: topPad, stepSize: stepSize))
                        }

                        Text(noteGlyph)
                            .font(.custom("Bravura", size: noteGlyphSize))
                            .foregroundStyle(Color(red: 0.13, green: 0.18, blue: 0.27))
                            .position(x: noteX, y: noteY)

                        if entry.note.isBlackKey {
                            Text("♯")
                                .font(.system(size: lineGap * 1.2, weight: .semibold, design: .serif))
                                .foregroundStyle(Color(red: 0.13, green: 0.18, blue: 0.27))
                                .position(x: noteX - accidentalOffsetX, y: noteY - 2)
                        }
                    }
                }

                if !currentNotes.isEmpty {
                    Text(currentNotes.map(\.displayName).joined(separator: " · "))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .position(x: width * 0.42, y: labelY)
                } else {
                    Text(scrollingNotes.isEmpty ? "Waiting for notes" : "Sliding note history")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .position(x: width * 0.44, y: labelY)
                }
            }
        }
    }

    private func staffLine(at y: CGFloat, startX: CGFloat, width: CGFloat, rightMargin: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.72))
            .frame(height: 1)
            .frame(width: width - startX - rightMargin)
            .position(x: startX + (width - startX - rightMargin) / 2, y: y)
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

private struct ScrollingNoteEvent: Identifiable {
    let id = UUID()
    let note: PianoNote
    let step: Int
    let timestamp: Date
}

private struct VisibleScrollingNote: Identifiable {
    let id: UUID
    let note: PianoNote
    let step: Int
    let age: Double
}

private struct GlyphDebugBox: View {
    let text: String
    let font: UIFont
    let color: Color
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1

    var body: some View {
        let metrics = glyphMetrics(for: text, font: font)

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

}

private func glyphMetrics(for text: String, font: UIFont) -> (bounds: CGRect, lineSize: CGSize, offset: CGSize) {
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
#Preview {
    StaffNoteView(
        notes: [
            PianoNote(midiNumber: 60, frequency: 261.63, centsOffset: 0),
            PianoNote(midiNumber: 64, frequency: 329.63, centsOffset: 0),
            PianoNote(midiNumber: 67, frequency: 392.00, centsOffset: 0),
        ]
    )
    .frame(height: 320)
    .padding()
    .background(Color(.systemGroupedBackground))
}

