import AVFoundation
import Combine
import UIKit

// MARK: - Camera Position

enum CameraPosition {
    case front
    case back

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: return .front
        case .back:  return .back
        }
    }
}

// MARK: - Camera Error

enum CameraError: LocalizedError {
    case permissionDenied
    case permissionRestricted
    case deviceNotAvailable
    case inputConfigurationFailed
    case outputConfigurationFailed
    case sessionStartFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access was denied. Please enable it in Settings."
        case .permissionRestricted:
            return "Camera access is restricted on this device."
        case .deviceNotAvailable:
            return "No camera is available on this device."
        case .inputConfigurationFailed:
            return "Failed to configure the camera input."
        case .outputConfigurationFailed:
            return "Failed to configure the camera output."
        case .sessionStartFailed:
            return "Failed to start the camera session."
        }
    }
}

// MARK: - Camera State

enum CameraState {
    case idle
    case running
    case stopped
    case error(CameraError)
}

// MARK: - Sample Buffer Delegate Protocol

protocol CameraManagerDelegate: AnyObject {
    /// Called on the session queue for every captured video frame.
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
}

// MARK: - CameraManager

/// Manages an AVCaptureSession that delivers 30 FPS CMSampleBuffer frames
/// via `CameraManagerDelegate`. Supports front/back camera switching.
final class CameraManager: NSObject, ObservableObject {

    // MARK: Published state

    @Published private(set) var state: CameraState = .idle
    @Published private(set) var currentPosition: CameraPosition = .back
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: Internal session objects

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(
        label: "com.pushup.camera.sessionQueue",
        qos: .userInitiated
    )
    private let videoOutputQueue = DispatchQueue(
        label: "com.pushup.camera.videoOutputQueue",
        qos: .userInitiated
    )

    private var currentInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()

    weak var delegate: CameraManagerDelegate?

    // MARK: - Initialisation

    override init() {
        super.init()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
    }

    // MARK: - Permission

    /// Checks the current authorisation status and requests access if needed.
    /// Calls `completion` on the main queue with the result.
    func requestPermission(completion: @escaping (Result<Void, CameraError>) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(.success(()))

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        completion(.success(()))
                    } else {
                        completion(.failure(.permissionDenied))
                    }
                }
            }

        case .denied:
            completion(.failure(.permissionDenied))

        case .restricted:
            completion(.failure(.permissionRestricted))

        @unknown default:
            completion(.failure(.permissionDenied))
        }
    }

    // MARK: - Setup

    /// Configures the session for the given camera position.
    /// Must be called after permission is granted.
    func configure(position: CameraPosition = .back) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureSession(position: position)
                DispatchQueue.main.async {
                    self.currentPosition = position
                }
            } catch let error as CameraError {
                DispatchQueue.main.async {
                    self.state = .error(error)
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .error(.inputConfigurationFailed)
                }
            }
        }
    }

    private func configureSession(position: CameraPosition) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Preset: high quality, supports 30 FPS on all modern iPhones
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        // Remove existing inputs
        session.inputs.forEach { session.removeInput($0) }

        // Add new video input
        let device = try captureDevice(for: position)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.inputConfigurationFailed
        }
        session.addInput(input)
        currentInput = input

        // Configure 30 FPS on the device
        try configureFrameRate(device: device, fps: 30)

        // Remove existing outputs
        session.outputs.forEach { session.removeOutput($0) }

        // Add video data output
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        guard session.canAddOutput(videoOutput) else {
            throw CameraError.outputConfigurationFailed
        }
        session.addOutput(videoOutput)

        // Set video orientation to portrait
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            // Mirror front camera
            if position == .front {
                connection.isVideoMirrored = true
            }
        }
    }

    // MARK: - Frame Rate

    private func configureFrameRate(device: AVCaptureDevice, fps: Int) throws {
        let targetFPS = CMTime(value: 1, timescale: CMTimeScale(fps))

        // Find a format that supports the target FPS
        let supportedFormat = device.formats.first { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= Double(fps) && Double(fps) <= range.maxFrameRate
            }
        }

        guard let format = supportedFormat else { return }

        try device.lockForConfiguration()
        device.activeFormat = format
        device.activeVideoMinFrameDuration = targetFPS
        device.activeVideoMaxFrameDuration = targetFPS
        device.unlockForConfiguration()
    }

    // MARK: - Session Lifecycle

    /// Starts the capture session. Safe to call multiple times.
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.state = .running
            }
        }
    }

    /// Stops the capture session. Safe to call multiple times.
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.state = .stopped
            }
        }
    }

    // MARK: - Camera Switching

    /// Switches between front and back camera.
    func switchCamera() {
        let newPosition: CameraPosition = currentPosition == .back ? .front : .back
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureSession(position: newPosition)
                DispatchQueue.main.async {
                    self.currentPosition = newPosition
                }
                // Restart session if it was running
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            } catch let error as CameraError {
                DispatchQueue.main.async {
                    self.state = .error(error)
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .error(.inputConfigurationFailed)
                }
            }
        }
    }

    // MARK: - Helpers

    private func captureDevice(for position: CameraPosition) throws -> AVCaptureDevice {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position.avPosition
        )

        guard let device = discoverySession.devices.first else {
            throw CameraError.deviceNotAvailable
        }
        return device
    }

    // MARK: - Full Setup Convenience

    /// Requests permission, configures the session, and starts it.
    /// Reports errors via the `state` published property.
    func setupAndStart(position: CameraPosition = .back) {
        requestPermission { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                // Run configure + start serially on the session queue so that
                // startRunning() is guaranteed to execute after configuration.
                self.sessionQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        try self.configureSession(position: position)
                        DispatchQueue.main.async { self.currentPosition = position }
                        self.session.startRunning()
                        DispatchQueue.main.async { self.state = .running }
                    } catch let error as CameraError {
                        DispatchQueue.main.async { self.state = .error(error) }
                    } catch {
                        DispatchQueue.main.async { self.state = .error(.inputConfigurationFailed) }
                    }
                }
            case .failure(let error):
                self.state = .error(error)
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Frames are dropped when processing is too slow; this is expected behaviour.
    }
}
