import SwiftUI

// MARK: - ReorderableWidgetList

/// Custom drag-reorder list that decides swap direction based on the **hovered** widget's
/// vertical midpoint rather than the dragged widget's midpoint. This prevents the jitter
/// that SwiftUI's built-in `List` `.onMove` causes when a small widget is dragged over a tall one.
///
/// While dragging near the top or bottom of the screen the list auto-scrolls, just like
/// the system drag-and-drop behaviour.
struct ReorderableWidgetList<Content: View>: View {

    @Binding var widgets: [DashboardWidgetKind]
    @Binding var isDragging: Bool
    let isEditing: Bool
    let onPersist: () -> Void
    let onDelete: (Int) -> Void
    /// Called on every ~60 Hz tick while the finger is in an edge-scroll zone.
    /// The parent is responsible for adjusting the scroll view's content offset by `delta` points.
    var onEdgeScroll: ((CGFloat) -> Void)? = nil
    @ViewBuilder let content: (DashboardWidgetKind) -> Content

    @State private var draggedKind: DashboardWidgetKind?
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartY: CGFloat = 0
    /// Cumulative content-scroll applied via edge-scroll while dragging.
    /// The ghost widget lives inside the scroll content, so each programmatic setContentOffset
    /// shifts it on screen. This value offsets the ghost back to stay under the finger.
    @State private var edgeScrollCompensation: CGFloat = 0
    @State private var frames: [DashboardWidgetKind: CGRect] = [:]
    /// Snapshot when reorder lift begins; used to detect if the list order actually changed.
    @State private var widgetOrderAtDragStart: [DashboardWidgetKind]?
    /// After a successful reorder, block widget chrome for one run loop so touch-up does not trigger buttons / links.
    @State private var blockWidgetChromeAfterOrderChange = false
    /// Global screen Y of the list's top edge.
    /// Stored as a class so mutations don't change the @State identity → no SwiftUI re-render on every
    /// scroll frame, while gesture callbacks always read the up-to-date value.
    @State private var listOriginHolder = ListOriginHolder()
    /// Reference-type helper that owns the auto-scroll Timer.
    @State private var edgeScroller = EdgeScrollHelper()

    private let coordinateSpace = "reorderArea"

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ForEach(Array(widgets.enumerated()), id: \.element) { index, kind in
                    widgetRow(kind: kind, index: index)
                }
            }
            .coordinateSpace(name: coordinateSpace)
            // Single preference observer at the VStack level – receives all widget frames merged
            // in one pass instead of N separate onPreferenceChange callbacks (one per row).
            .onPreferenceChange(WidgetFramePreferenceKey.self) { newFrames in
                frames = newFrames
            }

            if draggedKind != nil {
                content(draggedKind!)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.bottom, AppSpacing.md)
                    .opacity(0.9)
                    .scaleEffect(1.03)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .offset(y: dragStartY + dragOffset.height + edgeScrollCompensation)
                    .allowsHitTesting(false)
                    .transition(.identity)
            }
        }
        // Track the list's position in global (screen) coordinates so we can translate
        // drag.location.y → screen Y for edge-zone detection.
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: ListGlobalOriginYPreferenceKey.self,
                        value: geo.frame(in: .global).minY
                    )
            }
        )
        .onPreferenceChange(ListGlobalOriginYPreferenceKey.self) { y in
            listOriginHolder.y = y  // mutates the class instance → no @State identity change → no re-render
        }
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.82), value: widgets)
    }

    @ViewBuilder
    private func widgetRow(kind: DashboardWidgetKind, index: Int) -> some View {
        let isDragged = draggedKind == kind
        let chromeHitTesting = !isDragged && !blockWidgetChromeAfterOrderChange

        content(kind)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.bottom, AppSpacing.md)
            .opacity(isDragged ? 0.0 : 1.0)
            // Invisible list slot must not receive touch-up (otherwise NavigationLink / taps fire on drop).
            // After a real reorder, briefly drop hits so the same touch-up is not a tap on the widget.
            .allowsHitTesting(chromeHitTesting)
            // .disabled() prevents button *actions* from firing even when a button's gesture already
            // started tracking the touch before the drag began. allowsHitTesting(false) alone is not
            // enough because it only blocks new touches, not ones already in flight.
            .disabled(!chromeHitTesting)
            .overlay(alignment: .topTrailing) {
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
            .simultaneousGesture(longPressDrag(kind: kind))
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
                    if let drag {
                        // First movement after long press – lift the widget.
                        if draggedKind == nil {
                            widgetOrderAtDragStart = widgets
                            draggedKind = kind
                            isDragging = true
                            dragStartY = frames[kind]?.minY ?? 0
                            dragOffset = .zero
                        }
                        dragOffset = drag.translation
                        checkForSwap(draggedKind: kind, dragLocation: drag.location)

                        // Convert local Y → screen Y and update auto-scroll velocity.
                        let screenY = listOriginHolder.y + drag.location.y
                        let delta = edgeScrollDelta(for: screenY)
                        // Wrap onEdgeScroll so the ghost offset compensates for each scroll tick:
                        // the ghost lives inside the scroll content, so setContentOffset shifts it
                        // on screen. Adding the same delta to edgeScrollCompensation keeps it
                        // under the finger. @State's backing storage is a reference type, so this
                        // mutation from inside the timer closure reaches the real state.
                        edgeScroller.onScroll = { [onEdgeScroll] tick in
                            onEdgeScroll?(tick)
                            edgeScrollCompensation += tick
                        }
                        edgeScroller.update(velocity: delta)
                    } else if draggedKind == nil {
                        // Long press fired but no movement yet – haptic only, no state change.
                        // This avoids leaving draggedKind/isDragging set if the user releases
                        // without ever moving (onEnded is not guaranteed to fire in that case).
                        DashboardHaptics.mediumImpact()
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                guard draggedKind != nil else {
                    // Long press without any drag movement – nothing to clean up.
                    return
                }

                let startOrder = widgetOrderAtDragStart
                widgetOrderAtDragStart = nil
                let orderChanged = startOrder.map { $0 != widgets } ?? false

                draggedKind = nil
                isDragging = false
                dragOffset = .zero
                edgeScrollCompensation = 0
                edgeScroller.stop()

                if orderChanged {
                    blockWidgetChromeAfterOrderChange = true
                    DispatchQueue.main.async {
                        blockWidgetChromeAfterOrderChange = false
                    }
                }

                onPersist()
            }
    }

    // MARK: - Edge Scroll

    /// Returns the scroll delta (pts/tick at ~60 Hz) for the given screen Y position.
    /// Negative = scroll up, positive = scroll down, zero = no scroll.
    private func edgeScrollDelta(for screenY: CGFloat) -> CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        let zone: CGFloat = 120   // activation zone in points from each edge
        let maxSpeed: CGFloat = 10 // max points per 60 Hz tick

        if screenY < zone {
            let t = max(0, min(1, 1 - screenY / zone))
            return -maxSpeed * t
        }
        if screenY > screenHeight - zone {
            let t = max(0, min(1, (screenY - (screenHeight - zone)) / zone))
            return maxSpeed * t
        }
        return 0
    }

    // MARK: - Swap Logic

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

// MARK: - ListOriginHolder

/// Stores the list's global screen-Y origin without triggering SwiftUI re-renders on mutation.
/// Because this is a class (reference type), mutating `.y` does not change the @State identity,
/// so SwiftUI does not schedule a new render pass on every scroll frame.
private final class ListOriginHolder {
    var y: CGFloat = 0
}

// MARK: - EdgeScrollHelper

/// Reference-type wrapper owning a repeating Timer for auto-scroll.
/// Stored in `@State` so it survives SwiftUI re-renders without being recreated.
private final class EdgeScrollHelper {
    private var timer: Timer?
    var velocity: CGFloat = 0
    var onScroll: ((CGFloat) -> Void)?

    func update(velocity: CGFloat) {
        self.velocity = velocity
        if velocity == 0 {
            stop()
        } else if timer == nil {
            start()
        }
    }

    private func start() {
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self, self.velocity != 0 else { return }
            self.onScroll?(self.velocity)
        }
        // Use .common so the timer fires even while the user is actively touching the screen.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        velocity = 0
    }
}

// MARK: - Preference Keys

private struct WidgetFramePreferenceKey: PreferenceKey {
    static var defaultValue: [DashboardWidgetKind: CGRect] = [:]
    static func reduce(value: inout [DashboardWidgetKind: CGRect], nextValue: () -> [DashboardWidgetKind: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ListGlobalOriginYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
