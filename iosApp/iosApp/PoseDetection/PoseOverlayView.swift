import SwiftUI

// MARK: - PoseOverlayView

/// A transparent SwiftUI overlay that draws detected body joints and skeleton
/// lines on top of a camera preview.
///
/// **Coordinate conversion**
/// Vision uses a normalised coordinate system with the origin at the
/// **bottom-left** of the image. SwiftUI's coordinate system has its origin
/// at the **top-left**. This view converts between the two systems by
/// flipping the Y axis: `screenY = (1 - normalizedY) * viewHeight`.
///
/// **Usage**
/// ```swift
/// ZStack {
///     CameraPreviewView(cameraManager: camera)
///     PoseOverlayView(pose: detector.currentPose)
/// }
/// ```
///
/// Set `isVisible = false` to hide the overlay without removing it from the
/// hierarchy (avoids layout recalculations during a workout).
struct PoseOverlayView: View {

    // MARK: - Input

    /// The pose to render. Pass `nil` to show nothing.
    let pose: BodyPose?

    /// Controls overlay visibility. Defaults to `true`.
    var isVisible: Bool = true

    // MARK: - Styling

    /// Radius of each joint dot in points.
    var jointRadius: CGFloat = 7

    /// Width of skeleton connection lines in points.
    var lineWidth: CGFloat = 2.5

    /// Colour for joints with high confidence (>= 0.5).
    var highConfidenceColor: Color = .green

    /// Colour for joints with medium confidence (0.1 – 0.5).
    var lowConfidenceColor: Color = Color.yellow.opacity(0.75)

    /// Colour used for skeleton connection lines between detected joints.
    var lineColor: Color = Color.white.opacity(0.85)

    /// Colour for lines where one or both joints have low confidence.
    var dimLineColor: Color = Color.white.opacity(0.3)

    /// Minimum confidence to draw a joint at all.
    /// Set to 0.0 to draw everything Vision returns (like Python/MediaPipe).
    var minimumDrawConfidence: Float = 0.05

    // MARK: - Body

    var body: some View {
        if isVisible, let pose {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    // Draw skeleton lines first so joints render on top.
                    skeletonLines(pose: pose, in: size)
                    jointDots(pose: pose, in: size)
                }
            }
        }
    }

    // MARK: - Skeleton Lines

    @ViewBuilder
    private func skeletonLines(pose: BodyPose, in size: CGSize) -> some View {
        Canvas { context, _ in
            for (nameA, nameB) in BodyPose.skeletonConnections {
                guard
                    let jointA = pose[nameA], jointA.confidence >= minimumDrawConfidence,
                    let jointB = pose[nameB], jointB.confidence >= minimumDrawConfidence
                else { continue }

                let pointA = convert(jointA.position, to: size)
                let pointB = convert(jointB.position, to: size)

                // Dim the line if either joint has low confidence.
                let bothDetected = jointA.isDetected && jointB.isDetected
                let color = bothDetected ? lineColor : dimLineColor

                var path = Path()
                path.move(to: pointA)
                path.addLine(to: pointB)

                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
    }

    // MARK: - Joint Dots

    @ViewBuilder
    private func jointDots(pose: BodyPose, in size: CGSize) -> some View {
        Canvas { context, _ in
            for joint in pose.joints.values {
                // Skip placeholder joints that Vision never returned
                // (confidence == 0 and position == .zero).
                guard joint.confidence >= minimumDrawConfidence else { continue }

                let center = convert(joint.position, to: size)
                let r = joint.isDetected ? jointRadius : jointRadius * 0.7
                let rect = CGRect(
                    x: center.x - r,
                    y: center.y - r,
                    width: r * 2,
                    height: r * 2
                )
                let circle = Path(ellipseIn: rect)

                // Green = high confidence, yellow = low confidence
                let color = joint.isDetected ? highConfidenceColor : lowConfidenceColor
                context.fill(circle, with: .color(color))

                // White border for contrast.
                context.stroke(
                    circle,
                    with: .color(.white.opacity(0.7)),
                    lineWidth: 1.5
                )
            }
        }
    }

    // MARK: - Coordinate Conversion

    /// Converts a Vision normalised point (origin bottom-left) to a SwiftUI
    /// point (origin top-left) within `size`.
    private func convert(_ normalised: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(
            x: normalised.x * size.width,
            y: (1 - normalised.y) * size.height
        )
    }
}

// MARK: - PoseOverlayContainerView

/// A ready-to-use container that layers a `CameraContainerView` with a
/// `PoseOverlayView` and wires a `VisionPoseDetector` between them.
///
/// This is the primary integration point for the workout screen (Task 3.6).
///
/// **Usage**
/// ```swift
/// PoseOverlayContainerView(showOverlay: $showDebugOverlay)
/// ```
struct PoseOverlayContainerView: View {

    /// Controls whether the debug skeleton overlay is visible.
    @Binding var showOverlay: Bool

    @StateObject private var detector = VisionPoseDetector()

    var body: some View {
        ZStack {
            CameraContainerView { [detector] sampleBuffer in
                // Capture `detector` by value in the capture list. This creates
                // a strong reference to the VisionPoseDetector instance (not the
                // @StateObject wrapper). The instance is kept alive by SwiftUI's
                // @StateObject ownership; the closure holds an additional strong
                // reference for the duration of the camera session. The camera
                // stops in `onDisappear` before the view is torn down.
                detector.process(sampleBuffer)
            }

            PoseOverlayView(
                pose: detector.currentPose,
                isVisible: showOverlay
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Pose Overlay - No Pose") {
    PoseOverlayView(pose: nil)
        .background(Color.black)
        .frame(width: 390, height: 844)
}

#Preview("Pose Overlay - Sample Pose") {
    // Build a synthetic pose for layout verification in Xcode Previews.
    let sampleJoints: [JointName: Joint] = Dictionary(
        uniqueKeysWithValues: JointName.allCases.map { name in
            // Spread joints across the frame in a rough humanoid layout.
            let positions: [JointName: CGPoint] = [
                .leftShoulder:  CGPoint(x: 0.40, y: 0.70),
                .rightShoulder: CGPoint(x: 0.60, y: 0.70),
                .leftElbow:     CGPoint(x: 0.30, y: 0.55),
                .rightElbow:    CGPoint(x: 0.70, y: 0.55),
                .leftWrist:     CGPoint(x: 0.22, y: 0.40),
                .rightWrist:    CGPoint(x: 0.78, y: 0.40),
                .leftHip:       CGPoint(x: 0.42, y: 0.48),
                .rightHip:      CGPoint(x: 0.58, y: 0.48),
                .leftKnee:      CGPoint(x: 0.40, y: 0.30),
                .rightKnee:     CGPoint(x: 0.60, y: 0.30),
                .leftAnkle:     CGPoint(x: 0.38, y: 0.15),
                .rightAnkle:    CGPoint(x: 0.62, y: 0.15),
            ]
            let position = positions[name] ?? CGPoint(x: 0.5, y: 0.5)
            return (name, Joint(name: name, position: position, confidence: 0.9))
        }
    )
    let pose = BodyPose(joints: sampleJoints, timestamp: 0)

    return ZStack {
        Color.black.ignoresSafeArea()
        // Simulate a person silhouette.
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 200, height: 400)
        PoseOverlayView(pose: pose)
    }
    .frame(width: 390, height: 844)
}
#endif
