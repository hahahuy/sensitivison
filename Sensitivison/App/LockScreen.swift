import SwiftUI
import LocalAuthentication
import CryptoKit

struct LockScreen: View {
    let onUnlocked: (SymmetricKey) -> Void
    @State private var errorMessage: String?
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                Text("Sensitivison")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text("Your vault is locked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .transition(.opacity.animation(.easeIn(duration: 0.2)))
                }
                Button(action: authenticate) {
                    Label(authButtonLabel, systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
                .accessibilityLabel("Unlock vault with Face ID")
            }
        }
    }

    private var authButtonLabel: String {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return context.biometryType == .faceID ? "Unlock with Face ID" : "Unlock with Touch ID"
        }
        return "Unlock"
    }

    private func authenticate() {
        isAuthenticating = true
        errorMessage = nil
        let context = LAContext()
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock your Sensitivison vault"
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    let key = loadOrCreateKey()
                    withAnimation(.easeInOut(duration: 0.3)) { onUnlocked(key) }
                } else {
                    errorMessage = "Authentication failed. Try again."
                }
            }
        }
    }

    private func loadOrCreateKey() -> SymmetricKey {
        let keychainKey = "com.sensitivison.vault.key"
        if let data = try? KeychainService.load(key: keychainKey) {
            return SymmetricKey(data: data)
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try? KeychainService.save(data: keyData, key: keychainKey)
        return newKey
    }
}
