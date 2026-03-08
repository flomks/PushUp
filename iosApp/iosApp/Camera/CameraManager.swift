import AVFoundation
import UIKit

// MARK: - CameraPosition

enum CameraPosition: Sendable {
    case front
    case back

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: return .front
        case .back:  return .back
        }
    }

    var toggled: CameraPosition {
        self == .back ? .front : .back
    }
}

// MARK: - CameraError

enum CameraError: LocalizedError, Equatable, Sendable {
    case permissionDenied
    case permissionRestricted
    case deviceNotAvailable
    case inputConfigurationFailed
    case outputConfigurationFailed

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
        }
    }
}

// MARK: - CameraState

enum CameraState: Equatable, Sendable {
    case idle
    case running
    case stopped
    case error(CameraError)
}

// MARK: - CameraManagerDelegate

/// Receives raw video frames on a dedicated high-priority serial queue.
/// Implementations must be non-blocking; heavy work should be dispatched elsewhere.
///
/// Marked `Sendable` because instances are set from the main queue and called
/// from the video output queue.
protocol CameraManagerDelegate: AnyObject, Sendable {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
}

// MARK: - CameraManager

/// Manages an `AVCaptureSession` that delivers 30 FPS `CMSampleBuffer` frames
/// via `CameraManagerDelegate`. Supports front/back camera switching and
/// automatic session suspension when the app enters the background.
///
/// **Threading model**
/// - All AVFoundation mutations run on `sessionQueue` (serial).
/// - `@Published` state is always updated on the main queue.
/// - `delegate` callbacks arrive on `videoOutputQueue` (serial, `.userInteractive`).
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var state: CameraState = .idle
    @Published private(set) var currentPosition: CameraPosition = .back

    /// Current zoom factor applied to the active capture device.
    /// Always starts at 1.0 (fully zoomed out) and resets on camera switch.
    @Published private(set) var currentZoomFactor: CGFloat = 1.0

    /// The preview layer backed by the capture session.
    /// Created once in `init`; never nil, never replaced.
    let previewLayer: AVCaptureVideoPreviewLayer

    // MARK: - Private session objects

    private let session = AVCaptureSession()

    /// Serial queue for all AVFoundation configuration and lifecycle calls.
    private let sessionQueue = DispatchQueue(
        label: "com.pushup.camera.session",
        qos: .userInitiated
    )

    /// High-priority serial queue for sample buffer delivery.
    /// `.userInteractive` ensures Vision/ML processing gets CPU time within the 33 ms frame budget.
    private let videoOutputQueue = DispatchQueue(
        label: "com.pushup.camera.videoOutput",
        qos: .userInteractive
    )

    private var currentInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()

    // MARK: - Delegate (thread-safe access)

    /// Protected by `delegateLock` so it can be set on any thread and read
    /// safely from `videoOutputQueue` inside `captureOutput`.
    private let delegateLock = NSLock()
    private weak var _delegate: CameraManagerDelegate?

    var delegate: CameraManagerDelegate? {
        get {
            delegateLock.lock()
            defer { delegateLock.unlock() }
            return _delegate
        }
        set {
            delegateLock.lock()
            defer { delegateLock.unlock() }
            _delegate = newValue
        }
    }

    // MARK: - Position lock

    /// Protects `_currentPositionInternal` for safe cross-queue reads.
    /// The `@Published currentPosition` is only written on the main queue,
    /// but `switchCamera()` needs to read the current position from `sessionQueue`.
    private let positionLock = NSLock()
    private var _currentPositionInternal: CameraPosition = .back

    // MARK: - Background observation tokens

    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    // MARK: - Init / Deinit

    override init() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        super.init()
        subscribeToAppLifecycle()
    }

    deinit {
        if let token = backgroundObserver { NotificationCenter.default.removeObserver(token) }
        if let token = foregroundObserver { NotificationCenter.default.removeObserver(token) }
    }

    // MARK: - App Lifecycle

    private func subscribeToAppLifecycle() {
        // Use `queue: .main` to ensure `@Published` state is read/written
        // exclusively on the main queue, preventing data races.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopSession()
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Only restart if we were actively running before backgrounding.
            guard let self, case .running = self.state else { return }
            self.startSession()
        }
    }

    // MARK: - Permission

    /// Checks authorisation status and requests access when undetermined.
    /// The completion closure is always called on the **main queue**.
    func requestPermission(completion: @escaping (Result<Void, CameraError>) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { completion(.success(())) }

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted ? .success(()) : .failure(.permissionDenied))
                }
            }

        case .denied:
            DispatchQueue.main.async { completion(.failure(.permissionDenied)) }

        case .restricted:
            DispatchQueue.main.async { completion(.failure(.permissionRestricted)) }

        @unknown default:
            DispatchQueue.main.async { completion(.failure(.permissionDenied)) }
        }
    }

    // MARK: - Public API

    /// Requests permission, configures the session for `position`, and starts it.
    /// All errors are surfaced via the `state` published property.
    func setupAndStart(position: CameraPosition = .back) {
        requestPermission { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.sessionQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        try self.configureSession(position: position)
                        self.session.startRunning()
                        self.updatePosition(position)
                        DispatchQueue.main.async {
                            self.currentPosition = position
                            self.currentZoomFactor = 1.0
                            self.state = .running
                        }
                    } catch let error as CameraError {
                        DispatchQueue.main.async { self.state = .error(error) }
                    } catch {
                        DispatchQueue.main.async { self.state = .error(.inputConfigurationFailed) }
                    }
                }
            case .failure(let error):
                // Already on main queue (requestPermission guarantees this).
                self.state = .error(error)
            }
        }
    }

    /// Starts the capture session. No-op if already running.
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .running }
        }
    }

    /// Stops the capture session. No-op if already stopped.
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.state = .stopped }
        }
    }

    /// Atomically swaps the active camera input to the opposite lens.
    /// The session continues running without interruption on supported hardware.
    func switchCamera() {
        // Read the current position under lock so it is safe to call from
        // any queue. The `@Published currentPosition` is only written on
        // the main queue, but we may be called before it updates.
        let current = readPosition()
        let newPosition = current.toggled

        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Capture running state before reconfiguration (beginConfiguration
            // may implicitly pause delivery on some devices).
            let wasRunning = self.session.isRunning
            do {
                try self.configureSession(position: newPosition)
                if wasRunning && !self.session.isRunning {
                    self.session.startRunning()
                }
                self.updatePosition(newPosition)
                DispatchQueue.main.async {
                    self.currentPosition = newPosition
                    self.currentZoomFactor = 1.0
                }
            } catch let error as CameraError {
                DispatchQueue.main.async { self.state = .error(error) }
            } catch {
                DispatchQueue.main.async { self.state = .error(.inputConfigurationFailed) }
            }
        }
    }

    // MARK: - Zoom

    /// Sets the zoom factor on the active capture device.
    ///
    /// The value is clamped to `[1.0, device.activeFormat.videoMaxZoomFactor]`
    /// so callers do not need to guard against out-of-range values.
    /// This method is safe to call from any queue.
    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let input = self.currentInput else { return }
            let device = input.device
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            let clamped = max(1.0, min(factor, maxZoom))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                #if DEBUG
                print("[CameraManager] Zoom configuration failed: \(error)")
                #endif
                return
            }
            DispatchQueue.main.async { self.currentZoomFactor = clamped }
        }
    }

    /// Resets the zoom to 1.0x (fully zoomed out) on the active device.
    func resetZoom() {
        setZoomFactor(1.0)
    }

    // MARK: - Position Helpers (thread-safe)

    private func readPosition() -> CameraPosition {
        positionLock.lock()
        defer { positionLock.unlock() }
        return _currentPositionInternal
    }

    private func updatePosition(_ position: CameraPosition) {
        positionLock.lock()
        defer { positionLock.unlock() }
        _currentPositionInternal = position
    }

    // MARK: - Session Configuration (must run on sessionQueue)

    private func configureSession(position: CameraPosition) throws {
        session.beginConfiguration()
        // commitConfiguration is always called, even on early throw.
        defer { session.commitConfiguration() }

        // 720p is sufficient for VNDetectHumanBodyPoseRequest and reduces
        // memory bandwidth / thermal load compared to `.high`.
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        // --- Input ---
        session.inputs.forEach { session.removeInput($0) }

        let device = try captureDevice(for: position)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.inputConfigurationFailed
        }
        session.addInput(input)
        currentInput = input

        // Lock 30 FPS before committing so the preset and frame rate are
        // applied atomically within the same beginConfiguration block.
        configureFrameRate(device: device, targetFPS: 30)

        // --- Output ---
        session.outputs.forEach { session.removeOutput($0) }

        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // YCbCr 4:2:0 full-range: optimal for VNDetectHumanBodyPoseRequest.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        guard session.canAddOutput(videoOutput) else {
            throw CameraError.outputConfigurationFailed
        }
        session.addOutput(videoOutput)

        // --- Connection orientation & mirroring ---
        if let connection = videoOutput.connection(with: .video) {
            // Rotate to portrait. `videoRotationAngle` is iOS 17+; fall back
            // to `videoOrientation` on iOS 16.
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            if position == .front,
               connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
    }

    // MARK: - Frame Rate

    /// Locks the device to `targetFPS` by selecting the highest-resolution
    /// format that supports the requested rate, then clamping min/max durations.
    /// Best-effort: silently falls back to the device default if no matching
    /// format exists.
    private func configureFrameRate(device: AVCaptureDevice, targetFPS: Int) {
        let targetRate = Double(targetFPS)
        let targetDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))

        // Prefer the current active format if it already supports the target FPS,
        // otherwise find the highest-resolution format that does.
        let candidateFormat: AVCaptureDevice.Format? = {
            let supports: (AVCaptureDevice.Format) -> Bool = { format in
                format.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= targetRate && targetRate <= $0.maxFrameRate
                }
            }
            if supports(device.activeFormat) { return device.activeFormat }
            return device.formats
                .filter(supports)
                .max {
                    let dimA = $0.formatDescription.dimensions
                    let dimB = $1.formatDescription.dimensions
                    return Int(dimA.width) * Int(dimA.height) < Int(dimB.width) * Int(dimB.height)
                }
        }()

        guard let format = candidateFormat else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.activeFormat = format
            device.activeVideoMinFrameDuration = targetDuration
            device.activeVideoMaxFrameDuration = targetDuration
        } catch {
            #if DEBUG
            print("[CameraManager] Frame rate configuration failed: \(error)")
            #endif
        }
    }

    // MARK: - Device Discovery

    private func captureDevice(for position: CameraPosition) throws -> AVCaptureDevice {
        // Ordered by preference: multi-lens systems first for best quality.
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position.avPosition
        )

        guard let device = discovery.devices.first else {
            throw CameraError.deviceNotAvailable
        }
        return device
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Capture a strong reference for the duration of the call to prevent
        // deallocation between the nil-check and the method invocation.
        let currentDelegate = delegate
        currentDelegate?.cameraManager(self, didOutput: sampleBuffer)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Late frames are discarded intentionally (`alwaysDiscardsLateVideoFrames = true`).
        // Log in debug builds only to avoid performance overhead in production.
        #if DEBUG
        var mode: CMAttachmentMode = 0
        if let reason = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_DroppedFrameReason,
            attachmentModeOut: &mode
        ) {
            _ = reason // Available for breakpoint inspection.
        }
        #endif
    }
}
