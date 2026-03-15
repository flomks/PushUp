import AVFoundation
import SwiftUI

// MARK: - QRScannerView

/// Full-screen QR code scanner using AVFoundation.
///
/// Delivers the first valid friend code via `onCode`, then stops scanning.
/// `onCancel` is called when the user taps the X button.
struct QRScannerView: View {

    let onCode: (String) -> Void
    let onCancel: () -> Void

    @StateObject private var coordinator = QRScannerCoordinator()
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            if permissionDenied {
                permissionDeniedView
            } else {
                CameraPreviewLayer(session: coordinator.session)
                    .ignoresSafeArea()

                ViewfinderOverlay()
                    .ignoresSafeArea()
            }

            // Cancel button — always on top
            VStack {
                HStack {
                    Spacer()
                    Button {
                        coordinator.stop()
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
            startScanning()
        }
        .onDisappear {
            coordinator.stop()
        }
    }

    // MARK: - Start scanning

    private func startScanning() {
        coordinator.onCode = { raw in
            let code = extractCode(from: raw)
            guard !code.isEmpty else { return }
            coordinator.stop()
            onCode(code)
        }
        coordinator.checkPermissionAndStart { denied in
            permissionDenied = denied
        }
    }

    // MARK: - Permission denied view

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
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
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

    /// Accepts `pushup://friend-code/AB3X7K2M` or a bare alphanumeric code.
    private func extractCode(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed),
           url.scheme == "pushup",
           url.host == "friend-code" {
            return url.pathComponents
                .filter { $0 != "/" }
                .first?
                .uppercased() ?? ""
        }

        let bare = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        guard bare.count >= 4, bare.count <= 16 else { return "" }
        return bare
    }
}

// MARK: - ViewfinderOverlay

/// Dimmed surround with a transparent square cutout, white border, and label.
/// Built with four coloured rectangles so it works on every iOS version
/// without Canvas or blendMode tricks.
private struct ViewfinderOverlay: View {

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height) * 0.65
            let cx = geo.size.width  / 2
            let cy = geo.size.height / 2
            let top    = cy - side / 2
            let bottom = cy + side / 2
            let left   = cx - side / 2
            let right  = cx + side / 2

            ZStack {
                // Four dim panels around the cutout
                Color.black.opacity(0.55)
                    .frame(width: geo.size.width, height: top)
                    .position(x: cx, y: top / 2)

                Color.black.opacity(0.55)
                    .frame(width: geo.size.width, height: geo.size.height - bottom)
                    .position(x: cx, y: bottom + (geo.size.height - bottom) / 2)

                Color.black.opacity(0.55)
                    .frame(width: left, height: side)
                    .position(x: left / 2, y: cy)

                Color.black.opacity(0.55)
                    .frame(width: geo.size.width - right, height: side)
                    .position(x: right + (geo.size.width - right) / 2, y: cy)

                // White border frame
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: side, height: side)
                    .position(x: cx, y: cy)

                // Instruction label below the frame
                Text("Point at a friend's QR code")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
                    .position(x: cx, y: bottom + AppSpacing.lg + 10)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - CameraPreviewLayer

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

final class QRScannerCoordinator: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {

    let session = AVCaptureSession()
    var onCode: ((String) -> Void)?

    private var hasDelivered = false
    private let sessionQueue = DispatchQueue(label: "com.pushup.qrscanner", qos: .userInitiated)

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

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

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
