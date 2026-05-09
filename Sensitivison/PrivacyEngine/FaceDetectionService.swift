import AVFoundation
import Vision
import Combine

final class FaceDetectionService: NSObject, ObservableObject {
    @Published private(set) var faceCount: Int = 0

    // Simulator / testing override — setting this bypasses camera entirely
    var simulatedFaceCount: Int = 0 {
        didSet {
            DispatchQueue.main.async { self.faceCount = self.simulatedFaceCount }
        }
    }

    #if !targetEnvironment(simulator)
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.sensitivison.face-detection", qos: .userInitiated)
    private let sequenceHandler = VNSequenceRequestHandler()

    func start() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { session.commitConfiguration(); return }
        session.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        session.commitConfiguration()
    }
    #else
    func start() {}
    func stop() {}
    #endif
}

#if !targetEnvironment(simulator)
extension FaceDetectionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            let count = request.results?.count ?? 0
            DispatchQueue.main.async { self?.faceCount = count }
        }
        try? sequenceHandler.perform([request], on: pixelBuffer, orientation: .leftMirrored)
    }
}
#endif
