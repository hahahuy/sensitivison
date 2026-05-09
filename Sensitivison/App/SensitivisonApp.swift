import SwiftUI
import SwiftData
import CryptoKit

@main
struct SensitivisonApp: App {
    @StateObject private var privacyEngine = PrivacyEngine()
    @State private var isLocked = true
    @State private var cryptoVault: CryptoVault = CryptoVault(key: SymmetricKey(size: .bits256))

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isLocked {
                    LockScreen { key in
                        cryptoVault = CryptoVault(key: key)
                        isLocked = false
                        privacyEngine.start()
                    }
                } else {
                    ContentView()
                        .environmentObject(privacyEngine)
                        .environmentObject(cryptoVault)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    cryptoVault.lock()
                    isLocked = true
                    privacyEngine.stop()
                }
            }
        }
        .modelContainer(for: [VaultPhoto.self, VaultDocument.self, VaultNote.self, VaultCard.self])
    }
}
