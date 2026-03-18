import CoreLocation
import MapKit
import SwiftUI

// MARK: - JoggingShareCard

/// A self-contained card view designed to be rendered as a PNG image for sharing.
///
/// Layout (1080 x 1350 px at 3x = 360 x 450 pt):
/// ┌──────────────────────────────┐
/// │  Map snapshot with route     │  (top ~55%)
/// ├──────────────────────────────┤
/// │  Stats grid (2x2)           │
/// │  Distance  |  Duration      │
/// │  Pace      |  Calories      │
/// ├──────────────────────────────┤
/// │  Screen time earned bar     │
/// ├──────────────────────────────┤
/// │  PushUp branding            │
/// └──────────────────────────────┘
struct JoggingShareCard: View {

    let mapSnapshot: UIImage?
    let distance: String
    let duration: String
    let pace: String
    let calories: String
    let earnedMinutes: Int
    let date: Date

    private let cardWidth: CGFloat = 360
    private let cardHeight: CGFloat = 480

    private let bgTop = Color(red: 0.10, green: 0.10, blue: 0.18)
    private let bgBottom = Color(red: 0.09, green: 0.13, blue: 0.24)
    private let accentBlue = Color(red: 0.30, green: 0.65, blue: 1.0)
    private let accentGreen = Color(red: 0.20, green: 0.83, blue: 0.60)

    var body: some View {
        VStack(spacing: 0) {
            // Map area
            mapArea
                .frame(height: 260)
                .clipped()

            // Stats
            statsGrid
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 20)

            // Earned time
            earnedTimeBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            // Branding
            brandingBar
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            LinearGradient(
                colors: [bgTop, bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // No clipShape -- the renderer handles the rounded corners via Core Graphics
        // to avoid white corner artifacts from ImageRenderer.
    }

    // MARK: - Map Area

    private var mapArea: some View {
        ZStack {
            if let snapshot = mapSnapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: 260)
                    .clipped()
            } else {
                // Fallback when no map is available (e.g. very short run)
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.09),
                        Color(red: 0.08, green: 0.10, blue: 0.14),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.white.opacity(0.15))
                    Text("Route")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.15))
                }
            }

            // Gradient overlay at bottom for smooth transition into stats
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, bgTop],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 50)
            }

            // Date badge top-left
            VStack {
                HStack {
                    Text(formattedDate)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.leading, 14)
                .padding(.top, 14)
                Spacer()
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 14) {
            VStack(spacing: 10) {
                shareStatItem(value: distance, label: "DISTANCE", icon: "figure.run")
                shareStatItem(value: pace, label: "AVG PACE", icon: "speedometer")
            }
            VStack(spacing: 10) {
                shareStatItem(value: duration, label: "DURATION", icon: "clock")
                shareStatItem(value: calories, label: "CALORIES", icon: "flame.fill")
            }
        }
    }

    private func shareStatItem(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accentBlue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .tracking(0.8)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Earned Time

    private var earnedTimeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accentGreen)

            Text("+\(earnedMinutes) min screen time earned")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accentGreen)

            Spacer()
        }
    }

    // MARK: - Branding

    private var brandingBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentBlue)

                Text("PushUp")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            Text("Earn screen time with fitness")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Map Snapshot Generator

/// Generates a static map image with the jogging route drawn on it.
///
/// Uses `MKMapSnapshotter` for efficient off-screen rendering.
/// The route is drawn as a polyline on the snapshot image using Core Graphics.
@MainActor
enum JoggingMapSnapshotGenerator {

    /// Generates a map snapshot with the route polyline drawn on it.
    ///
    /// - Parameters:
    ///   - coordinates: The GPS coordinates of the route.
    ///   - size: The desired image size in **pixels** (not points).
    ///           Rendered at the screen's native scale for maximum sharpness.
    /// - Returns: A `UIImage` of the map with the route, or `nil` if generation fails.
    static func generateSnapshot(
        coordinates: [CLLocationCoordinate2D],
        size: CGSize = CGSize(width: 1080, height: 780)
    ) async -> UIImage? {
        // Accept even a single coordinate (show the user's position)
        guard !coordinates.isEmpty else { return nil }

        // Calculate the bounding region with padding
        let region: MKCoordinateRegion
        if coordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            var r = MKCoordinateRegion(polyline.boundingMapRect)
            // Add 40% padding around the route
            r.span.latitudeDelta *= 1.4
            r.span.longitudeDelta *= 1.4
            // Ensure minimum zoom level
            r.span.latitudeDelta = max(r.span.latitudeDelta, 0.003)
            r.span.longitudeDelta = max(r.span.longitudeDelta, 0.003)
            region = r
        } else {
            // Single point: show a small area around it
            region = MKCoordinateRegion(
                center: coordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }

        let options = MKMapSnapshotter.Options()
        options.region = region
        // Render at full pixel size for maximum sharpness.
        // scale = 1.0 because we are specifying the size in pixels directly.
        options.size = size
        options.scale = 1.0
        options.mapType = .mutedStandard
        options.showsBuildings = true
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()
            return drawRoute(on: snapshot, coordinates: coordinates, pixelSize: size)
        } catch {
            #if DEBUG
            print("[JoggingMapSnapshotGenerator] Snapshot failed: \(error)")
            #endif
            return nil
        }
    }

    /// Draws the route polyline on the map snapshot image.
    private static func drawRoute(
        on snapshot: MKMapSnapshotter.Snapshot,
        coordinates: [CLLocationCoordinate2D],
        pixelSize: CGSize
    ) -> UIImage {
        let image = snapshot.image

        // Use scale=1 because the image is already at the desired pixel size
        UIGraphicsBeginImageContextWithOptions(image.size, true, 1.0)
        defer { UIGraphicsEndImageContext() }

        // Draw the base map
        image.draw(at: .zero)

        guard let context = UIGraphicsGetCurrentContext() else {
            return image
        }

        // Convert coordinates to points in the snapshot
        let points = coordinates.map { snapshot.point(for: $0) }

        if points.count >= 2 {
            // Draw route glow/shadow
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.4).cgColor)
            context.setLineWidth(10.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            drawPath(context: context, points: points)
            context.strokePath()

            // Draw route line
            context.setStrokeColor(UIColor(red: 0.30, green: 0.65, blue: 1.0, alpha: 1.0).cgColor)
            context.setLineWidth(5.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            drawPath(context: context, points: points)
            context.strokePath()
        }

        // Draw start marker (green dot)
        if let first = points.first {
            drawMarker(
                context: context,
                at: first,
                color: UIColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1.0),
                radius: 8
            )
        }

        // Draw end marker (blue dot) -- only if we have a route
        if let last = points.last, points.count > 1 {
            drawMarker(
                context: context,
                at: last,
                color: UIColor(red: 0.30, green: 0.65, blue: 1.0, alpha: 1.0),
                radius: 8
            )
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    private static func drawPath(context: CGContext, points: [CGPoint]) {
        guard let first = points.first else { return }
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
    }

    private static func drawMarker(context: CGContext, at point: CGPoint, color: UIColor, radius: CGFloat) {
        // White border
        let borderRadius = radius + 3
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - borderRadius,
            y: point.y - borderRadius,
            width: borderRadius * 2,
            height: borderRadius * 2
        ))
        // Colored fill
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}

// MARK: - Share Image Renderer

/// Renders the JoggingShareCard as a UIImage for sharing.
///
/// Uses `ImageRenderer` to convert the SwiftUI card to a bitmap, then applies
/// rounded corners via Core Graphics to avoid the white-corner artifact that
/// occurs when `clipShape` is used with `ImageRenderer`.
@MainActor
enum JoggingShareRenderer {

    @MainActor
    static func renderShareImage(
        mapSnapshot: UIImage?,
        distance: String,
        duration: String,
        pace: String,
        calories: String,
        earnedMinutes: Int,
        date: Date
    ) -> UIImage? {
        let card = JoggingShareCard(
            mapSnapshot: mapSnapshot,
            distance: distance,
            duration: duration,
            pace: pace,
            calories: calories,
            earnedMinutes: earnedMinutes,
            date: date
        )

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0

        guard let rawImage = renderer.uiImage else { return nil }

        // Apply rounded corners via Core Graphics to avoid white corner artifacts.
        // ImageRenderer does not correctly handle clipShape transparency.
        return applyRoundedCorners(to: rawImage, cornerRadius: 20.0 * 3.0)
    }

    /// Clips the image to a rounded rectangle with the given corner radius (in pixels).
    private static func applyRoundedCorners(to image: UIImage, cornerRadius: CGFloat) -> UIImage {
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        let rect = CGRect(origin: .zero, size: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        path.addClip()
        image.draw(in: rect)

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
}
