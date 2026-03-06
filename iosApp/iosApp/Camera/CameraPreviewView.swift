import AVFoundation
import SwiftUI
import UIKit

// MARK: - CameraPreviewView

/// A SwiftUI view that renders the live camera feed from a `CameraManager`.
///
/// Usage:
/// ```swift
/// @StateObject private var cameraManager = CameraManager()
///
/// var body: some View {
///     CameraPreviewView(cameraManager: cameraManager)
///         .ignoresSafeArea()
///         .onAppear { cameraManager.setupAndStart() }
///         .onDisappear { cameraManager.stopSession() }
/// }
/// ```
struct CameraPreviewView: UIViewRepresentable {

    let cameraManager: CameraManager

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        if let layer = cameraManager.previewLayer {
            view.setPreviewLayer(layer)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // The preview layer is already attached; layout is handled in layoutSubviews.
    }
}

// MARK: - PreviewUIView

/// A UIView subclass that hosts an `AVCaptureVideoPreviewLayer` and keeps it
/// sized to fill the view's bounds on every layout pass.
final class PreviewUIView: UIView {

    private var previewLayer: AVCaptureVideoPreviewLayer?

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        // Remove any previously attached layer
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

/// Shown in place of the camera preview when the camera is unavailable
/// (e.g. permission denied, simulator, or hardware error).
struct CameraUnavailableView: View {

    let error: CameraError

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.6))

                Text(error.errorDescription ?? "Camera unavailable")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if case .permissionDenied = error {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundColor(.black)
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

/// A convenience SwiftUI container that:
/// - Shows the live camera preview when running
/// - Shows `CameraUnavailableView` on error
/// - Exposes a camera-switch button overlay
///
/// This is the primary view to embed in your workout screen.
struct CameraContainerView: View {

    @StateObject private var cameraManager = CameraManager()
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    var body: some View {
        ZStack {
            cameraContent
            overlayControls
        }
        .onAppear {
            cameraManager.setupAndStart()
            if let handler = onSampleBuffer {
                cameraManager.delegate = SampleBufferHandler(handler: handler)
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }

    // MARK: Private views

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
                Button(action: { cameraManager.switchCamera() }) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
            }
            Spacer()
        }
    }
}

// MARK: - SampleBufferHandler (bridge for closure-based delegate)

/// A lightweight `CameraManagerDelegate` that forwards sample buffers
/// to a Swift closure, avoiding the need for the caller to implement the protocol.
private final class SampleBufferHandler: CameraManagerDelegate {
    let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        handler(sampleBuffer)
    }
}

// MARK: - Previews

#if DEBUG
struct CameraPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        // The simulator has no camera, so we show the unavailable state.
        CameraUnavailableView(error: .deviceNotAvailable)
            .previewDisplayName("Camera Unavailable")

        CameraUnavailableView(error: .permissionDenied)
            .previewDisplayName("Permission Denied")
    }
}
#endif
