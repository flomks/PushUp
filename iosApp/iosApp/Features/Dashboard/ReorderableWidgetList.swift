import SwiftUI

// MARK: - ReorderableWidgetList

/// Custom drag-reorder list that decides swap direction based on the **hovered** widget's
/// vertical midpoint rather than the dragged widget's midpoint. This prevents the jitter
/// that SwiftUI's built-in `List` `.onMove` causes when a small widget is dragged over a tall one.
struct ReorderableWidgetList<Content: View>: View {

    @Binding var widgets: [DashboardWidgetKind]
    @Binding var isDragging: Bool
    let isEditing: Bool
    let onPersist: () -> Void
    let onDelete: (Int) -> Void
    @ViewBuilder let content: (DashboardWidgetKind) -> Content

    @State private var draggedKind: DashboardWidgetKind?
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartY: CGFloat = 0
    @State private var frames: [DashboardWidgetKind: CGRect] = [:]
    /// Long-press entered reorder (widget lifted); release must not activate NavigationLinks / buttons.
    @State private var reorderLiftActiveThisGesture = false
    /// Short cooldown so the touch-up after a reorder cannot trigger widget actions.
    @State private var suppressWidgetContentInteractions = false

    private let coordinateSpace = "reorderArea"
    private let postDragInteractionSuppressionSeconds: TimeInterval = 0.45

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ForEach(Array(widgets.enumerated()), id: \.element) { index, kind in
                    widgetRow(kind: kind, index: index)
                }
            }
            .coordinateSpace(name: coordinateSpace)

            if draggedKind != nil {
                content(draggedKind!)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.bottom, AppSpacing.md)
                    .opacity(0.9)
                    .scaleEffect(1.03)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .offset(y: dragStartY + dragOffset.height)
                    .allowsHitTesting(false)
                    .transition(.identity)
            }
        }
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.82), value: widgets)
    }

    @ViewBuilder
    private func widgetRow(kind: DashboardWidgetKind, index: Int) -> some View {
        let isDragged = draggedKind == kind
        let blockWidgetChromeHits = isDragged || isDragging || suppressWidgetContentInteractions

        ZStack(alignment: .topTrailing) {
            content(kind)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.bottom, AppSpacing.md)
                .opacity(isDragged ? 0.0 : 1.0)
                // No hit testing on widget chrome while dragging, right after drop, or on the invisible slot.
                // (Avoid `.disabled` here — it dims the whole card during reorder.)
                .allowsHitTesting(!blockWidgetChromeHits)

            if isEditing && draggedKind == nil {
                deleteButton(index: index)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: WidgetFramePreferenceKey.self,
                        value: [kind: geo.frame(in: .named(coordinateSpace))]
                    )
            }
        )
        // High priority so the reorder gesture wins over links/buttons; simultaneousGesture lets taps fire on release.
        .highPriorityGesture(longPressDrag(kind: kind))
        .onPreferenceChange(WidgetFramePreferenceKey.self) { newFrames in
            frames.merge(newFrames) { _, new in new }
        }
    }

    private func deleteButton(index: Int) -> some View {
        Button {
            onDelete(index)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .background(Circle().fill(.white).padding(4))
        }
        .offset(x: -4, y: -4)
        .buttonStyle(.plain)
    }

    // MARK: - Gesture

    private func longPressDrag(kind: DashboardWidgetKind) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(coordinateSpace: .named(coordinateSpace)))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if draggedKind == nil {
                        draggedKind = kind
                        isDragging = true
                        reorderLiftActiveThisGesture = true
                        dragStartY = frames[kind]?.minY ?? 0
                        dragOffset = .zero
                        DashboardHaptics.mediumImpact()
                    }
                    if let drag {
                        dragOffset = drag.translation
                        checkForSwap(draggedKind: kind, dragLocation: drag.location)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                let shouldBlockLiftAsTap = reorderLiftActiveThisGesture
                draggedKind = nil
                isDragging = false
                dragOffset = .zero
                reorderLiftActiveThisGesture = false
                if shouldBlockLiftAsTap {
                    suppressWidgetContentInteractions = true
                    let delay = postDragInteractionSuppressionSeconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        suppressWidgetContentInteractions = false
                    }
                }
                onPersist()
            }
    }

    /// Swap decision uses the **hovered widget's** vertical center, not the dragged widget's.
    private func checkForSwap(draggedKind: DashboardWidgetKind, dragLocation: CGPoint) {
        guard let draggedIndex = widgets.firstIndex(of: draggedKind) else { return }

        let fingerY = dragLocation.y

        for (targetKind, targetFrame) in frames {
            guard targetKind != draggedKind,
                  let targetIndex = widgets.firstIndex(of: targetKind)
            else { continue }

            let targetMidY = targetFrame.midY

            let movingDown = targetIndex > draggedIndex
            let movingUp = targetIndex < draggedIndex

            if movingDown && fingerY > targetMidY {
                var updated = widgets
                updated.remove(at: draggedIndex)
                updated.insert(draggedKind, at: min(targetIndex, updated.count))
                widgets = updated
                DashboardHaptics.lightImpact()
                return
            }

            if movingUp && fingerY < targetMidY {
                var updated = widgets
                updated.remove(at: draggedIndex)
                updated.insert(draggedKind, at: targetIndex)
                widgets = updated
                DashboardHaptics.lightImpact()
                return
            }
        }
    }
}

// MARK: - WidgetFramePreferenceKey

private struct WidgetFramePreferenceKey: PreferenceKey {
    static var defaultValue: [DashboardWidgetKind: CGRect] = [:]
    static func reduce(value: inout [DashboardWidgetKind: CGRect], nextValue: () -> [DashboardWidgetKind: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
