import Combine
import Foundation

enum ThreatReason: Equatable {
    case faceDetected
    case screenCapture
    case screenshot
}

@MainActor
final class PrivacyEngine: ObservableObject {
    @Published private(set) var threatActive: Bool = false
    @Published private(set) var threatReason: ThreatReason?

    let faceDetectionService = FaceDetectionService()
    let screenCaptureService = ScreenCaptureService()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Face detection: debounce 0.5s to avoid single-frame flicker
        faceDetectionService.$faceCount
            .map { $0 > 1 }
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .combineLatest(screenCaptureService.$isCapturing)
            .map { faceActive, captureActive -> (Bool, ThreatReason?) in
                if captureActive { return (true, .screenCapture) }
                if faceActive { return (true, .faceDetected) }
                return (false, nil)
            }
            .sink { [weak self] active, reason in
                self?.threatActive = active
                self?.threatReason = reason
            }
            .store(in: &cancellables)

        // Screenshot: one-shot, auto-clears after 3s
        screenCaptureService.screenshotTaken
            .sink { [weak self] in
                self?.threatActive = true
                self?.threatReason = .screenshot
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    if self?.threatReason == .screenshot {
                        self?.threatActive = false
                        self?.threatReason = nil
                    }
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        faceDetectionService.start()
    }

    func stop() {
        faceDetectionService.stop()
    }
}
