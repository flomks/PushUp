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
    /// Returns the list's current global-screen-Y origin. Called once when drag starts
    /// to compute edge-scroll zones without a continuously-running GeometryReader.
    var listGlobalOriginY: (() -> CGFloat)? = nil
    @ViewBuilder let content: (DashboardWidgetKind) -> Content

    @State private var draggedKind: DashboardWidgetKind?
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartY: CGFloat = 0
    /// Widget frames in the named coordinate space. Stored as a class so the
    /// continuous preference updates from GeometryReaders don't trigger re-renders.
    /// Only read from gesture callbacks (drag start / swap detection).
    @State private var framesHolder = WidgetFramesHolder()
    /// Snapshot when reorder lift begins; used to detect if the list order actually changed.
    @State private var widgetOrderAtDragStart: [DashboardWidgetKind]?
    /// After a successful reorder, block widget chrome for one run loop so touch-up does not trigger buttons / links.
    @State private var blockWidgetChromeAfterOrderChange = false
    /// Reference-type helper that owns the auto-scroll Timer and tracks cumulative scroll compensation.
    /// Using a class (reference type) so Timer callbacks can mutate it and trigger view updates.
    @StateObject private var edgeScroller = EdgeScrollHelper()

    private let coordinateSpace = "reorderArea"

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ForEach(Array(widgets.enumerated()), id: \.element) { index, kind in
                    widgetRow(kind: kind, index: index)
                }
            }
            .coordinateSpace(name: coordinateSpace)
            // Single preference observer at the VStack level – updates the class holder
            // without triggering SwiftUI re-renders (framesHolder identity stays the same).
            .onPreferenceChange(WidgetFramePreferenceKey.self) { newFrames in
                framesHolder.frames = newFrames
            }

            if draggedKind != nil {
                content(draggedKind!)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.bottom, AppSpacing.md)
                    .opacity(0.9)
                    .scaleEffect(1.03)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .offset(y: dragStartY + dragOffset.height + edgeScroller.compensation)
                    .allowsHitTesting(false)
                    .transition(.identity)
            }
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
            .sequenced(before: DragGesture(coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if let drag {
                        // First movement after long press – lift the widget.
                        if draggedKind == nil {
                            widgetOrderAtDragStart = widgets
                            draggedKind = kind
                            isDragging = true
                            dragStartY = framesHolder.frames[kind]?.minY ?? 0
                            dragOffset = .zero
                            edgeScroller.reset()
                            // Record the finger's initial screen Y and the list's content
                            // origin so we can convert between screen and local coordinates.
                            edgeScroller.fingerStartScreenY = drag.location.y
                            edgeScroller.contentOriginAtDragStart = listGlobalOriginY?() ?? 0
                            DashboardHaptics.mediumImpact()
                        }

                        // drag.translation is in global coordinates now — use it directly.
                        dragOffset = drag.translation

                        // The finger's actual screen position — drag.location.y is global.
                        let fingerScreenY = drag.location.y
                        let delta = edgeScrollDelta(for: fingerScreenY)

                        // Convert finger screen Y → local coordinate space for swap detection.
                        // local Y = fingerScreenY - contentOriginAtDragStart + totalScrollApplied
                        let localY = fingerScreenY - edgeScroller.contentOriginAtDragStart + edgeScroller.compensation
                        checkForSwap(draggedKind: kind, fingerLocalY: localY)

                        // Set up scroll callback: each tick scrolls the content and compensates the ghost.
                        edgeScroller.onScroll = { [onEdgeScroll] tick in
                            onEdgeScroll?(tick)
                        }
                        edgeScroller.update(velocity: delta)
                    } else if draggedKind == nil {
                        DashboardHaptics.mediumImpact()
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                guard draggedKind != nil else { return }

                let startOrder = widgetOrderAtDragStart
                widgetOrderAtDragStart = nil
                let orderChanged = startOrder.map { $0 != widgets } ?? false

                draggedKind = nil
                isDragging = false
                dragOffset = .zero
                edgeScroller.reset()

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
        let safeTop = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 60
        let safeBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
        let screenHeight = UIScreen.main.bounds.height

        // Only activate within 80pt of the safe-area edges — not the absolute screen edge.
        // This prevents the zone from reaching the middle of the screen.
        let zone: CGFloat = 80
        let maxSpeed: CGFloat = 12

        let topThreshold = safeTop + zone
        let bottomThreshold = screenHeight - safeBottom - zone

        if screenY < topThreshold {
            // How far into the zone (0 = edge of zone, 1 = at safe area edge)
            let t = max(0, min(1, (topThreshold - screenY) / zone))
            // Ease-in curve so it starts gently
            return -maxSpeed * t * t
        }
        if screenY > bottomThreshold {
            let t = max(0, min(1, (screenY - bottomThreshold) / zone))
            return maxSpeed * t * t
        }
        return 0
    }

    // MARK: - Swap Logic

    /// Swap decision uses the **hovered widget's** vertical center, not the dragged widget's.
    private func checkForSwap(draggedKind: DashboardWidgetKind, fingerLocalY: CGFloat) {
        guard let draggedIndex = widgets.firstIndex(of: draggedKind) else { return }

        let fingerY = fingerLocalY

        for (targetKind, targetFrame) in framesHolder.frames {
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

// MARK: - WidgetFramesHolder

/// Stores widget frames by reference so `onPreferenceChange` updates don't trigger
/// SwiftUI re-renders. The @State wrapper sees the same object identity on every mutation.
private final class WidgetFramesHolder {
    var frames: [DashboardWidgetKind: CGRect] = [:]
}

// MARK: - EdgeScrollHelper

/// ObservableObject wrapper owning a repeating Timer for auto-scroll.
/// Stored in `@StateObject` so SwiftUI re-renders when `compensation` changes,
/// keeping the ghost widget under the finger during programmatic scrolling.
private final class EdgeScrollHelper: ObservableObject {
    private var timer: Timer?
    var velocity: CGFloat = 0
    var onScroll: ((CGFloat) -> Void)?
    /// The finger's screen Y when the drag started.
    var fingerStartScreenY: CGFloat = 0
    /// The list content's global Y origin when the drag started.
    var contentOriginAtDragStart: CGFloat = 0

    /// Cumulative content-scroll applied via edge-scroll while dragging.
    /// The ghost widget lives inside the scroll content, so each programmatic setContentOffset
    /// shifts it on screen. This published value offsets the ghost back to stay under the finger.
    @Published var compensation: CGFloat = 0

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
            // Update compensation on the main thread — @Published triggers SwiftUI re-render
            // so the ghost widget offset stays in sync with the scroll position.
            self.compensation += self.velocity
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        velocity = 0
    }

    func reset() {
        stop()
        compensation = 0
        fingerStartScreenY = 0
        contentOriginAtDragStart = 0
        onScroll = nil
    }
}

// MARK: - Preference Keys

private struct WidgetFramePreferenceKey: PreferenceKey {
    static var defaultValue: [DashboardWidgetKind: CGRect] = [:]
    static func reduce(value: inout [DashboardWidgetKind: CGRect], nextValue: () -> [DashboardWidgetKind: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

