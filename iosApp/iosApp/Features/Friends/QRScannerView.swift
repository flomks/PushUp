import AVFoundation
import SwiftUI

// MARK: - QRScannerView

/// Full-screen QR code scanner using AVFoundation.
///
/// Calls `onCode` exactly once with the first valid `pushup://friend-code/<CODE>`
/// deep-link or bare alphanumeric code it detects, then stops scanning.
/// Calls `onCancel` when the user taps the X button.
///
/// Usage:
/// ```swift
/// QRScannerView { code in
///     // code is already normalised (uppercase, trimmed)
/// } onCancel: {
///     showScanner = false
/// }
/// ```
struct QRScannerView: View {

    let onCode: (String) -> Void
    let onCancel: () -> Void

    @StateObject private var scanner = QRScannerCoordinator()
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            // Camera preview
            if permissionDenied {
                permissionDeniedView
            } else {
                CameraPreviewLayer(session: scanner.session)
                    .ignoresSafeArea()

                // Viewfinder overlay
                viewfinderOverlay
            }

            // Top bar: cancel button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        scanner.stop()
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, AppSpacing.md)
                    .padding(.top, AppSpacing.md)
                }
                Spacer()
            }
        }
        .onAppear {
            scanner.onCode = { raw in
                let code = extractCode(from: raw)
                guard !code.isEmpty else { return }
                scanner.stop()
                onCode(code)
            }
            scanner.checkPermissionAndStart { denied in
                permissionDenied = denied
            }
        }
        .onDisappear {
            scanner.stop()
        }
    }

    // MARK: - Viewfinder overlay

    private var viewfinderOverlay: some View {
        GeometryReader { geo in
            let size: CGFloat = min(geo.size.width, geo.size.height) * 0.65
            let x = (geo.size.width  - size) / 2
            let y = (geo.size.height - size) / 2

            ZStack {
                // Dimmed background with a clear cutout
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .mask(
                        Rectangle()
                            .ignoresSafeArea()
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .frame(width: size, height: size)
                                    .blendMode(.destinationOut)
                            )
                    )

                // Corner brackets
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: size, height: size)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Instruction label
                VStack(spacing: AppSpacing.xs) {
                    Spacer()
                        .frame(height: y + size + AppSpacing.lg)

                    Text("Point at a friend's QR code")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - Permission denied

    private var permissionDeniedView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                Image(systemName: "camera.slash")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))

                Text("Camera Access Required")
                    .font(AppTypography.headline)
                    .foregroundStyle(.white)

                Text("Please allow camera access in Settings to scan QR codes.")
                    .font(AppTypography.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(AppTypography.bodySemibold)
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xs)
                .background(.white.opacity(0.2), in: Capsule())
            }
        }
    }

    // MARK: - Code extraction

    /// Extracts the friend code from either a deep-link or a bare code string.
    ///
    /// Accepts:
    ///   - `pushup://friend-code/AB3X7K2M`
    ///   - `AB3X7K2M`
    private func extractCode(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Deep-link format
        if let url = URL(string: trimmed),
           url.scheme == "pushup",
           url.host == "friend-code" {
            let code = url.pathComponents
                .filter { $0 != "/" }
                .first?
                .uppercased() ?? ""
            return code
        }

        // Bare code: uppercase alphanumeric only
        let bare = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        guard bare.count >= 4, bare.count <= 16 else { return "" }
        return bare
    }
}

// MARK: - CameraPreviewLayer

/// UIViewRepresentable that hosts an `AVCaptureVideoPreviewLayer`.
private struct CameraPreviewLayer: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - QRScannerCoordinator

/// ObservableObject that owns the AVFoundation capture session and
/// delivers decoded QR strings via the `onCode` callback.
final class QRScannerCoordinator: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {

    let session = AVCaptureSession()
    var onCode: ((String) -> Void)?

    private var hasDelivered = false
    private let queue = DispatchQueue(label: "com.pushup.qrscanner", qos: .userInitiated)

    // MARK: - Permission + start

    func checkPermissionAndStart(onDenied: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.configureAndStart() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.queue.async { self.configureAndStart() }
                } else {
                    DispatchQueue.main.async { onDenied(true) }
                }
            }
        default:
            DispatchQueue.main.async { onDenied(true) }
        }
    }

    // MARK: - Session setup

    private func configureAndStart() {
        guard !session.isRunning else { return }
        session.beginConfiguration()

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: queue)
        output.metadataObjectTypes = [.qr]

        session.commitConfiguration()
        session.startRunning()
    }

    // MARK: - Stop

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            !hasDelivered,
            let obj  = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let raw  = obj.stringValue,
            !raw.isEmpty
        else { return }

        hasDelivered = true
        DispatchQueue.main.async { self.onCode?(raw) }
    }
}
