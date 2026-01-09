import AVFoundation
import UIKit
import Vision

enum LightMode: String, CaseIterable {
    case auto = "Auto"
    case on = "On"
    case off = "Off"
}

enum CaptureMode: String, CaseIterable {
    case auto = "Auto"
    case manual = "Manual"
}

class CameraManager: NSObject, ObservableObject {
    @Published var detectedRectangle: VNRectangleObservation?
    @Published var isCapturing = false
    @Published var capturedImage: UIImage?
    @Published var error: CameraError?
    @Published var lightMode: LightMode = .off

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.scanner.processing", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "com.scanner.session")
    private var cameraDevice: AVCaptureDevice?
    private var isConfiguring = false

    private var rectangleDetectionRequest: VNDetectRectanglesRequest?
    private var lastDetectionTime = Date()
    private let detectionInterval: TimeInterval = 0.1 // 10 fps for detection

    enum CameraError: Error, LocalizedError {
        case cameraUnavailable
        case cannotAddInput
        case cannotAddOutput
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable: return "Camera is not available"
            case .cannotAddInput: return "Cannot add camera input"
            case .cannotAddOutput: return "Cannot add camera output"
            case .permissionDenied: return "Camera permission denied"
            }
        }
    }

    override init() {
        super.init()
        setupRectangleDetection()
    }

    // MARK: - Setup

    func setupCamera() {
        checkPermissions { [weak self] granted in
            guard granted else {
                DispatchQueue.main.async {
                    self?.error = .permissionDenied
                }
                return
            }
            self?.configureSession()
        }
    }

    private func checkPermissions(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.isConfiguring = true
            defer { self.isConfiguring = false }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Add camera input
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                DispatchQueue.main.async { self.error = .cameraUnavailable }
                self.session.commitConfiguration()
                return
            }

            guard self.session.canAddInput(input) else {
                DispatchQueue.main.async { self.error = .cannotAddInput }
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.cameraDevice = camera

            // Configure camera for document scanning
            try? camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()

            // Add photo output
            guard self.session.canAddOutput(self.photoOutput) else {
                DispatchQueue.main.async { self.error = .cannotAddOutput }
                self.session.commitConfiguration()
                return
            }
            self.session.addOutput(self.photoOutput)
            self.photoOutput.isHighResolutionCaptureEnabled = true

            // Add video output for live edge detection
            self.videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addOutput(self.videoOutput)

            // Set video orientation
            if let connection = self.videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
            }

            self.session.commitConfiguration()
        }
    }

    private func setupRectangleDetection() {
        rectangleDetectionRequest = VNDetectRectanglesRequest { [weak self] request, error in
            guard error == nil,
                  let results = request.results as? [VNRectangleObservation],
                  let rect = results.first else {
                DispatchQueue.main.async {
                    self?.detectedRectangle = nil
                }
                return
            }

            DispatchQueue.main.async {
                self?.detectedRectangle = rect
            }
        }

        rectangleDetectionRequest?.minimumAspectRatio = 0.3
        rectangleDetectionRequest?.maximumAspectRatio = 1.0
        rectangleDetectionRequest?.minimumSize = 0.2
        rectangleDetectionRequest?.maximumObservations = 1
        rectangleDetectionRequest?.minimumConfidence = 0.6
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        setTorchMode(.off)
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Torch Control

    func setTorchMode(_ mode: LightMode) {
        guard let device = cameraDevice, device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            switch mode {
            case .on:
                if device.isTorchModeSupported(.on) {
                    device.torchMode = .on
                }
            case .off:
                device.torchMode = .off
            case .auto:
                if device.isTorchModeSupported(.auto) {
                    device.torchMode = .auto
                }
            }
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self.lightMode = mode
            }
        } catch {
            print("Torch control error: \(error)")
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        guard !isCapturing else { return }

        DispatchQueue.main.async {
            self.isCapturing = true
        }

        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Helpers

    func convertToImageCoordinates(_ point: CGPoint, in viewSize: CGSize) -> CGPoint {
        // Vision coordinates are normalized (0-1) with origin at bottom-left
        // Convert to view coordinates with origin at top-left
        return CGPoint(
            x: point.x * viewSize.width,
            y: (1 - point.y) * viewSize.height
        )
    }

    func getCornerPoints(for observation: VNRectangleObservation, in viewSize: CGSize) -> [CGPoint] {
        return [
            convertToImageCoordinates(observation.topLeft, in: viewSize),
            convertToImageCoordinates(observation.topRight, in: viewSize),
            convertToImageCoordinates(observation.bottomRight, in: viewSize),
            convertToImageCoordinates(observation.bottomLeft, in: viewSize)
        ]
    }
}

// MARK: - Video Sample Buffer Delegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle detection
        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= detectionInterval else { return }
        lastDetectionTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let request = rectangleDetectionRequest else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - Photo Capture Delegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async {
            self.isCapturing = false
        }

        guard error == nil,
              let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }

        // Fix orientation and resize to reduce memory usage
        // 2400px is sufficient for A4 at 300 DPI
        let fixedImage = image.fixedOrientation().resized(maxDimension: 2400)

        DispatchQueue.main.async {
            self.capturedImage = fixedImage
        }
    }
}

// MARK: - UIImage Orientation Fix

extension UIImage {
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Resize image to fit within maxDimension while preserving aspect ratio
    func resized(maxDimension: CGFloat) -> UIImage {
        let aspectRatio = size.width / size.height
        var newSize: CGSize

        if size.width > size.height {
            if size.width <= maxDimension { return self }
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            if size.height <= maxDimension { return self }
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
