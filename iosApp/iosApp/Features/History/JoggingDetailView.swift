import MapKit
import Shared
import SwiftUI

// MARK: - JoggingDetailView

/// Detail screen for a completed jogging session.
///
/// Shows key running metrics (distance, duration, pace, calories, earned time)
/// and an interactive MapKit route map with timestamp annotations.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  [Back]  Mon, Mar 8 - 09:42  [X]  |  <- navigation bar
/// |                                    |
/// |  [Hero metrics card]               |  <- distance, duration, pace, calories
/// |                                    |
/// |  [Interactive Route Map]            |  <- MapKit with polyline + annotations
/// |                                    |
/// |  [Route Details]                    |  <- GPS points, max/avg speed, elevation
/// +-----------------------------------+
/// ```
struct JoggingDetailView: View {

    let session: JoggingSessionItem

    @Environment(\.dismiss) private var dismiss

    /// Route points loaded from the local DB on appear.
    @State private var routePoints: [RoutePointItem] = []

    /// Whether route points are currently being loaded.
    @State private var isLoadingRoute: Bool = true

    /// The selected route point for the tooltip.
    @State private var selectedPoint: RoutePointItem? = nil

    /// Map camera position.
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: AppSpacing.md) {
                        heroCard
                        routeMapSection
                        if !routePoints.isEmpty {
                            routeDetailsCard
                        }
                        if let selected = selectedPoint {
                            selectedPointCard(selected)
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.screenVerticalBottom)
                }
            }
            .navigationTitle("\(session.shortDateString) - \(session.timeString)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(icon: .xmarkCircleFill)
                            .font(.system(size: AppSpacing.iconSizeMedium))
                            .foregroundStyle(AppColors.textSecondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("jogging_detail_close_button")
                }
            }
            .task { loadRoutePoints() }
        }
        .accessibilityIdentifier("jogging_detail_screen")
    }

    // MARK: - Load Route Points

    private func loadRoutePoints() {
        DataBridge.shared.fetchRoutePointsForSession(sessionId: session.kmpSessionId) { kmpPoints in
            let mapped: [RoutePointItem] = kmpPoints.enumerated().map { index, point in
                let timestampMs = point.timestamp.epochSeconds * 1_000 + Int64(point.timestamp.nanosecondsOfSecond) / 1_000_000
                let date = Date(timeIntervalSince1970: Double(timestampMs) / 1_000.0)

                return RoutePointItem(
                    id: UUID(uuidString: point.id) ?? UUID(),
                    index: index,
                    coordinate: CLLocationCoordinate2D(
                        latitude: point.latitude,
                        longitude: point.longitude
                    ),
                    altitude: point.altitude?.doubleValue,
                    speed: point.speed?.doubleValue,
                    distanceFromStart: point.distanceFromStart,
                    timestamp: date
                )
            }
            self.routePoints = mapped
            self.isLoadingRoute = false

            // Set initial map region to fit the route
            if !mapped.isEmpty {
                let coords = mapped.map { $0.coordinate }
                let region = Self.regionForCoordinates(coords)
                mapPosition = .region(region)
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        Card {
            VStack(spacing: AppSpacing.md) {

                // Distance hero
                VStack(spacing: AppSpacing.xxs) {
                    Text(session.distanceString)
                        .font(AppTypography.displayLarge)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Distance")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Divider()

                // Metrics row
                HStack(spacing: 0) {
                    metricCell(
                        icon: .clock,
                        value: session.durationString,
                        label: "Duration",
                        tint: AppColors.info
                    )

                    metricDivider

                    metricCell(
                        icon: .figureRun,
                        value: "\(session.formattedPace) /km",
                        label: "Avg Pace",
                        tint: AppColors.primary
                    )

                    metricDivider

                    metricCell(
                        icon: .flameFill,
                        value: "\(session.caloriesBurned) kcal",
                        label: "Calories",
                        tint: AppColors.error
                    )
                }

                Divider()

                // Earned time
                HStack(spacing: AppSpacing.xs) {
                    Image(icon: .boltFill)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                        .foregroundStyle(AppColors.success)

                    Text("+\(session.earnedMinutes) min Screen Time Earned")
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.success)
                }
            }
        }
        .accessibilityIdentifier("jogging_detail_hero_card")
    }

    // MARK: - Metric Cells

    @ViewBuilder
    private func metricCell(
        icon: AppIcon,
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon.rawValue)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.textPrimary)

            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppColors.separator)
            .frame(width: 1, height: 48)
    }

    // MARK: - Route Map Section

    @ViewBuilder
    private var routeMapSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {

            Label("Route", icon: .figureRun)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            if isLoadingRoute {
                VStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.primary)
                    Text("Loading route...")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
            } else if routePoints.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    Image(icon: .figureRun)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .symbolRenderingMode(.hierarchical)

                    Text("No GPS route data was recorded for this session.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            } else {
                Text("Tap on the route to see timestamps and speed at each point.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)

                routeMap
                    .frame(height: 350)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)

                // Legend
                HStack(spacing: AppSpacing.md) {
                    legendItem(color: .green, label: "Start")
                    legendItem(color: .red, label: "End")
                    legendItem(color: AppColors.info, label: "Route")
                }
                .padding(.top, AppSpacing.xxs)
            }
        }
    }

    // MARK: - Route Map (MapKit)

    private var routeMap: some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            // Route polyline
            if routePoints.count >= 2 {
                MapPolyline(
                    coordinates: routePoints.map { $0.coordinate }
                )
                .stroke(AppColors.info, lineWidth: 4)
            }

            // Start marker (green)
            if let first = routePoints.first {
                Annotation("Start", coordinate: first.coordinate) {
                    ZStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 20, height: 20)
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                    }
                    .shadow(color: .green.opacity(0.5), radius: 4)
                    .onTapGesture {
                        selectedPoint = first
                    }
                }
            }

            // End marker (red)
            if let last = routePoints.last, routePoints.count > 1 {
                Annotation("End", coordinate: last.coordinate) {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 20, height: 20)
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                    }
                    .shadow(color: .red.opacity(0.5), radius: 4)
                    .onTapGesture {
                        selectedPoint = last
                    }
                }
            }

            // Intermediate timestamp markers (every ~12.5% of the route)
            let markerInterval = max(1, routePoints.count / 8)
            ForEach(intermediateMarkerIndices(interval: markerInterval), id: \.self) { index in
                let point = routePoints[index]
                Annotation("", coordinate: point.coordinate) {
                    Circle()
                        .fill(AppColors.info.opacity(0.8))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 1.5)
                        )
                        .shadow(color: AppColors.info.opacity(0.3), radius: 2)
                        .onTapGesture {
                            selectedPoint = point
                        }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    /// Returns indices for intermediate markers, excluding first and last.
    private func intermediateMarkerIndices(interval: Int) -> [Int] {
        guard routePoints.count > 2 else { return [] }
        var indices: [Int] = []
        var i = interval
        while i < routePoints.count - 1 {
            indices.append(i)
            i += interval
        }
        return indices
    }

    // MARK: - Selected Point Card

    @ViewBuilder
    private func selectedPointCard(_ point: RoutePointItem) -> some View {
        Card {
            VStack(spacing: AppSpacing.sm) {
                HStack {
                    Label("Route Point", icon: .figureRun)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Button {
                        selectedPoint = nil
                    } label: {
                        Image(icon: .xmarkCircleFill)
                            .font(.system(size: 18))
                            .foregroundStyle(AppColors.textSecondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }

                Divider()

                detailRow(label: "Time", value: Self.timeFormatter.string(from: point.timestamp))
                detailRow(label: "Distance from Start", value: "\(Int(point.distanceFromStart)) m")

                if let speed = point.speed {
                    detailRow(label: "Speed", value: String(format: "%.1f km/h", speed * 3.6))
                }

                if let altitude = point.altitude {
                    detailRow(label: "Altitude", value: String(format: "%.0f m", altitude))
                }

                detailRow(
                    label: "Coordinates",
                    value: String(format: "%.5f, %.5f", point.coordinate.latitude, point.coordinate.longitude)
                )
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.3), value: selectedPoint?.id)
        .accessibilityIdentifier("jogging_detail_selected_point")
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: - Route Details Card

    private var routeDetailsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("Route Details", icon: .chartBar)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Divider()

                detailRow(label: "GPS Points", value: "\(routePoints.count)")

                if let maxSpeed = routePoints.compactMap({ $0.speed }).max() {
                    detailRow(label: "Max Speed", value: String(format: "%.1f km/h", maxSpeed * 3.6))
                }

                if let avgSpeed = averageSpeed {
                    detailRow(label: "Avg Speed", value: String(format: "%.1f km/h", avgSpeed * 3.6))
                }

                let elevGain = elevationGain
                if elevGain > 0 {
                    detailRow(label: "Elevation Gain", value: String(format: "%.0f m", elevGain))
                }
            }
        }
        .accessibilityIdentifier("jogging_detail_route_details")
    }

    // MARK: - Helpers

    @ViewBuilder
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var averageSpeed: Double? {
        let speeds = routePoints.compactMap { $0.speed }
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    private var elevationGain: Double {
        var gain = 0.0
        for i in 1..<routePoints.count {
            guard let prev = routePoints[i - 1].altitude,
                  let curr = routePoints[i].altitude else { continue }
            let diff = curr - prev
            if diff > 0 { gain += diff }
        }
        return gain
    }

    /// Computes a map region that fits all the given coordinates with padding.
    private static func regionForCoordinates(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude

        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.005)
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: - Cached DateFormatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - RoutePointItem

/// View-layer model for a single GPS route point.
struct RoutePointItem: Identifiable {
    let id: UUID
    let index: Int
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let speed: Double?
    let distanceFromStart: Double
    let timestamp: Date
}

// MARK: - Previews

#if DEBUG
#Preview("JoggingDetailView") {
    let session = JoggingSessionItem(
        id: UUID(),
        kmpSessionId: UUID().uuidString,
        startDate: Date().addingTimeInterval(-3600),
        distanceMeters: 5230,
        durationSeconds: 1845,
        avgPaceSecondsPerKm: 352,
        caloriesBurned: 420,
        earnedMinutes: 8
    )

    JoggingDetailView(session: session)
}

#Preview("JoggingDetailView - Dark") {
    let session = JoggingSessionItem(
        id: UUID(),
        kmpSessionId: UUID().uuidString,
        startDate: Date(),
        distanceMeters: 2100,
        durationSeconds: 780,
        avgPaceSecondsPerKm: 371,
        caloriesBurned: 180,
        earnedMinutes: 4
    )

    JoggingDetailView(session: session)
        .preferredColorScheme(.dark)
}
#endif
