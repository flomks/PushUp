import Foundation

// MARK: - DashboardGridSize

/// Grid layout variants available on the dashboard.
enum DashboardGridSize: String, Hashable, CaseIterable {
    case oneByTwo = "1x2"
    case twoByTwo = "2x2"

    var capacity: Int {
        switch self {
        case .oneByTwo: return 2
        case .twoByTwo: return 4
        }
    }

    var columns: Int { 2 }

    var rows: Int {
        switch self {
        case .oneByTwo: return 1
        case .twoByTwo: return 2
        }
    }

    var title: String {
        switch self {
        case .oneByTwo: return "1×2 Grid"
        case .twoByTwo: return "2×2 Grid"
        }
    }

    var subtitle: String {
        switch self {
        case .oneByTwo: return "2 compact widgets side by side"
        case .twoByTwo: return "4 compact widgets in a square"
        }
    }

    var systemImage: String {
        switch self {
        case .oneByTwo: return "rectangle.split.1x2.fill"
        case .twoByTwo: return "rectangle.split.2x2.fill"
        }
    }
}

// MARK: - DashboardItem

/// A single entry in the dashboard layout — either a standalone widget or a grid of compact widgets.
enum DashboardItem: Identifiable, Hashable {
    case widget(DashboardWidgetKind)
    case grid(id: UUID, size: DashboardGridSize, slots: [DashboardWidgetKind?])

    var id: String {
        switch self {
        case .widget(let kind): return kind.rawValue
        case .grid(let id, _, _): return "grid-\(id.uuidString)"
        }
    }

    var isGrid: Bool {
        if case .grid = self { return true }
        return false
    }

    /// All widget kinds actively used by this item.
    var usedWidgetKinds: Set<DashboardWidgetKind> {
        switch self {
        case .widget(let kind):
            return [kind]
        case .grid(_, _, let slots):
            return Set(slots.compactMap { $0 })
        }
    }
}
