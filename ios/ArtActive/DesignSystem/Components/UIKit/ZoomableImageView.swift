import SwiftUI
import UIKit

/// Полноэкранное фото на UIScrollView: pinch и double-tap zoom с bounce,
/// интерактивное закрытие свайпом вниз (только когда фото не увеличено).
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage?
    /// 0…1 — насколько фото утянуто вниз (для затухания фона).
    var onDismissProgress: (CGFloat) -> Void
    var onDismiss: () -> Void
    var onZoomChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        view.delegate = context.coordinator
        view.coordinator = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDismissPan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.dismissPan = pan

        view.imageView.image = image
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        context.coordinator.parent = self
        if view.imageView.image !== image {
            view.imageView.image = image
            view.setZoomScale(1, animated: false)
            view.setNeedsLayout()
        }
    }

    final class ZoomScrollView: UIScrollView {
        let imageView = UIImageView()
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            minimumZoomScale = 1
            maximumZoomScale = 4
            bouncesZoom = true
            showsVerticalScrollIndicator = false
            showsHorizontalScrollIndicator = false
            contentInsetAdjustmentBehavior = .never
            backgroundColor = .clear
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = true
            imageView.isAccessibilityElement = true
            imageView.accessibilityTraits = .image
            addSubview(imageView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard zoomScale == minimumZoomScale else { return }
            imageView.frame = fittedFrame()
            contentSize = imageView.frame.size
            centerContent()
        }

        func fittedFrame() -> CGRect {
            guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0 else {
                return bounds
            }
            let scale = min(bounds.width / size.width, bounds.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            return CGRect(origin: .zero, size: fitted)
        }

        func centerContent() {
            let offsetX = max((bounds.width - contentSize.width) / 2, 0)
            let offsetY = max((bounds.height - contentSize.height) / 2, 0)
            imageView.center = CGPoint(x: contentSize.width / 2 + offsetX, y: contentSize.height / 2 + offsetY)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableImageView
        weak var dismissPan: UIPanGestureRecognizer?

        init(parent: ZoomableImageView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerContent()
            parent.onZoomChange(scrollView.zoomScale > scrollView.minimumZoomScale + 0.01)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? ZoomScrollView else { return }
            if view.zoomScale > view.minimumZoomScale {
                view.setZoomScale(view.minimumZoomScale, animated: true)
            } else {
                let point = recognizer.location(in: view.imageView)
                let scale = min(view.maximumZoomScale, 2.5)
                let size = CGSize(width: view.bounds.width / scale, height: view.bounds.height / scale)
                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                view.zoom(to: rect, animated: true)
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }

        @objc func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view as? ZoomScrollView else { return }
            let translation = recognizer.translation(in: view)
            let progress = min(max(translation.y / 300, 0), 1)
            switch recognizer.state {
            case .changed:
                view.imageView.transform = CGAffineTransform(translationX: translation.x * 0.3, y: max(translation.y, 0))
                    .scaledBy(x: 1 - progress * 0.2, y: 1 - progress * 0.2)
                parent.onDismissProgress(progress)
            case .ended, .cancelled:
                let velocity = recognizer.velocity(in: view).y
                if translation.y > 120 || velocity > 900 {
                    parent.onDismiss()
                } else {
                    UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                        view.imageView.transform = .identity
                    }
                    parent.onDismissProgress(0)
                }
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard recognizer === dismissPan,
                  let pan = recognizer as? UIPanGestureRecognizer,
                  let view = pan.view as? UIScrollView else { return true }
            guard view.zoomScale <= view.minimumZoomScale + 0.01 else { return false }
            let velocity = pan.velocity(in: view)
            return velocity.y > 0 && abs(velocity.y) > abs(velocity.x) * 1.2
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
