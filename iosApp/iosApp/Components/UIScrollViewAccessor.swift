import SwiftUI
import UIKit

/// A zero-size background view that walks up the UIKit hierarchy to find the nearest
/// UIScrollView and delivers it via a callback.  Add it as `.background` on a SwiftUI
/// `ScrollView` to get a reference for programmatic offset control.
struct UIScrollViewAccessor: UIViewRepresentable {
    let onFound: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView { FinderView(onFound: onFound) }
    func updateUIView(_ uiView: FinderView, context: Context) {}

    // MARK: - FinderView

    final class FinderView: UIView {
        private let onFound: (UIScrollView) -> Void

        init(onFound: @escaping (UIScrollView) -> Void) {
            self.onFound = onFound
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var view: UIView? = superview
                while let v = view {
                    if let sv = v as? UIScrollView {
                        onFound(sv)
                        return
                    }
                    view = v.superview
                }
            }
        }
    }
}
