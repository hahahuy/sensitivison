import UIKit
import Combine

@MainActor
final class ScreenCaptureService: ObservableObject {
    @Published private(set) var isCapturing: Bool = false
    let screenshotTaken = PassthroughSubject<Void, Never>()

    // Simulator / testing override
    var simulatedIsCapturing: Bool = false {
        didSet { isCapturing = simulatedIsCapturing }
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                #if targetEnvironment(simulator)
                // UIScreen.isCaptured is always false in simulator — use simulated value
                self.isCapturing = self.simulatedIsCapturing
                #else
                self.isCapturing = UIScreen.main.isCaptured
                #endif
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.screenshotTaken.send() }
            .store(in: &cancellables)
    }

    func simulateScreenshot() {
        screenshotTaken.send()
    }
}
