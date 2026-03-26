import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecognitionViewModel
    @State private var staffHeightRatio: CGFloat = 0.35
    @State private var dragStartStaffHeightRatio: CGFloat?
    // TODO: style to choose from
    // .layeredRibbons
    // .envelopeBars
    // .neonThreads
    private let waveformStyle: WaveformEnvelopeView.Style = .neonThreads
    private let minStaffHeightRatio: CGFloat = 0.20
    private let maxStaffHeightRatio: CGFloat = 0.60

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                statusBar(containerHeight: geometry.size.height)
                WaveformEnvelopeView(
                    envelope: viewModel.waveformEnvelope,
                    isListening: viewModel.isListening,
                    noteLabel: viewModel.waveformNoteLabel,
                    detailLabel: viewModel.waveformDetailText,
                    style: waveformStyle
                )
                StaffNoteView(notes: viewModel.detectedNotes)
                    .frame(height: geometry.size.height * staffHeightRatio)
                PianoKeyboardView(activeMIDINotes: viewModel.activeMIDINotes)
                    .frame(height: geometry.size.height * 0.24)
                controlsPanel
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                    Color(red: 0.89, green: 0.91, blue: 0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .task {
            await viewModel.prepareAudio()
        }
    }

    private func statusBar(containerHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Text(viewModel.isListening ? "Listening..." : "Ready")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.24, green: 0.42, blue: 0.67))

                Text("\(Int(staffHeightRatio * 100))%")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.22))
                .frame(width: 72, height: 6)
                .contentShape(Rectangle())
                .gesture(staffResizeGesture(containerHeight: containerHeight))
        }
        .frame(height: 64)
        .background(Color.white.opacity(0.92))
    }

    private func staffResizeGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartStaffHeightRatio == nil {
                    dragStartStaffHeightRatio = staffHeightRatio
                }

                let startingRatio = dragStartStaffHeightRatio ?? staffHeightRatio
                let proposedRatio = startingRatio + (value.translation.height / max(containerHeight, 1))
                staffHeightRatio = min(max(proposedRatio, minStaffHeightRatio), maxStaffHeightRatio)
            }
            .onEnded { _ in
                dragStartStaffHeightRatio = nil
            }
    }

    private var controlsPanel: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 2)

            Button {
                viewModel.toggleListening()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.25, green: 0.60, blue: 0.97),
                                    Color(red: 0.04, green: 0.24, blue: 0.74)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 2)
                                .padding(4)
                        )
                        .shadow(color: Color.blue.opacity(0.18), radius: 10, y: 6)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 92, height: 92)
            .disabled(!viewModel.canStartListening)

            Spacer(minLength: 18)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

}

#Preview {
    ContentView(viewModel: RecognitionViewModel.preview)
}
