import CoreLocation
import MapKit
import SwiftUI

// MARK: - JoggingShareCard

/// A self-contained card rendered as a JPEG for sharing via WhatsApp, iMessage, etc.
///
/// **No rounded corners** -- messaging apps render transparent PNG corners as white.
/// The card uses a solid dark background that extends edge-to-edge.
///
/// Designed at 400x533 pt, rendered at 3x = 1200x1600 px (sharp on all screens).
struct JoggingShareCard: View {

    let mapSnapshot: UIImage?
    let distance: String
    let duration: String
    let pace: String
    let calories: String
    let earnedMinutes: Int
    let date: Date

    // Design tokens (self-contained, no dependency on AppColors for off-screen rendering)
    private let bg = Color(red: 0.07, green: 0.07, blue: 0.11)
    private let cardBg = Color(red: 0.10, green: 0.10, blue: 0.15)
    private let accent = Color(red: 0.30, green: 0.65, blue: 1.0)
    private let green = Color(red: 0.20, green: 0.83, blue: 0.60)
    private let subtle = Color.white.opacity(0.45)
    private let divider = Color.white.opacity(0.06)

    var body: some View {
        VStack(spacing: 0) {
            mapSection
            statsSection
        }
        .frame(width: 400, height: 533)
        .background(bg)
    }

    // MARK: - Map

    private var mapSection: some View {
        ZStack(alignment: .topLeading) {
            if let img = mapSnapshot {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 400, height: 300)
                    .clipped()
            } else {
                Color(red: 0.05, green: 0.05, blue: 0.08)
                    .frame(height: 300)
                    .overlay {
                        Image(systemName: "map.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.white.opacity(0.08))
                    }
            }

            // Bottom fade
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, bg], startPoint: .top, endPoint: .bottom)
                    .frame(height: 60)
            }
            .frame(height: 300)

            // Date pill
            Text(formattedDate)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(.leading, 16)
                .padding(.top, 16)
        }
        .frame(height: 300)
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: 0) {
            // Big distance
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(distance)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Secondary stats row
            HStack(spacing: 0) {
                miniStat(value: duration, label: "Duration")
                miniDivider
                miniStat(value: pace, label: "Pace")
                miniDivider
                miniStat(value: calories, label: "Calories")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Earned time
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(green)
                Text("+\(earnedMinutes) min screen time")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(green)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Spacer(minLength: 0)

            // Branding
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                Text("PushUp")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("pushup.weareo.fun")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Helpers

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(subtle)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var miniDivider: some View {
        Rectangle()
            .fill(divider)
            .frame(width: 1, height: 28)
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
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
        pointSize: CGSize = CGSize(width: 400, height: 300)
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
