import SwiftUI

// MARK: - DashboardGridWidget

/// Renders a 1×2 or 2×2 grid of compact widget cells inside a single dashboard chrome container.
/// Empty slots show a dashed "+" placeholder; in edit mode, filled slots show an "×" overlay.
struct DashboardGridWidget<CellContent: View>: View {

    let size: DashboardGridSize
    let slots: [DashboardWidgetKind?]
    let isEditing: Bool
    let onAddToSlot: (Int) -> Void
    let onRemoveFromSlot: (Int) -> Void
    @ViewBuilder let cellContent: (DashboardWidgetKind) -> CellContent

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<size.rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<size.columns, id: \.self) { col in
                        let index = row * size.columns + col
                        cellView(at: index)
                    }
                }
            }
        }
        .padding(14)
        .dashboardWidgetChrome()
    }

    @ViewBuilder
    private func cellView(at index: Int) -> some View {
        if index < slots.count, let kind = slots[index] {
            filledCell(kind: kind, index: index)
        } else {
            emptySlotButton(index: index)
        }
    }

    private func filledCell(kind: DashboardWidgetKind, index: Int) -> some View {
        cellContent(kind)
            .overlay(alignment: .topTrailing) {
                if isEditing {
                    Button {
                        DashboardHaptics.lightImpact()
                        onRemoveFromSlot(index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
    }

    private func emptySlotButton(index: Int) -> some View {
        Button {
            DashboardHaptics.lightImpact()
            onAddToSlot(index)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(DashboardWidgetChrome.labelMuted)

                Text("Add")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DashboardWidgetChrome.labelMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.1),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
