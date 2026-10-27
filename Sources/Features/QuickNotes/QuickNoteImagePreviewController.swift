import SwiftUI
import UIKit

struct QuickNoteImagePreviewController: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> QuickNoteImageZoomViewController {
        QuickNoteImageZoomViewController(image: image)
    }

    func updateUIViewController(_ controller: QuickNoteImageZoomViewController, context: Context) {
        controller.updateImage(image)
    }
}

final class QuickNoteImageZoomViewController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var image: UIImage
    private var lastLayoutSize: CGSize = .zero

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true

        view.addSubview(scrollView)
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        if lastLayoutSize != scrollView.bounds.size {
            lastLayoutSize = scrollView.bounds.size
            layoutImage(resetZoom: true)
        } else {
            centerImage()
        }
    }

    func updateImage(_ newImage: UIImage) {
        guard image !== newImage else { return }
        image = newImage
        imageView.image = newImage
        lastLayoutSize = .zero
        view.setNeedsLayout()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    private func layoutImage(resetZoom: Bool) {
        guard scrollView.bounds.width > 0,
              scrollView.bounds.height > 0,
              image.size.width > 0,
              image.size.height > 0 else { return }
        if resetZoom {
            scrollView.zoomScale = 1
        }
        let fitScale = min(scrollView.bounds.width / image.size.width, scrollView.bounds.height / image.size.height)
        let fittedSize = CGSize(width: image.size.width * fitScale, height: image.size.height * fitScale)
        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        scrollView.contentSize = fittedSize
        centerImage()
    }

    private func centerImage() {
        let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
        let verticalInset = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.01 {
            scrollView.setZoomScale(1, animated: true)
            return
        }
        let point = recognizer.location(in: imageView)
        let zoomScale: CGFloat = min(2.5, scrollView.maximumZoomScale)
        let width = scrollView.bounds.width / zoomScale
        let height = scrollView.bounds.height / zoomScale
        let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        scrollView.zoom(to: rect, animated: true)
    }
}
