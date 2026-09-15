import AppKit
import SwiftUI

/// Displays a Dock icon through AppKit so Settings uses the same native image
/// compositing path as `NSApplication.applicationIconImage`.
struct DockIconNativeImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> ClippedImageView {
        ClippedImageView(image: image)
    }

    func updateNSView(_ view: ClippedImageView, context: Context) {
        view.image = image
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: ClippedImageView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? 64,
            height: proposal.height ?? 64
        )
    }
}

/// An explicit clipping host prevents large icon representations from drawing
/// beyond the size SwiftUI assigns to the preview.
final class ClippedImageView: NSView {
    private let imageView = NSImageView()

    var image: NSImage? {
        get { imageView.image }
        set {
            guard imageView.image !== newValue else { return }
            imageView.image = newValue
        }
    }

    init(image: NSImage) {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true

        imageView.image = image
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isEditable = false
        imageView.isEnabled = false
        imageView.animates = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
