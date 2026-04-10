import CoreLocation
import MapKit
import SwiftUI

// MARK: - JoggingShareCard

/// A self-contained card rendered as a JPEG for sharing via WhatsApp, iMessage, etc.
///
/// **No rounded corners** -- messaging apps render transparent PNG corners as white.
/// The card uses a solid dark background that extends edge-to-edge.
///
/// Designed at 400x700 pt, rendered at 3x for a tall share image.
struct JoggingShareCard: View {

    let mapSnapshot: UIImage?
    let distance: String
    let duration: String
    let pace: String
    let calories: String
    let earnedMinutes: Int
    let date: Date

    // Design tokens (self-contained, no dependency on AppColors for off-screen rendering)
    private let bg = Color(red: 0.04, green: 0.05, blue: 0.08)
    private let accent = Color(red: 0.35, green: 0.77, blue: 1.0)
    private let green = Color(red: 0.33, green: 0.88, blue: 0.63)
    private let subtle = Color.white.opacity(0.58)
    private let muted = Color.white.opacity(0.78)

    var body: some View {
        ZStack {
            backgroundLayer
            contentOverlay
        }
        .frame(width: 400, height: 700)
        .background(bg)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            mapSection

            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.36),
                    bg.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [accent.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 220
            )
            .offset(x: 60, y: -80)
        }
    }

    private var contentOverlay: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 22)
                .padding(.top, 20)

            Spacer()

            bottomContent
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)
                Text("RUN RECAP")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.22), in: Capsule())

            Spacer()

            Text(formattedDate.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(subtle)
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        ZStack {
            if let img = mapSnapshot {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 400, height: 700)
                    .clipped()
            } else {
                Color(red: 0.05, green: 0.05, blue: 0.08)
                    .frame(width: 400, height: 700)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.16))
                            Text("Route Preview")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.26))
                        }
                    }
            }
        }
    }

    // MARK: - Bottom Content

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(distance)
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Outdoor run")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(muted)
            }

            HStack(alignment: .top, spacing: 28) {
                inlineStat(label: "Duration", value: duration)
                inlineStat(label: "Pace", value: pace)
                inlineStat(label: "Calories", value: calories)
            }

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(green)
                Text("+\(earnedMinutes) min screen time earned")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(green)
            }

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                    Text("Sinura")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                }

                Spacer()

                Text("move to unlock")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(subtle)
            }
        }
    }

    private func inlineStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(subtle)

            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy | HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Map Snapshot Generator

@MainActor
enum JoggingMapSnapshotGenerator {

    /// Generates a high-resolution map snapshot with the route drawn on it.
    ///
    /// The snapshot is rendered at **point size** with `scale = UIScreen.main.scale`
    /// so MKMapSnapshotter uses the device's native retina tiles (2x or 3x).
    /// This produces a sharp, non-pixelated map image.
    static func generateSnapshot(
        coordinates: [CLLocationCoordinate2D],
        pointSize: CGSize = CGSize(width: 400, height: 700)
    ) async -> UIImage? {
        guard !coordinates.isEmpty else { return nil }

        let region: MKCoordinateRegion
        if coordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            var r = MKCoordinateRegion(polyline.boundingMapRect)
            r.span.latitudeDelta *= 1.4
            r.span.longitudeDelta *= 1.4
            r.span.latitudeDelta = max(r.span.latitudeDelta, 0.003)
            r.span.longitudeDelta = max(r.span.longitudeDelta, 0.003)
            region = r
        } else {
            region = MKCoordinateRegion(
                center: coordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = pointSize
        // Use the device's native scale so MKMapSnapshotter fetches retina map tiles.
        // This is the key to getting a sharp, non-pixelated map.
        options.scale = UIScreen.main.scale
        options.mapType = .mutedStandard
        options.showsBuildings = true
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            return drawRoute(on: snapshot, coordinates: coordinates)
        } catch {
            #if DEBUG
            print("[JoggingMapSnapshotGenerator] Snapshot failed: \(error)")
            #endif
            return nil
        }
    }

    private static func drawRoute(
        on snapshot: MKMapSnapshotter.Snapshot,
        coordinates: [CLLocationCoordinate2D]
    ) -> UIImage {
        let image = snapshot.image
        let scale = image.scale

        UIGraphicsBeginImageContextWithOptions(image.size, true, scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(at: .zero)

        guard let ctx = UIGraphicsGetCurrentContext() else { return image }

        let points = coordinates.map { snapshot.point(for: $0) }

        if points.count >= 2 {
            // Shadow
            ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(6)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            strokePath(ctx, points)

            // Route line
            ctx.setStrokeColor(UIColor(red: 0.30, green: 0.65, blue: 1.0, alpha: 1.0).cgColor)
            ctx.setLineWidth(3.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            strokePath(ctx, points)
        }

        // Start marker (green)
        if let p = points.first {
            dot(ctx, at: p, fill: UIColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1), r: 5)
        }
        // End marker (accent blue)
        if let p = points.last, points.count > 1 {
            dot(ctx, at: p, fill: UIColor(red: 0.30, green: 0.65, blue: 1.0, alpha: 1), r: 5)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    private static func strokePath(_ ctx: CGContext, _ pts: [CGPoint]) {
        guard let f = pts.first else { return }
        ctx.move(to: f)
        pts.dropFirst().forEach { ctx.addLine(to: $0) }
        ctx.strokePath()
    }

    private static func dot(_ ctx: CGContext, at p: CGPoint, fill: UIColor, r: CGFloat) {
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r - 2, y: p.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2))
        ctx.setFillColor(fill.cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }
}

// MARK: - Share Image Renderer

@MainActor
enum JoggingShareRenderer {

    /// Renders the share card as a **JPEG** UIImage (no transparency = no white corners).
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
        // Force opaque rendering -- the dark background fills every pixel,
        // so there are no transparent corners that messaging apps turn white.
        renderer.isOpaque = true

        return renderer.uiImage
    }
}
