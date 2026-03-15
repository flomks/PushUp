import AVFoundation
import SwiftUI
import UIKit

// MARK: - EnterFriendCodeSheet

/// Sheet that lets the user type in or scan a friend code.
///
/// Can be used in two ways:
///   1. As a standalone sheet (e.g. from a deep-link) -- wraps itself in a
///      NavigationStack and shows a "Done" button.
///   2. Embedded inside `AddFriendSheet` (the "Enter Code" tab) -- the
///      parent provides the navigation chrome; set `standalone = false`.
struct EnterFriendCodeSheet: View {

    @ObservedObject var viewModel: FriendCodeViewModel
    @Environment(\.dismiss) private var dismiss

    var standalone: Bool = true

    @FocusState private var isFieldFocused: Bool
    @State private var showScanner = false

    var body: some View {
        Group {
            if standalone {
                NavigationStack {
                    innerContent
                        .navigationTitle("Enter Friend Code")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { dismiss() }
                                    .font(AppTypography.bodySemibold)
                                    .foregroundStyle(AppColors.primary)
                            }
                        }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            } else {
                innerContent
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            FriendQRScannerView { code in
                viewModel.enteredCode = code
                showScanner = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    viewModel.useFriendCode()
                }
            } onCancel: {
                showScanner = false
            }
        }
        .alert(
            viewModel.useCodeSuccess?.title ?? "",
            isPresented: Binding(
                get: { viewModel.useCodeSuccess != nil },
                set: { if !$0 { viewModel.dismissUseCodeSuccess() } }
            )
        ) {
            Button("Great!", role: .cancel) {
                viewModel.dismissUseCodeSuccess()
                if standalone { dismiss() }
            }
        } message: {
            Text(viewModel.useCodeSuccess?.message ?? "")
        }
        .alert("Could Not Use Code", isPresented: Binding(
            get: { viewModel.useCodeError != nil },
            set: { if !$0 { viewModel.dismissUseCodeError() } }
        )) {
            Button("OK", role: .cancel) { viewModel.dismissUseCodeError() }
        } message: {
            Text(viewModel.useCodeError ?? "")
        }
        .onAppear { isFieldFocused = true }
    }

    // MARK: - Inner content

    private var innerContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppSpacing.lg) {
                // Header
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(AppColors.primary)
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: AppSpacing.xxs) {
                        Text("Add by Code")
                            .font(AppTypography.title3)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Type your friend's code or scan their QR code.")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Input row
                VStack(spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xs) {
                        TextField("e.g. AB3X7K2M", text: $viewModel.enteredCode)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .focused($isFieldFocused)
                            .onChange(of: viewModel.enteredCode) { _, newValue in
                                let cleaned = newValue
                                    .uppercased()
                                    .filter { $0.isLetter || $0.isNumber }
                                    .prefix(16)
                                if viewModel.enteredCode != String(cleaned) {
                                    viewModel.enteredCode = String(cleaned)
                                }
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .background(
                                AppColors.backgroundSecondary,
                                in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                                    .strokeBorder(
                                        isFieldFocused ? AppColors.primary.opacity(0.5) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )

                        // QR scan button
                        Button {
                            isFieldFocused = false
                            showScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(AppColors.primary)
                                .frame(width: 52, height: 52)
                                .background(
                                    AppColors.primary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scan QR code")
                    }

                    if !viewModel.enteredCode.isEmpty {
                        Text("\(viewModel.enteredCode.count) / 16 characters")
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                // Submit button
                Button {
                    isFieldFocused = false
                    viewModel.useFriendCode()
                } label: {
                    Group {
                        if viewModel.isUsingCode {
                            ProgressView().tint(.white)
                        } else {
                            Text("Add Friend")
                                .font(AppTypography.bodySemibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                    .background(
                        viewModel.enteredCode.count >= 4
                            ? AppColors.primary
                            : AppColors.primary.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.enteredCode.count < 4 || viewModel.isUsingCode)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.lg)

            Spacer()
        }
        .background(AppColors.backgroundPrimary)
    }
}

// MARK: - FriendQRScannerView
//
// UIViewControllerRepresentable wrapper. Defined in the same file so
// Xcode never has a cross-file visibility problem.

struct FriendQRScannerView: UIViewControllerRepresentable {

    var onCode:   (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> FriendQRScannerVC {
        let vc = FriendQRScannerVC()
        vc.onCode   = onCode
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ vc: FriendQRScannerVC, context: Context) {}
}

// MARK: - FriendQRScannerVC

final class FriendQRScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onCode:   ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let session      = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasDelivered = false
    private let sessionQueue = DispatchQueue(label: "com.pushup.qrscanner", qos: .userInitiated)
    private var overlayAdded = false

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
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
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

    // MARK: Session

    private func configureSession() {
        session.beginConfiguration()
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { session.commitConfiguration(); return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { session.commitConfiguration(); return }
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
        let overlay = FriendScannerOverlay()
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
        let img    = UIImage(systemName: "xmark.circle.fill", withConfiguration: config)
        let btn    = UIButton(type: .system)
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            btn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            btn.widthAnchor.constraint(equalToConstant: 44),
            btn.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func cancelTapped() {
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
        onCancel?()
    }

    // MARK: Permission denied

    private func showPermissionDenied() {
        let label = UILabel()
        label.text = "Camera access is required to scan QR codes.\nPlease enable it in Settings."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .body)

        let btn = UIButton(type: .system)
        btn.setTitle("Open Settings", for: .normal)
        btn.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        btn.tintColor = .white
        btn.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, btn])
        stack.axis    = .vertical
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

    private func extractCode(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           url.scheme == "pushup",
           url.host == "friend-code" {
            return url.pathComponents.filter { $0 != "/" }.first?.uppercased() ?? ""
        }
        let bare = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        guard bare.count >= 4, bare.count <= 16 else { return "" }
        return bare
    }
}

// MARK: - FriendScannerOverlay

private final class FriendScannerOverlay: UIView {

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

        // Dim surround with transparent cutout (even-odd rule)
        ctx.saveGState()
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        let outer = UIBezierPath(rect: rect)
        let hole  = UIBezierPath(roundedRect: cutout, cornerRadius: radius)
        outer.append(hole)
        outer.usesEvenOddFillRule = true
        ctx.addPath(outer.cgPath)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        // White border
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(3)
        let border = UIBezierPath(roundedRect: cutout, cornerRadius: radius)
        ctx.addPath(border.cgPath)
        ctx.strokePath()
        ctx.restoreGState()

        // Label
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

// MARK: - Preview

#if DEBUG
#Preview("EnterFriendCodeSheet") {
    EnterFriendCodeSheet(viewModel: FriendCodeViewModel())
}
#endif
