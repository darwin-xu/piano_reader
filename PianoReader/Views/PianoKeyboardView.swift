import SwiftUI

struct PianoKeyboardView: View {
    let activeMIDINote: Int?

    private let whiteKeys = KeyboardLayout.visibleWhiteKeys
    private let blackKeys = KeyboardLayout.visibleBlackKeys

    var body: some View {
        GeometryReader { geometry in
            let whiteKeyWidth = geometry.size.width / CGFloat(whiteKeys.count)
            let blackKeyWidth = whiteKeyWidth * 0.62
            let blackKeyHeight = geometry.size.height * 0.62

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(whiteKeys) { note in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(fillColor(for: note, defaultColor: .white))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.black.opacity(0.22), lineWidth: 1)
                            )
                            .frame(width: whiteKeyWidth)
                    }
                }

                ForEach(blackKeys) { note in
                    let offset = CGFloat(KeyboardLayout.visibleWhiteKeyOffset(for: note.midiNumber)) * whiteKeyWidth - (blackKeyWidth / 2)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(fillColor(for: note, defaultColor: Color.black.opacity(0.84)))
                        .frame(width: blackKeyWidth, height: blackKeyHeight)
                        .offset(x: offset)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 8)
    }

    private func fillColor(for note: PianoNote, defaultColor: Color) -> Color {
        guard activeMIDINote == note.midiNumber else {
            return defaultColor
        }

        return note.isBlackKey
            ? Color(red: 0.93, green: 0.64, blue: 0.21)
            : Color(red: 0.95, green: 0.75, blue: 0.32)
    }
}