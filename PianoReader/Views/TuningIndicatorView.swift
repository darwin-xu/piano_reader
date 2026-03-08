import SwiftUI

struct TuningIndicatorView: View {
    let centsOffset: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Flat")
                Spacer()
                Text("In Tune")
                Spacer()
                Text("Sharp")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let clamped = max(-50.0, min(50.0, centsOffset))
                let normalized = (clamped + 50.0) / 100.0
                let xPosition = geometry.size.width * normalized

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.36, green: 0.61, blue: 0.86), Color(red: 0.23, green: 0.74, blue: 0.54), Color(red: 0.91, green: 0.45, blue: 0.25)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 12)

                    Circle()
                        .fill(.white)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 1))
                        .position(x: xPosition, y: 6)
                }
            }
            .frame(height: 24)
        }
    }
}