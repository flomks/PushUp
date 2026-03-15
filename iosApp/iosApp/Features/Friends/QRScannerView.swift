import AVFoundation
import SwiftUI

// MARK: - QRScannerView

/// Full-screen QR code scanner using AVFoundation.
///
/// Calls `onCode` exactly once with the first valid `pushup://friend-code/<CODE>`
/// deep-link or bare alphanumeric code it detects, then stops scanning.
/// Calls `onCancel` when the user taps the X button.
struct QRScannerView: View {

    let onCode: (String) -> Void
    let onCancel: () -> Void

    @StateObject private var scanner = QRScannerCoordinator()
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            if permissionDenied {
                permissionDeniedView
            } else {
                // Live camera feed
                CameraPreviewLayer(session: scanner.session)
                    .ignoresSafeArea()

                // Viewfinder overlay drawn on top
                ViewfinderOverlay()
            }

            // Cancel button pinned to top-right
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
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, AppSpacing.md)
                    .padding(.top, AppSpacing.md)
                }
                Spacer()
            }
        }
        .onAppear {
            scanner.onCode = { [self] raw in
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

    private func extractCode(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Deep-link: pushup://friend-code/AB3X7K2M
        if let url = URL(string: trimmed),
           url.scheme == "pushup",
           url.host == "friend-code" {
            let code = url.pathComponents
                .filter { $0 != "/" }
                .first?
                .uppercased() ?? ""
            return code
        }

        // Bare code: uppercase alphanumeric, 4-16 chars
        let bare = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        guard bare.count >= 4, bare.count <= 16 else { return "" }
        return bare
    }
}

// MARK: - ViewfinderOverlay

/// Draws the dimmed surround + white border frame + instruction text.
/// Uses a Canvas-based approach to avoid the deprecated mask(content:) API.
private struct ViewfinderOverlay: View {

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height) * 0.65
            let cx = geo.size.width  / 2
            let cy = geo.size.height / 2
            let rect = CGRect(
                x: cx - side / 2,
                y: cy - side / 2,
                width: side,
                height: side
            )
            let radius: CGFloat = 16

            ZStack {
                // Dimmed surround with transparent cutout via Canvas
                Canvas { ctx, size in
                    // Fill entire canvas with semi-transparent black
                    ctx.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(.black.opacity(0.55))
                    )
                    // Punch out the viewfinder rectangle using .clear blend mode
                    var cutout = Path()
                    cutout.addRoundedRect(
                        in: rect,
                        cornerSize: CGSize(width: radius, height: radius)
                    )
                    ctx.blendMode = .clear
                    ctx.fill(cutout, with: .color(.black))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // White border around the viewfinder
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: side, height: side)
                    .position(x: cx, y: cy)
                    .allowsHitTesting(false)

                // Instruction label below the viewfinder
                Text("Point at a friend's QR code")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
                    .position(x: cx, y: rect.maxY + AppSpacing.lg + 10)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - CameraPreviewLayer

/// UIViewRepresentable that hosts an AVCaptureVideoPreviewLayer.
private struct CameraPreviewLayer: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    // MARK: PreviewView

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - QRScannerCoordinator

/// Owns the AVCaptureSession and delivers decoded QR strings via `onCode`.
final class QRScannerCoordinator: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {

    let session = AVCaptureSession()
    var onCode: ((String) -> Void)?

    private var hasDelivered = false
    private let sessionQueue = DispatchQueue(
        label: "com.pushup.qrscanner.session",
        qos: .userInitiated
    )

    // MARK: Permission + start

    func checkPermissionAndStart(onDenied: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.configureAndStart() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async { self.configureAndStart() }
                } else {
                    DispatchQueue.main.async { onDenied(true) }
                }
            }
        default:
            DispatchQueue.main.async { onDenied(true) }
        }
    }

    // MARK: Session setup

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
        output.setMetadataObjectsDelegate(self, queue: sessionQueue)
        output.metadataObjectTypes = [.qr]

        session.commitConfiguration()
        session.startRunning()
    }

    // MARK: Stop

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            !hasDelivered,
            let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let raw = obj.stringValue,
            !raw.isEmpty
        else { return }

        hasDelivered = true
        DispatchQueue.main.async { self.onCode?(raw) }
    }
}
