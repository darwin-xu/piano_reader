import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecognitionViewModel

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                header
                heroStrip
                StaffNoteView(note: viewModel.detectedNote)
                    .frame(height: geometry.size.height * 0.34)
                PianoKeyboardView(activeMIDINote: viewModel.activeMIDINote)
                    .frame(height: geometry.size.height * 0.20)
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.96, blue: 0.92), Color(red: 0.89, green: 0.92, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .task {
            await viewModel.prepareAudio()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Piano Reader")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("One-note listening with one visible octave.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Label(viewModel.permissionStatusText, systemImage: viewModel.permissionIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button(viewModel.isListening ? "Stop" : "Listen") {
                    viewModel.toggleListening()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStartListening)
            }
        }
    }

    private var heroStrip: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.detectedNote?.displayName ?? "--")
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .lineLimit(1)

                Text(viewModel.frequencyText)
                    .font(.headline)
                Text(viewModel.feedbackText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                TuningIndicatorView(centsOffset: viewModel.centsOffset)
                    .frame(width: 200)

                Text(viewModel.confidenceText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Visible scale: C4-B4")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView(viewModel: RecognitionViewModel.preview)
}