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
    var jointRadius: CGFloat = 6

    /// Width of skeleton connection lines in points.
    var lineWidth: CGFloat = 2.5

    /// Colour used for joints that pass the confidence threshold.
    var detectedJointColor: Color = .green

    /// Colour used for joints below the confidence threshold.
    var undetectedJointColor: Color = Color.yellow.opacity(0.4)

    /// Colour used for skeleton connection lines.
    var lineColor: Color = Color.white.opacity(0.85)

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
                    let jointA = pose[nameA], jointA.isDetected,
                    let jointB = pose[nameB], jointB.isDetected
                else { continue }

                let pointA = convert(jointA.position, to: size)
                let pointB = convert(jointB.position, to: size)

                var path = Path()
                path.move(to: pointA)
                path.addLine(to: pointB)

                context.stroke(
                    path,
                    with: .color(lineColor),
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
                let center = convert(joint.position, to: size)
                let rect = CGRect(
                    x: center.x - jointRadius,
                    y: center.y - jointRadius,
                    width: jointRadius * 2,
                    height: jointRadius * 2
                )
                let circle = Path(ellipseIn: rect)
                let color = joint.isDetected ? detectedJointColor : undetectedJointColor
                context.fill(circle, with: .color(color))

                // White border for contrast against any background.
                context.stroke(
                    circle,
                    with: .color(.white.opacity(0.6)),
                    lineWidth: 1
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
        let detectorRef = detector
        ZStack {
            CameraContainerView { sampleBuffer in
                // `detectorRef` is a local copy of the reference captured by
                // value. This avoids capturing `self` or the `@StateObject`
                // property wrapper directly. The `VisionPoseDetector` instance
                // is kept alive by SwiftUI's `@StateObject` ownership; this
                // closure simply holds an additional strong reference for the
                // duration of the camera session, which is correct because the
                // camera stops in `onDisappear` before the view is torn down.
                detectorRef.process(sampleBuffer)
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
