import XCTest
import Combine
@testable import Sensitivison

@MainActor
final class PrivacyEngineTests: XCTestCase {
    var engine: PrivacyEngine!
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        engine = PrivacyEngine()
    }

    func test_no_threat_initially() {
        XCTAssertFalse(engine.threatActive)
        XCTAssertNil(engine.threatReason)
    }

    func test_extra_face_triggers_threat() {
        let expectation = expectation(description: "threat activates")
        engine.$threatActive
            .dropFirst()
            .sink { active in
                if active { expectation.fulfill() }
            }
            .store(in: &cancellables)
        engine.faceDetectionService.simulatedFaceCount = 2
        wait(for: [expectation], timeout: 2.0)  // accounts for 0.5s debounce
    }

    func test_single_face_no_threat() {
        engine.faceDetectionService.simulatedFaceCount = 2
        engine.faceDetectionService.simulatedFaceCount = 1
        let expectation = expectation(description: "no threat")
        expectation.isInverted = true
        engine.$threatActive
            .dropFirst()
            .filter { $0 }
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)
    }

    func test_screen_capture_triggers_threat() {
        let expectation = expectation(description: "capture threat")
        engine.$threatActive
            .dropFirst()
            .filter { $0 }
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        engine.screenCaptureService.simulatedIsCapturing = true
        wait(for: [expectation], timeout: 1.0)
    }

    func test_threat_reason_is_face_when_face_detected() {
        engine.faceDetectionService.simulatedFaceCount = 2
        let expectation = expectation(description: "reason set")
        engine.$threatReason
            .compactMap { $0 }
            .sink { reason in
                XCTAssertEqual(reason, .faceDetected)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 2.0)
    }
}
