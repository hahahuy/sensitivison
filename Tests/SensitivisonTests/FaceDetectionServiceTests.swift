import XCTest
import Combine
@testable import Sensitivison

final class FaceDetectionServiceTests: XCTestCase {
    var service: FaceDetectionService!
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        service = FaceDetectionService()
    }

    func test_initial_face_count_is_zero() {
        XCTAssertEqual(service.faceCount, 0)
    }

    func test_simulated_face_count_updates_published_value() {
        let expectation = expectation(description: "faceCount updates")
        service.$faceCount
            .dropFirst()
            .sink { count in
                XCTAssertEqual(count, 2)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        service.simulatedFaceCount = 2
        wait(for: [expectation], timeout: 1.0)
    }

    func test_simulated_face_count_zero() {
        service.simulatedFaceCount = 3
        service.simulatedFaceCount = 0
        XCTAssertEqual(service.faceCount, 0)
    }
}
