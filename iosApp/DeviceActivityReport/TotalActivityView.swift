import SwiftUI

// MARK: - AppUsageReportView
//
// The SwiftUI view rendered inside the DeviceActivityReport container.
// Receives an AppUsageConfiguration (processed by AppUsageReport.makeConfiguration)
// and renders a per-app usage list with real app names, icons, and usage bars.
//
// This view is injected directly into the main app's view hierarchy by the system.
// It uses the design language of the main app (system fonts, system colors) so it
// blends seamlessly regardless of light/dark mode.

struct AppUsageReportView: View {

    let configuration: AppUsageConfiguration

    var body: some View {
        if configuration.entries.isEmpty {
            emptyView
        } else {
            appList
        }
    }

    // MARK: - App List

    private var appList: some View {
        VStack(spacing: 0) {
            ForEach(Array(configuration.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider()
                        .padding(.leading, 52)
                }
                appRow(entry: entry)
            }
        }
    }

    private func appRow(_ entry: AppUsageEntry) -> some View {
        HStack(spacing: 12) {
            // Real app icon from the OS via Label.iconOnly
            entry.label
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                // Real app name from the OS via Label.titleOnly
                entry.label
                    .labelStyle(.titleOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                // Category label (if available)
                if !entry.categoryName.isEmpty {
                    Text(entry.categoryName)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }

                // Usage bar proportional to total
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(.systemFill))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(barColor(for: entry.duration))
                            .frame(
                                width: geo.size.width * barFraction(for: entry.duration),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
            }

            Spacer(minLength: 8)

            Text(formatDuration(entry.duration))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.primary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.badge")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.secondary)
                .symbolRenderingMode(.hierarchical)

            Text("No app usage recorded yet today.")
                .font(.system(size: 14))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func barFraction(for duration: TimeInterval) -> CGFloat {
        guard configuration.totalDuration > 0 else { return 0 }
        return min(1.0, CGFloat(duration / configuration.totalDuration))
    }

    private func barColor(for duration: TimeInterval) -> Color {
        let fraction = duration / max(1, configuration.totalDuration)
        if fraction >= 0.5 { return .red }
        if fraction >= 0.3 { return .orange }
        return .blue
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 { return "\(seconds)s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Preview

#Preview("AppUsageReportView") {
    AppUsageReportView(configuration: AppUsageConfiguration(entries: [], totalDuration: 0))
}
