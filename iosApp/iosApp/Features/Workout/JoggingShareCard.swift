import CoreLocation
import MapKit
import SwiftUI

// MARK: - JoggingShareCard

/// A self-contained card view designed to be rendered as a PNG image for sharing.
///
/// Layout (390 x 520 pt):
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
    let routeCoordinates: [CLLocationCoordinate2D]
    let distance: String
    let duration: String
    let pace: String
    let calories: String
    let earnedMinutes: Int
    let date: Date

    private let cardWidth: CGFloat = 390
    private let cardHeight: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            // Map area
            mapArea
                .frame(height: 280)
                .clipped()

            // Stats
            statsGrid
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
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
                colors: [Color(hex: 0x1A1A2E), Color(hex: 0x16213E)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Map Area

    private var mapArea: some View {
        ZStack {
            if let snapshot = mapSnapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(hex: 0x0D1117)
                Image(systemName: "map")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            // Gradient overlay at bottom for smooth transition
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color(hex: 0x1A1A2E)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
            }

            // Date badge top-left
            VStack {
                HStack {
                    Text(formattedDate)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 12)
                Spacer()
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 16) {
            VStack(spacing: 12) {
                shareStatItem(value: distance, label: "DISTANCE", icon: "figure.run")
                shareStatItem(value: pace, label: "AVG PACE", icon: "speedometer")
            }
            VStack(spacing: 12) {
                shareStatItem(value: duration, label: "DURATION", icon: "clock")
                shareStatItem(value: calories, label: "CALORIES", icon: "flame.fill")
            }
        }
    }

    private func shareStatItem(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x4DA6FF))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .tracking(0.5)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Earned Time

    private var earnedTimeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: 0x34D399))

            Text("+\(earnedMinutes) min screen time earned")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: 0x34D399))

            Spacer()
        }
    }

    // MARK: - Branding

    private var brandingBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x4DA6FF))

                Text("PushUp")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            Text("Earn screen time with fitness")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Color Hex Extension (private to this file)

private extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
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
    ///   - size: The desired image size in points.
    /// - Returns: A `UIImage` of the map with the route, or `nil` if generation fails.
    static func generateSnapshot(
        coordinates: [CLLocationCoordinate2D],
        size: CGSize = CGSize(width: 390, height: 280)
    ) async -> UIImage? {
        guard coordinates.count >= 2 else { return nil }

        // Calculate the bounding region with padding
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        var region = MKCoordinateRegion(polyline.boundingMapRect)

        // Add 30% padding around the route
        region.span.latitudeDelta *= 1.3
        region.span.longitudeDelta *= 1.3

        // Ensure minimum zoom level
        region.span.latitudeDelta = max(region.span.latitudeDelta, 0.005)
        region.span.longitudeDelta = max(region.span.longitudeDelta, 0.005)

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.showsBuildings = true
        options.pointOfInterestFilter = .excludingAll

        // Use dark appearance for the map to match the card style
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()
            return drawRoute(on: snapshot, coordinates: coordinates)
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
        coordinates: [CLLocationCoordinate2D]
    ) -> UIImage {
        let image = snapshot.image

        UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
        defer { UIGraphicsEndImageContext() }

        // Draw the base map
        image.draw(at: .zero)

        guard let context = UIGraphicsGetCurrentContext() else {
            return image
        }

        // Convert coordinates to points in the snapshot
        let points = coordinates.map { snapshot.point(for: $0) }

        // Draw route shadow
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(7.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawPath(context: context, points: points)
        context.strokePath()

        // Draw route line
        context.setStrokeColor(UIColor(red: 0.3, green: 0.65, blue: 1.0, alpha: 1.0).cgColor)
        context.setLineWidth(4.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawPath(context: context, points: points)
        context.strokePath()

        // Draw start marker (green dot)
        if let first = points.first {
            drawMarker(context: context, at: first, color: UIColor(red: 0.2, green: 0.83, blue: 0.6, alpha: 1.0), radius: 6)
        }

        // Draw end marker (red dot)
        if let last = points.last, points.count > 1 {
            drawMarker(context: context, at: last, color: UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0), radius: 6)
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
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - radius - 2,
            y: point.y - radius - 2,
            width: (radius + 2) * 2,
            height: (radius + 2) * 2
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
@MainActor
enum JoggingShareRenderer {

    /// Renders the share card to a PNG-ready UIImage.
    ///
    /// - Parameters:
    ///   - mapSnapshot: Pre-generated map snapshot image.
    ///   - routeCoordinates: GPS coordinates for the route.
    ///   - distance: Formatted distance string.
    ///   - duration: Formatted duration string.
    ///   - pace: Formatted pace string.
    ///   - calories: Formatted calories string.
    ///   - earnedMinutes: Screen time minutes earned.
    ///   - date: The date of the run.
    /// - Returns: A rendered UIImage, or nil if rendering fails.
    @MainActor
    static func renderShareImage(
        mapSnapshot: UIImage?,
        routeCoordinates: [CLLocationCoordinate2D],
        distance: String,
        duration: String,
        pace: String,
        calories: String,
        earnedMinutes: Int,
        date: Date
    ) -> UIImage? {
        let card = JoggingShareCard(
            mapSnapshot: mapSnapshot,
            routeCoordinates: routeCoordinates,
            distance: distance,
            duration: duration,
            pace: pace,
            calories: calories,
            earnedMinutes: earnedMinutes,
            date: date
        )

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0 // 3x for crisp sharing
        return renderer.uiImage
    }
}
