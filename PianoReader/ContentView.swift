import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecognitionViewModel
    @State private var heroPhase: CGFloat = 0

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

    private var heroBanner: some View {
        VStack(spacing: 6) {
            Text(viewModel.detectedNote?.displayName ?? "--")
                .font(.system(size: 84, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
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
            ZStack {
                // Base rich gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.21, green: 0.28, blue: 0.39),
                        Color(red: 0.13, green: 0.18, blue: 0.28),
                        Color(red: 0.20, green: 0.28, blue: 0.39)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Drifting ambient glow
                RadialGradient(
                    colors: [
                        Color(red: 0.28, green: 0.40, blue: 0.62).opacity(0.35),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: 0.25 + heroPhase * 0.3,
                        y: 0.3 + heroPhase * 0.2
                    ),
                    startRadius: 30,
                    endRadius: 180
                )

                // Counter-phase ambient glow
                RadialGradient(
                    colors: [
                        Color(red: 0.18, green: 0.25, blue: 0.48).opacity(0.25),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: 0.75 - heroPhase * 0.25,
                        y: 0.7 - heroPhase * 0.15
                    ),
                    startRadius: 20,
                    endRadius: 160
                )

                // Fine grain texture
                Canvas { context, size in
                    for x in stride(from: 0, through: size.width, by: 4) {
                        for y in stride(from: 0, through: size.height, by: 4) {
                            let seed = (Int(x) * 73 + Int(y) * 127) % 1000
                            let hash = abs(seed) % 100
                            if hash < 30 {
                                let alpha = Double(hash) / 3000.0
                                context.fill(
                                    Path(CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                    with: .color(.white.opacity(alpha))
                                )
                            }
                        }
                    }
                }
                .blendMode(.overlay)
                .allowsHitTesting(false)

                // Shimmer sweep
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.03),
                                    .white.opacity(0.08),
                                    .white.opacity(0.03),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 100)
                        .rotationEffect(.degrees(25))
                        .offset(x: -150 + heroPhase * (geo.size.width + 300))
                }
                .clipped()
                .allowsHitTesting(false)

                // Top-leading highlight
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.clear,
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                heroPhase = 1
            }
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