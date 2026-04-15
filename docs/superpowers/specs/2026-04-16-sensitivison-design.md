# Sensitivison — Design Spec
**Date:** 2026-04-16  
**Status:** Approved

---

## 1. Problem Statement

When viewing sensitive content on an iPhone in public, two distinct threats exist:

- **Passive exposure** — a bystander's face enters the camera frame; the user hasn't noticed yet
- **Screen capture** — the screen is being recorded, mirrored, or screenshot by a malicious app or a nearby person photographing the screen

The app must detect both threats and respond immediately without requiring user action.

---

## 2. Scope

### In scope
- Face detection via front camera → blur vault content when count > 1
- Screen recording detection via `UIScreen.isCaptured`
- Screenshot detection via `UIApplication.userDidTakeScreenshotNotification`
- Secure encrypted vault: photos, PDFs, notes, financial cards
- Biometric lock/unlock (Face ID / Touch ID)
- GitHub Actions CI/CD → Appetize.io live demo

### Out of scope
- System-wide notification protection (requires jailbreak; deferred)
- Cloud sync or backup
- Multiple user profiles
- iPad or Mac Catalyst support

---

## 3. Platform & Requirements

| Item | Value |
|---|---|
| Platform | iOS 17+ (iPhone only, portrait) |
| Language | Swift 5.9+, SwiftUI |
| Persistence | SwiftData |
| Encryption | CryptoKit AES-GCM 256-bit |
| Key storage | Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| Face detection | Vision `VNDetectFaceRectanglesRequest` + AVFoundation |
| Minimum deployment | iOS 17.0 |
| Build target | iOS Simulator (iphonesimulator SDK) |
| Deploy target | Appetize.io |

---

## 4. Architecture

### 4.1 Privacy Engine

Always-on layer that sits above all vault content. Composed of three components:

**FaceDetectionService**
- Opens `AVCaptureSession` on the front camera
- Runs `VNDetectFaceRectanglesRequest` on each frame via `VNSequenceRequestHandler`
- Publishes `@Published faceCount: Int` via Combine
- Simulator shim: `#if targetEnvironment(simulator)` exposes `simulatedFaceCount: Int` — no camera needed on Appetize
- Runs on a dedicated background serial queue

**ScreenCaptureService**
- Observes `UIScreen.capturedDidChangeNotification` → publishes `@Published isCapturing: Bool`
- Observes `UIApplication.userDidTakeScreenshotNotification` → fires one-shot `screenshotTaken` publisher

**PrivacyEngine** (coordinator, `@MainActor ObservableObject`)
- Combines `FaceDetectionService.$faceCount` and `ScreenCaptureService.$isCapturing` via `Publishers.CombineLatest`
- Applies 0.5s debounce to face count to prevent single-frame flicker
- Exposes `@Published threatActive: Bool` and `@Published threatReason: ThreatReason?`
- Injected as `@EnvironmentObject` into the root `ContentView`

**BlurOverlay** (SwiftUI view)
- Positioned at top of root `ZStack`, above all vault tabs
- `ultraThinMaterial` background + lock icon + reason label
- Animated with `.easeInOut(duration: 0.3)` on appear/disappear
- Screenshot event: shows overlay + dismissible warning banner, auto-clears after 3s

### 4.2 Threat Matrix

| Trigger | Condition | Response | Auto-clear |
|---|---|---|---|
| Extra face | `faceCount > 1` sustained 0.5s | Frosted blur overlay | When count drops to 1 |
| Screen recording | `UIScreen.isCaptured == true` | Frosted blur overlay | When recording stops |
| Screenshot | Notification fired | Overlay + warning banner | After 3s |

### 4.3 Vault — Data Model

All sensitive fields encrypted with AES-GCM before storage. Binary files (photos, PDFs) stored as `.enc` files in `Documents/vault/`, with metadata held in SwiftData.

**VaultPhoto**
```
id: UUID
encryptedFilePath: String        // path to .enc file in Documents/vault/photos/ — UUID-based filename, safe unencrypted
encryptedThumbnail: Data         // AES-GCM encrypted 120×120 JPEG thumbnail
createdAt: Date
```

**VaultDocument**
```
id: UUID
encryptedName: Data              // AES-GCM encrypted display name
encryptedFilePath: String        // path to .enc file in Documents/vault/docs/ — UUID-based filename, safe unencrypted
pageCount: Int                   // unencrypted, used for list preview only
createdAt: Date
```

**VaultNote**
```
id: UUID
encryptedTitle: Data             // AES-GCM encrypted
encryptedBody: Data              // AES-GCM encrypted
updatedAt: Date
```

**VaultCard**
```
id: UUID
encryptedNumber: Data            // AES-GCM encrypted
encryptedCVV: Data               // AES-GCM encrypted
encryptedPIN: Data               // AES-GCM encrypted
encryptedHolder: Data            // AES-GCM encrypted
encryptedExpiry: Data            // AES-GCM encrypted
cardType: String                 // "visa" / "mastercard" — unencrypted, used for card art only
```

### 4.4 CryptoVault Service

Single access point for all encrypt/decrypt operations.

```swift
// Interface
func encrypt(_ data: Data) throws -> Data
func decrypt(_ data: Data) throws -> Data
func encryptString(_ string: String) throws -> Data
func decryptString(_ data: Data) throws -> String
```

- AES-GCM key loaded from Keychain after biometric auth
- Key held in memory as `SymmetricKey` until vault locks
- On lock (app background): key zeroed with `withUnsafeMutableBytes`
- On first launch: generates `SymmetricKey(.bits256)`, stores raw bytes in Keychain

### 4.5 Lock / Unlock Lifecycle

```
App foreground → LAContext biometric auth → key loaded into CryptoVault → vault accessible
App background → key zeroed from memory → vault locked → blur overlay shown
```

- `scenePhase` SwiftUI environment value drives background detection
- Auth failure shows lock screen, vault content not accessible
- Blur overlay only activates when vault is **unlocked** — the lock screen itself contains no sensitive content and does not need the overlay

---

## 5. UI Structure

### Navigation
5-tab `TabView`:
1. 🖼️ Photos
2. 📄 Documents
3. 📝 Notes
4. 💳 Cards
5. ⚙️ Settings

### Screens

**Lock screen** — full-screen, black background, app name, Face ID prompt button. Auto-presented when vault is locked.

**Photos tab** — 3-column encrypted thumbnail grid. Tap `+` to import from Camera Roll (PHPickerViewController). Tap photo → full-screen viewer. Swipe to delete with confirmation.

**Documents tab** — list view showing decrypted file name and page count. Tap `+` to import via `UIDocumentPickerViewController`. Tap document → in-app PDF viewer (`PDFKit`). Swipe to delete.

**Notes tab** — list showing decrypted title and relative date. Tap `+` → new note editor (title + body, auto-save on dismiss). Tap existing → edit. Swipe to delete.

**Cards tab** — vertical list of card art tiles showing last 4 digits and holder name. Tap card → 3D flip animation revealing CVV, full number, and PIN. Tap `+` → `AddCardView` form. Swipe to delete.

**Settings tab**
- Face detection sensitivity: threshold (1 extra face / 2+ extra faces)
- Debounce duration: 0.3s / 0.5s / 1.0s
- Screenshot reaction: warn only / full blur
- Auto-lock timer: immediately / 30s / 1min
- Auth method: biometrics (Face ID or Touch ID, device-dependent — LAContext picks automatically) or device passcode fallback

**Debug toolbar** (`#if DEBUG` only)
- Floating bottom bar visible only in debug builds (Appetize)
- Face count buttons: 0 / 1 / 2+
- Screen capture toggle: Off / On

---

## 6. File Structure

```
Sensitivison/
├── App/
│   ├── SensitivisonApp.swift
│   └── ContentView.swift            ← root ZStack + BlurOverlay + TabView
├── PrivacyEngine/
│   ├── PrivacyEngine.swift
│   ├── FaceDetectionService.swift
│   ├── ScreenCaptureService.swift
│   └── BlurOverlay.swift
├── Vault/
│   ├── Models/
│   │   ├── VaultPhoto.swift
│   │   ├── VaultDocument.swift
│   │   ├── VaultNote.swift
│   │   └── VaultCard.swift
│   ├── Crypto/
│   │   ├── CryptoVault.swift
│   │   └── KeychainService.swift
│   ├── Photos/
│   │   ├── PhotosView.swift
│   │   ├── PhotoGridView.swift
│   │   └── PhotoDetailView.swift
│   ├── Documents/
│   │   ├── DocumentsView.swift
│   │   └── PDFViewerView.swift
│   ├── Notes/
│   │   ├── NotesView.swift
│   │   └── NoteEditorView.swift
│   └── Cards/
│       ├── CardsView.swift
│       ├── CardView.swift
│       └── AddCardView.swift
├── Settings/
│   └── SettingsView.swift
├── Debug/                           ← #if DEBUG only
│   └── DebugToolbar.swift
└── Resources/
    ├── Assets.xcassets
    └── Info.plist

.github/
└── workflows/
    └── build.yml                    ← xcodebuild → zip → Appetize.io upload
```

---

## 7. CI/CD Pipeline

### GitHub Actions (`build.yml`)

**Trigger:** push to `main`

**Steps:**
1. `macos-latest` runner, Xcode latest stable
2. `xcodebuild -scheme Sensitivison -sdk iphonesimulator -configuration Debug`
3. Locate `.app` in `DerivedData`, zip as `Sensitivison.app.zip`
4. Upload to Appetize.io via REST API (multipart POST)
5. Print public Appetize URL to logs
6. Upload `.app.zip` as GitHub Actions artifact

### Secrets required

| Secret | When to add | Source |
|---|---|---|
| `APPETIZE_API_TOKEN` | Before first push | appetize.io → Account → API Token |
| `APPETIZE_APP_KEY` | After first push | Printed in CI logs; paste back as secret for subsequent updates |

---

## 8. Simulator / Appetize Considerations

- Front camera not available on Appetize.io
- `FaceDetectionService` uses `#if targetEnvironment(simulator)` to expose `simulatedFaceCount`
- `DebugToolbar` (DEBUG builds only) provides face count buttons (0/1/2+) and screen capture toggle
- `UIScreen.isCaptured` and screenshot notifications work normally in simulator
- Biometric auth: simulator supports Face ID simulation via `Hardware → Face ID → Enrolled` + `Matching Face`

---

## 9. Out-of-scope / Future Work

- System-wide notification blurring (requires jailbreak tweak — separate project)
- iCloud / encrypted backup
- App Store submission (requires paid Apple Developer account + code signing)
- Apple Watch companion (lock/unlock from wrist)
