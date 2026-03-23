import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecognitionViewModel
    // TODO: here controls what style is for waveform
    private let waveformStyle: WaveformEnvelopeView.Style = .layeredRibbons

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                statusBar
                WaveformEnvelopeView(
                    envelope: viewModel.waveformEnvelope,
                    isListening: viewModel.isListening,
                    noteLabel: viewModel.waveformNoteLabel,
                    detailLabel: viewModel.waveformDetailText,
                    style: waveformStyle
                )
                StaffNoteView(notes: viewModel.detectedNotes)
                    .frame(height: geometry.size.height * 0.35)
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

    private var statusBar: some View {
        HStack {
            Spacer()
            Text(viewModel.isListening ? "Listening..." : "Ready")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.24, green: 0.42, blue: 0.67))
            Spacer()
        }
        .frame(height: 64)
        .background(Color.white.opacity(0.92))
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
