import AVFoundation
import SwiftUI
import UIKit

// MARK: - QRScannerView

/// Full-screen QR-code scanner presented as a fullScreenCover.
///
/// Calls `onCode` once with the decoded friend code, then stops.
/// Calls `onCancel` when the user taps the X button.
struct QRScannerView: UIViewControllerRepresentable {

    var onCode:   (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc      = QRScannerViewController()
        vc.onCode   = onCode
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

// MARK: - QRScannerViewController

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onCode:   ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let session      = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasDelivered = false
    private var overlayAdded = false
    private let sessionQueue = DispatchQueue(label: "com.pushup.qrscanner", qos: .userInitiated)

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addCancelButton()
        checkPermission()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let s = self, !s.session.isRunning else { return }
            s.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let s = self, s.session.isRunning else { return }
            s.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        addOverlayIfNeeded()
    }

    // MARK: Permission

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.configureSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.sessionQueue.async { self?.configureSession() }
                } else {
                    DispatchQueue.main.async { self?.showPermissionDenied() }
                }
            }
        default:
            DispatchQueue.main.async { self.showPermissionDenied() }
        }
    }

    // MARK: Session setup

    private func configureSession() {
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
        DispatchQueue.main.async { self.addPreviewLayer() }
        session.startRunning()
    }

    private func addPreviewLayer() {
        guard previewLayer == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        addOverlayIfNeeded()
    }

    private func addOverlayIfNeeded() {
        guard !overlayAdded, previewLayer != nil else { return }
        overlayAdded = true
        let overlay = QRScannerOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isUserInteractionEnabled = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: Cancel button

    private func addCancelButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
        let image  = UIImage(systemName: "xmark.circle.fill", withConfiguration: config)
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func cancelTapped() {
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
        onCancel?()
    }

    // MARK: Permission denied UI

    private func showPermissionDenied() {
        let label = UILabel()
        label.text = "Camera access is required to scan QR codes.\nPlease enable it in Settings."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .body)

        let button = UIButton(type: .system)
        button.setTitle("Open Settings", for: .normal)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.tintColor = .white
        button.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

        let code = extractCode(from: raw)
        guard !code.isEmpty else { return }
        hasDelivered = true
        session.stopRunning()
        DispatchQueue.main.async { self.onCode?(code) }
    }

    // MARK: Code extraction

    private func extractCode(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed) {
            // Universal Link: https://pushup.weareo.fun/friend/<CODE>
            if url.scheme == "https",
               url.host == "pushup.weareo.fun",
               url.pathComponents.count >= 3,
               url.pathComponents[1] == "friend" {
                return url.pathComponents[2].uppercased()
            }
            // Legacy custom scheme: pushup://friend-code/<CODE>
            if url.scheme == "pushup", url.host == "friend-code" {
                return url.pathComponents
                    .filter { $0 != "/" }
                    .first?
                    .uppercased() ?? ""
            }
        }

        // Bare code typed or printed directly on a QR
        let bare = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        guard bare.count >= 4, bare.count <= 16 else { return "" }
        return bare
    }
}

// MARK: - QRScannerOverlayView

private final class QRScannerOverlayView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let side:   CGFloat = min(rect.width, rect.height) * 0.65
        let cx             = rect.midX
        let cy             = rect.midY
        let cutout         = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
        let radius: CGFloat = 16

        // Dim surround with transparent cutout (even-odd fill rule)
        ctx.saveGState()
        let outer = UIBezierPath(rect: rect)
        let hole  = UIBezierPath(roundedRect: cutout, cornerRadius: radius)
        outer.append(hole)
        outer.usesEvenOddFillRule = true
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        ctx.addPath(outer.cgPath)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        // White border
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(3)
        ctx.addPath(UIBezierPath(roundedRect: cutout, cornerRadius: radius).cgPath)
        ctx.strokePath()
        ctx.restoreGState()

        // Instruction label
        let text  = "Point at a friend's QR code" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            UIFont.preferredFont(forTextStyle: .subheadline),
            .foregroundColor: UIColor.white,
        ]
        let textSize = text.size(withAttributes: attrs)
        let textRect = CGRect(
            x: cx - textSize.width / 2,
            y: cutout.maxY + 20,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attrs)
    }
}
