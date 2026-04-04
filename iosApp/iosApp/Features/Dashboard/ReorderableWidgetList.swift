import SwiftUI

// MARK: - ReorderableWidgetList

/// Custom drag-reorder list that decides swap direction based on the **hovered** widget's
/// vertical midpoint rather than the dragged widget's midpoint. This prevents the jitter
/// that SwiftUI's built-in `List` `.onMove` causes when a small widget is dragged over a tall one.
///
/// While dragging near the top or bottom of the screen the list auto-scrolls, just like
/// the system drag-and-drop behaviour.
struct ReorderableWidgetList<Content: View>: View {

    @Binding var items: [DashboardItem]
    @Binding var isDragging: Bool
    let isEditing: Bool
    let onPersist: () -> Void
    let onDelete: (Int) -> Void
    var onEdgeScroll: ((CGFloat) -> CGFloat)? = nil
    var listGlobalOriginY: (() -> CGFloat)? = nil
    @ViewBuilder let content: (DashboardItem) -> Content

    @State private var draggedItem: DashboardItem?
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartY: CGFloat = 0
    @State private var framesHolder = ItemFramesHolder()
    @State private var itemOrderAtDragStart: [DashboardItem]?
    @State private var blockWidgetChromeAfterOrderChange = false
    @StateObject private var edgeScroller = EdgeScrollHelper()

    private let coordinateSpace = "reorderArea"

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    widgetRow(item: item, index: index)
                }
            }
            .coordinateSpace(name: coordinateSpace)
            .onPreferenceChange(ItemFramePreferenceKey.self) { newFrames in
                framesHolder.frames = newFrames
            }

            if let dragged = draggedItem {
                content(dragged)
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
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.82), value: items.map(\.id))
    }

    @ViewBuilder
    private func widgetRow(item: DashboardItem, index: Int) -> some View {
        let isDragged = draggedItem == item
        let chromeHitTesting = !isDragged && !blockWidgetChromeAfterOrderChange

        content(item)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.bottom, AppSpacing.md)
            .opacity(isDragged ? 0.0 : 1.0)
            .allowsHitTesting(chromeHitTesting)
            .disabled(!chromeHitTesting)
            .overlay(alignment: .topTrailing) {
                if isEditing && draggedItem == nil {
                    deleteButton(index: index)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: ItemFramePreferenceKey.self,
                            value: [item.id: geo.frame(in: .named(coordinateSpace))]
                        )
                }
            )
            .simultaneousGesture(longPressDrag(item: item))
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

    private func longPressDrag(item: DashboardItem) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if let drag {
                        if draggedItem == nil {
                            itemOrderAtDragStart = items
                            draggedItem = item
                            isDragging = true
                            dragStartY = framesHolder.frames[item.id]?.minY ?? 0
                            dragOffset = .zero
                            edgeScroller.reset()
                            edgeScroller.fingerStartScreenY = drag.location.y
                            edgeScroller.contentOriginAtDragStart = listGlobalOriginY?() ?? 0
                            DashboardHaptics.mediumImpact()
                        }

                        dragOffset = drag.translation

                        let fingerScreenY = drag.location.y
                        edgeScroller.lastFingerScreenY = fingerScreenY
                        let delta = edgeScrollDelta(for: fingerScreenY)

                        let localY = fingerScreenY - edgeScroller.contentOriginAtDragStart + edgeScroller.compensation
                        checkForSwap(draggedItem: item, fingerLocalY: localY)

                        edgeScroller.onScroll = { [onEdgeScroll] tick in
                            onEdgeScroll?(tick) ?? 0
                        }
                        let scrollerRef = edgeScroller
                        edgeScroller.onSwapCheck = {
                            let localYFromTimer = scrollerRef.lastFingerScreenY - scrollerRef.contentOriginAtDragStart + scrollerRef.compensation
                            checkForSwap(draggedItem: item, fingerLocalY: localYFromTimer)
                        }
                        edgeScroller.update(velocity: delta)
                    } else if draggedItem == nil {
                        DashboardHaptics.mediumImpact()
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                guard draggedItem != nil else { return }

                let startOrder = itemOrderAtDragStart
                itemOrderAtDragStart = nil
                let orderChanged = startOrder.map { $0 != items } ?? false

                draggedItem = nil
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

    private func edgeScrollDelta(for screenY: CGFloat) -> CGFloat {
        let safeTop = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 60
        let safeBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
        let screenHeight = UIScreen.main.bounds.height

        let zone: CGFloat = 80
        let maxSpeed: CGFloat = 12

        let topThreshold = safeTop + zone
        let bottomThreshold = screenHeight - safeBottom - zone

        if screenY < topThreshold {
            let t = max(0, min(1, (topThreshold - screenY) / zone))
            return -maxSpeed * t * t
        }
        if screenY > bottomThreshold {
            let t = max(0, min(1, (screenY - bottomThreshold) / zone))
            return maxSpeed * t * t
        }
        return 0
    }

    // MARK: - Swap Logic

    private func checkForSwap(draggedItem: DashboardItem, fingerLocalY: CGFloat) {
        guard let draggedIndex = items.firstIndex(of: draggedItem) else { return }

        for (index, targetItem) in items.enumerated() {
            guard targetItem != draggedItem,
                  let targetFrame = framesHolder.frames[targetItem.id]
            else { continue }

            let targetMidY = targetFrame.midY
            let movingDown = index > draggedIndex
            let movingUp = index < draggedIndex

            if movingDown && fingerLocalY > targetMidY {
                var updated = items
                updated.remove(at: draggedIndex)
                updated.insert(draggedItem, at: min(index, updated.count))
                items = updated
                DashboardHaptics.lightImpact()
                return
            }

            if movingUp && fingerLocalY < targetMidY {
                var updated = items
                updated.remove(at: draggedIndex)
                updated.insert(draggedItem, at: index)
                items = updated
                DashboardHaptics.lightImpact()
                return
            }
        }
    }
}

// MARK: - ItemFramesHolder

private final class ItemFramesHolder {
    var frames: [String: CGRect] = [:]
}

// MARK: - EdgeScrollHelper

private final class EdgeScrollHelper: ObservableObject {
    private var timer: Timer?
    var velocity: CGFloat = 0
    var onScroll: ((CGFloat) -> CGFloat)?
    var onSwapCheck: (() -> Void)?
    var fingerStartScreenY: CGFloat = 0
    var contentOriginAtDragStart: CGFloat = 0
    var lastFingerScreenY: CGFloat = 0

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
            let actualDelta = self.onScroll?(self.velocity) ?? 0
            if actualDelta != 0 {
                self.compensation += actualDelta
            }
            self.onSwapCheck?()
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
        lastFingerScreenY = 0
        onScroll = nil
        onSwapCheck = nil
    }
}

// MARK: - Preference Keys

private struct ItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
