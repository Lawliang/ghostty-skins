import AppKit
import QuartzCore

extension MindControl {
    /// Text labels over the Metal view, drawn with a reusable pool of CATextLayers. Never takes the mouse.
    final class LabelOverlayView: NSView {
        private var pool: [CATextLayer] = []
        private struct SizeKey: Hashable {
            let text: String
            let size: CGFloat
            let bold: Bool
        }

        private static var sizeCache: [SizeKey: CGSize] = [:]

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        static func font(size: CGFloat, bold: Bool) -> NSFont {
            .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        }

        /// Text size, cached because labels are re-planned every frame.
        static func measure(_ text: String, _ size: CGFloat, _ bold: Bool) -> CGSize {
            let key = SizeKey(text: text, size: size, bold: bold)
            if let cached = sizeCache[key] { return cached }
            let measured = (text as NSString).size(withAttributes: [.font: font(size: size, bold: bold)])
            let result = CGSize(width: ceil(measured.width), height: ceil(measured.height))
            if sizeCache.count > 20_000 { sizeCache.removeAll() }
            sizeCache[key] = result
            return result
        }

        func show(_ labels: [PlacedLabel]) {
            guard let root = layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            while pool.count < labels.count {
                let text = CATextLayer()
                text.contentsScale = window?.backingScaleFactor ?? 2
                text.foregroundColor = NSColor.white.cgColor
                text.shadowColor = NSColor.black.cgColor
                text.shadowOpacity = 0.8
                text.shadowRadius = 2
                text.shadowOffset = .zero
                text.alignmentMode = .left
                root.addSublayer(text)
                pool.append(text)
            }
            for (i, text) in pool.enumerated() {
                guard i < labels.count else {
                    text.isHidden = true
                    continue
                }
                let label = labels[i]
                text.isHidden = false
                if (text.string as? String) != label.text { text.string = label.text }
                // Reassigning font properties re-rasterises the text; only do it when they change.
                if text.fontSize != label.fontSize || (text.font as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) != label.isBold {
                    text.font = Self.font(size: label.fontSize, bold: label.isBold)
                    text.fontSize = label.fontSize
                }
                text.frame = label.frame
                text.opacity = Float(label.opacity)
            }
            CATransaction.commit()
        }
    }
}
