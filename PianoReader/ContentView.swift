import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecognitionViewModel

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                statusBar
                heroBanner
                StaffNoteView(note: viewModel.detectedNote)
                    .frame(height: geometry.size.height * 0.35)
                PianoKeyboardView(activeMIDINote: viewModel.activeMIDINote)
                    .frame(height: geometry.size.height * 0.24)
                controlsPanel
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(Color(red: 0.91, green: 0.91, blue: 0.92).ignoresSafeArea())
        .task {
            await viewModel.prepareAudio()
        }
    }

    private var statusBar: some View {
        HStack {
            Spacer()
            Text(viewModel.isListening ? "Listening..." : "Ready")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.28, green: 0.47, blue: 0.69))
            Spacer()
        }
        .frame(height: 64)
        .background(Color.white)
    }

    private var heroBanner: some View {
        VStack(spacing: 6) {
            Text(viewModel.detectedNote?.displayName ?? "--")
                .font(.system(size: 84, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(viewModel.frequencyText)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.96))

            Text(centsText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(centsColor)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 175)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.29, blue: 0.36),
                    Color(red: 0.18, green: 0.22, blue: 0.29),
                    Color(red: 0.23, green: 0.28, blue: 0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var controlsPanel: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 14)

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

            Text(viewModel.isListening ? "Stop" : "Listen")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.91, green: 0.91, blue: 0.92))
    }

    private var centsText: String {
        guard viewModel.frequency > 0 else {
            return "Waiting for note"
        }

        let rounded = Int(viewModel.centsOffset.rounded())
        if rounded == 0 {
            return "In tune"
        }
        return String(format: "%+d cents", rounded)
    }

    private var centsColor: Color {
        guard viewModel.frequency > 0 else {
            return Color.white.opacity(0.75)
        }
        return Color(red: 0.52, green: 0.91, blue: 0.62)
    }
}

#Preview {
    ContentView(viewModel: RecognitionViewModel.preview)
}