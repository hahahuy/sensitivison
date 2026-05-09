import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @AppStorage("faceSensitivity") private var faceSensitivity: Int = 1
    @AppStorage("debounceMs") private var debounceMs: Double = 500
    @AppStorage("screenshotReaction") private var screenshotReaction: String = "blurAndWarn"
    @AppStorage("autoLockSeconds") private var autoLockSeconds: Int = 0

    var authMethodLabel: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return "Passcode" }
        return context.biometryType == .faceID ? "Face ID" : "Touch ID"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Face Detection") {
                    Picker("Sensitivity", selection: $faceSensitivity) {
                        Text("1 extra face").tag(1)
                        Text("2+ extra faces").tag(2)
                    }
                    Picker("Reaction delay", selection: $debounceMs) {
                        Text("0.3s").tag(300.0)
                        Text("0.5s").tag(500.0)
                        Text("1.0s").tag(1000.0)
                    }
                }
                Section("Screen Capture") {
                    Picker("Screenshot reaction", selection: $screenshotReaction) {
                        Text("Blur + warn").tag("blurAndWarn")
                        Text("Warn only").tag("warnOnly")
                    }
                }
                Section("Security") {
                    Picker("Auto-lock", selection: $autoLockSeconds) {
                        Text("Immediately").tag(0)
                        Text("After 30 seconds").tag(30)
                        Text("After 1 minute").tag(60)
                    }
                    LabeledContent("Authentication", value: authMethodLabel)
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
