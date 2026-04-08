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
    private let bg = Color(red: 0.04, green: 0.05, blue: 0.08)
    private let panel = Color(red: 0.09, green: 0.10, blue: 0.15)
    private let panelSoft = Color.white.opacity(0.05)
    private let accent = Color(red: 0.35, green: 0.77, blue: 1.0)
    private let accentSoft = Color(red: 0.60, green: 0.90, blue: 1.0)
    private let green = Color(red: 0.33, green: 0.88, blue: 0.63)
    private let subtle = Color.white.opacity(0.52)
    private let muted = Color.white.opacity(0.72)
    private let divider = Color.white.opacity(0.08)

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 14) {
                headerStrip
                heroSection
                statGrid
                footerStrip
            }
            .padding(18)
        }
        .frame(width: 400, height: 533)
        .background(bg)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.07),
                    Color(red: 0.06, green: 0.07, blue: 0.11),
                    Color(red: 0.03, green: 0.05, blue: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [accent.opacity(0.34), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 220
            )
            .offset(x: 40, y: -50)

            RadialGradient(
                colors: [green.opacity(0.18), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 180
            )
            .offset(x: -30, y: 60)

            VStack(spacing: 24) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.025))
                        .frame(height: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Header

    private var headerStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentSoft, accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 10, height: 10)
                Text("RUN RECAP")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(panelSoft, in: Capsule())

            Spacer()

            Text(formattedDate.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(subtle)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = mapSnapshot {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 364, height: 236)
                    .clipped()
            } else {
                Color(red: 0.05, green: 0.05, blue: 0.08)
                    .frame(height: 236)
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

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.16), bg.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(distance)
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("km")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(muted)
                        .opacity(distance.contains("km") ? 0 : 1)
                }

                HStack(spacing: 8) {
                    heroPill(icon: "speedometer", title: pace)
                    heroPill(icon: "flame.fill", title: calories)
                    heroPill(icon: "clock.badge.checkmark.fill", title: "+\(earnedMinutes)m")
                }
            }
            .padding(18)
        }
        .frame(height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 30, y: 18)
    }

    private func heroPill(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.94))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.26), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Stats

    private var statGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(title: "Duration", value: duration, icon: "timer")
                statCard(title: "Avg pace", value: pace, icon: "gauge.with.dots.needle.50percent")
            }

            HStack(spacing: 12) {
                statCard(title: "Calories", value: calories, icon: "flame")
                creditCard
            }
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(subtle)
            }

            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var creditCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCREEN TIME")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(subtle)

            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(green.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("+\(earnedMinutes) min")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("earned in PushUp")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(green)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [green.opacity(0.14), panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(green.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footerStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                Text("PushUp")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }

            Rectangle()
                .fill(divider)
                .frame(width: 1, height: 16)

            Text("run | recover | earn")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(subtle)

            Spacer()

            Text("pushup")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.30))
        }
        .padding(.horizontal, 4)
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
