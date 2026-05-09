import SwiftUI

struct ContentView: View {
    @EnvironmentObject var privacyEngine: PrivacyEngine

    var body: some View {
        ZStack {
            MainTabView()
                .accessibilityHidden(privacyEngine.threatActive)

            BlurOverlay(
                threatActive: privacyEngine.threatActive,
                reason: privacyEngine.threatReason
            )

            #if DEBUG
            VStack {
                Spacer()
                DebugToolbar(
                    faceDetectionService: privacyEngine.faceDetectionService,
                    screenCaptureService: privacyEngine.screenCaptureService
                )
            }
            #endif
        }
    }
}
