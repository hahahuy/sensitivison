import SwiftUI

struct BlurOverlay: View {
    let threatActive: Bool
    let reason: ThreatReason?

    var body: some View {
        if threatActive {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.primary)
                    Text("Content Hidden")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(reasonText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Content hidden for privacy")
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
        }
    }

    private var reasonText: String {
        switch reason {
        case .faceDetected: return "Someone else is looking"
        case .screenCapture: return "Screen recording active"
        case .screenshot: return "Screenshot captured"
        case nil: return ""
        }
    }
}
