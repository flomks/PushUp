import AVFoundation
import SwiftUI
import UIKit

// MARK: - CameraPreviewView

/// A SwiftUI view that renders the live camera feed from a `CameraManager`.
///
/// The view attaches the manager's `previewLayer` to a backing `UIView` and
/// keeps it sized to fill the available space on every layout pass.
///
/// **Usage**
/// ```swift
/// @StateObject private var camera = CameraManager()
///
/// var body: some View {
///     CameraPreviewView(cameraManager: camera)
///         .ignoresSafeArea()
///         .onAppear  { camera.setupAndStart() }
///         .onDisappear { camera.stopSession() }
/// }
/// ```
struct CameraPreviewView: UIViewRepresentable {

    let cameraManager: CameraManager

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.setPreviewLayer(cameraManager.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // The preview layer is permanently attached; frame updates happen in
        // `layoutSubviews`. Nothing to do here.
    }
}

// MARK: - PreviewUIView

/// A `UIView` that hosts an `AVCaptureVideoPreviewLayer` as its primary sublayer
/// and keeps it sized to fill the view's bounds on every layout pass.
final class PreviewUIView: UIView {

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = layer
        self.layer.insertSublayer(layer, at: 0)
        layer.frame = bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - CameraUnavailableView

/// Displayed in place of the camera preview when the camera cannot be used --
/// for example when permission is denied or the device has no camera (Simulator).
struct CameraUnavailableView: View {

    let error: CameraError

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.6))

                Text(error.errorDescription ?? "Camera unavailable")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if case .permissionDenied = error {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Color.black)
                }
            }
        }
    }

    private var iconName: String {
        switch error {
        case .permissionDenied, .permissionRestricted:
            return "camera.fill.badge.ellipsis"
        case .deviceNotAvailable:
            return "camera.slash.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - CameraContainerView

/// A ready-to-use SwiftUI container that owns a `CameraManager` and wires
/// everything together:
/// - Shows the live preview when the session is running.
/// - Shows `CameraUnavailableView` on any error.
/// - Provides a camera-flip button overlay.
/// - Forwards `CMSampleBuffer` frames to an optional closure for downstream
///   processing (e.g. pose detection in Task 2.2).
///
/// **Usage**
/// ```swift
/// CameraContainerView { sampleBuffer in
///     poseDetector.process(sampleBuffer)
/// }
/// ```
struct CameraContainerView: View {

    /// Optional closure called on the video output queue for every captured frame.
    /// Keep implementations non-blocking; dispatch heavy work to a background queue.
    ///
    /// Marked `@Sendable` because it is invoked on the video output queue but
    /// captured from the main-queue SwiftUI context.
    var onSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    @StateObject private var cameraManager = CameraManager()

    /// Strong reference that keeps the delegate alive for the lifetime of this view.
    /// `CameraManager.delegate` is `weak`, so the owner must hold a strong ref.
    @State private var sampleBufferHandler: SampleBufferHandler?

    var body: some View {
        ZStack {
            cameraContent
            overlayControls
        }
        .onAppear {
            attachDelegate()
            cameraManager.setupAndStart()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: onSampleBuffer != nil) { _, _ in
            // Re-attach whenever the closure presence changes.
            attachDelegate()
        }
    }

    // MARK: Private

    private func attachDelegate() {
        if let handler: @Sendable (CMSampleBuffer) -> Void = onSampleBuffer {
            let wrapper = SampleBufferHandler(handler: handler)
            sampleBufferHandler = wrapper      // strong ref kept in @State
            cameraManager.delegate = wrapper   // weak ref in CameraManager
        } else {
            sampleBufferHandler = nil
            cameraManager.delegate = nil
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
        switch cameraManager.state {
        case .idle, .running, .stopped:
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()
        case .error(let error):
            CameraUnavailableView(error: error)
        }
    }

    private var overlayControls: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    cameraManager.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Switch camera")
                .padding(.trailing, 16)
                .padding(.top, 16)
            }
            Spacer()
        }
    }
}

// MARK: - SampleBufferHandler

/// Bridges `CameraManagerDelegate` to a Swift closure.
///
/// **Ownership:** `CameraContainerView` holds a strong reference via `@State`.
/// `CameraManager.delegate` holds only a `weak` reference, so this object's
/// lifetime is controlled entirely by the view -- no retain cycle possible.
///
/// Conforms to `@unchecked Sendable` because the stored closure is `@Sendable`
/// and the class has no mutable state after initialisation.
final class SampleBufferHandler: CameraManagerDelegate, @unchecked Sendable {

    private let handler: @Sendable (CMSampleBuffer) -> Void

    init(handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        handler(sampleBuffer)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Camera Unavailable") {
    CameraUnavailableView(error: .deviceNotAvailable)
}

#Preview("Permission Denied") {
    CameraUnavailableView(error: .permissionDenied)
}
#endif
