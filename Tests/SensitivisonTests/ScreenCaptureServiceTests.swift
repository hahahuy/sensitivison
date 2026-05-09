import XCTest
import Combine
@testable import Sensitivison

@MainActor
final class ScreenCaptureServiceTests: XCTestCase {
    var service: ScreenCaptureService!
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        service = ScreenCaptureService()
    }

    func test_initial_state_not_capturing() {
        XCTAssertFalse(service.isCapturing)
    }

    func test_simulated_capture_toggle() {
        service.simulatedIsCapturing = true
        XCTAssertTrue(service.isCapturing)
        service.simulatedIsCapturing = false
        XCTAssertFalse(service.isCapturing)
    }

    func test_screenshot_publisher_fires() {
        let expectation = expectation(description: "screenshotTaken fires")
        service.screenshotTaken
            .sink { expectation.fulfill() }
            .store(in: &cancellables)
        service.simulateScreenshot()
        wait(for: [expectation], timeout: 1.0)
    }
}
