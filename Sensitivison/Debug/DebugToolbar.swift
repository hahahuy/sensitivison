#if DEBUG
import SwiftUI

struct DebugToolbar: View {
    let faceDetectionService: FaceDetectionService
    let screenCaptureService: ScreenCaptureService
    @State private var selectedFaces: Int = 1
    @State private var captureOn: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Text("SIM").font(.caption.monospaced()).foregroundStyle(.orange)
            Text("Faces:").font(.caption).foregroundStyle(.secondary)
            ForEach([0, 1, 2], id: \.self) { count in
                Button(count == 2 ? "2+" : "\(count)") {
                    selectedFaces = count
                    faceDetectionService.simulatedFaceCount = count
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(selectedFaces == count ? Color.accentColor : Color.clear)
                .foregroundStyle(selectedFaces == count ? .white : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
                .font(.caption)
                .accessibilityLabel("Simulate \(count) face(s)")
            }
            Divider().frame(height: 20)
            Text("Capture:").font(.caption).foregroundStyle(.secondary)
            ForEach([false, true], id: \.self) { on in
                Button(on ? "On" : "Off") {
                    captureOn = on
                    screenCaptureService.simulatedIsCapturing = on
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(captureOn == on ? (on ? Color.red : Color.accentColor) : Color.clear)
                .foregroundStyle(captureOn == on ? .white : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(captureOn == on ? (on ? Color.red : Color.accentColor) : Color.accentColor, lineWidth: 1))
                .font(.caption)
                .accessibilityLabel("Simulate screen capture \(on ? "on" : "off")")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 8)
    }
}
#endif
