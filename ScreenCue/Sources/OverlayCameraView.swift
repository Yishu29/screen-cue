import AppKit
import AVFoundation

final class OverlayCameraView: NSView {
    private enum DiagonalCursorDirection {
        case slash
        case backslash
    }

    private let previewContainerLayer = CALayer()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let cameraManager: CameraManager
    private let resizeGuideLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?

    private let minSize: CGFloat = 120
    private let maxSize: CGFloat = 360
    private static let diagonalResizeCursorSlash: NSCursor = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: NSPoint(x: 3, y: 15))
        path.line(to: NSPoint(x: 15, y: 3))
        // Arrow heads
        path.move(to: NSPoint(x: 3, y: 10))
        path.line(to: NSPoint(x: 3, y: 15))
        path.line(to: NSPoint(x: 8, y: 15))
        path.move(to: NSPoint(x: 10, y: 3))
        path.line(to: NSPoint(x: 15, y: 3))
        path.line(to: NSPoint(x: 15, y: 8))
        path.stroke()

        NSColor.black.withAlphaComponent(0.4).setStroke()
        let shadowPath = NSBezierPath()
        shadowPath.lineWidth = 1
        shadowPath.move(to: NSPoint(x: 2, y: 14))
        shadowPath.line(to: NSPoint(x: 14, y: 2))
        shadowPath.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: 9))
    }()

    private static let diagonalResizeCursorBackslash: NSCursor = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: NSPoint(x: 3, y: 3))
        path.line(to: NSPoint(x: 15, y: 15))
        // Arrow heads
        path.move(to: NSPoint(x: 3, y: 8))
        path.line(to: NSPoint(x: 3, y: 3))
        path.line(to: NSPoint(x: 8, y: 3))
        path.move(to: NSPoint(x: 10, y: 15))
        path.line(to: NSPoint(x: 15, y: 15))
        path.line(to: NSPoint(x: 15, y: 10))
        path.stroke()

        NSColor.black.withAlphaComponent(0.4).setStroke()
        let shadowPath = NSBezierPath()
        shadowPath.lineWidth = 1
        shadowPath.move(to: NSPoint(x: 2, y: 2))
        shadowPath.line(to: NSPoint(x: 14, y: 14))
        shadowPath.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: 9))
    }()

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        super.init(frame: .zero)
        wantsLayer = true

        previewLayer.session = cameraManager.session
        previewLayer.videoGravity = .resizeAspectFill
        previewContainerLayer.addSublayer(previewLayer)
        layer?.addSublayer(previewContainerLayer)

        resizeGuideLayer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.98).cgColor
        resizeGuideLayer.fillColor = NSColor.clear.cgColor
        resizeGuideLayer.lineWidth = 2
        resizeGuideLayer.lineDashPattern = [5, 4]
        resizeGuideLayer.shadowColor = NSColor.black.withAlphaComponent(0.6).cgColor
        resizeGuideLayer.shadowOpacity = 1
        resizeGuideLayer.shadowRadius = 3
        resizeGuideLayer.shadowOffset = CGSize(width: 0, height: -1)
        resizeGuideLayer.isHidden = true
        layer?.addSublayer(resizeGuideLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let side = min(bounds.width, bounds.height)
        let circleRect = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        previewContainerLayer.frame = bounds
        previewLayer.frame = circleRect

        let circlePath = CGPath(ellipseIn: circleRect, transform: nil)

        let maskLayer = CAShapeLayer()
        maskLayer.path = circlePath
        previewContainerLayer.mask = maskLayer

        let guideInset = resizeGuideLayer.lineWidth / 2
        let guideRect = circleRect.insetBy(dx: guideInset, dy: guideInset)
        resizeGuideLayer.path = CGPath(rect: guideRect, transform: nil)
        resizeGuideLayer.frame = bounds
    }

    override func updateTrackingAreas() {
        if let existingTrackingArea = trackingArea {
            removeTrackingArea(existingTrackingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .cursorUpdate,
            .activeAlways,
            .inVisibleRect
        ]
        let newTrackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        resizeGuideLayer.isHidden = false
        updateCursor(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        resizeGuideLayer.isHidden = true
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }

        let delta = event.deltaY * 4
        let oldFrame = window.frame
        var newSize = oldFrame.size.width + delta
        newSize = max(minSize, min(maxSize, newSize))

        let center = CGPoint(x: oldFrame.midX, y: oldFrame.midY)
        let newOrigin = CGPoint(x: center.x - newSize / 2, y: center.y - newSize / 2)
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: newSize, height: newSize))
        window.setFrame(newFrame, display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 {
            guard let connection = previewLayer.connection else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored.toggle()
        }
    }

    private func updateCursor(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard OverlayWindow.isInResizeBorder(point: point, bounds: bounds) else {
            NSCursor.crosshair.set()
            return
        }

        let direction = diagonalDirection(for: point, in: bounds)
        switch direction {
        case .slash:
            Self.diagonalResizeCursorSlash.set()
        case .backslash:
            Self.diagonalResizeCursorBackslash.set()
        }
    }

    private func diagonalDirection(for point: CGPoint, in rect: CGRect) -> DiagonalCursorDirection {
        let isLeft = point.x < rect.midX
        let isTop = point.y > rect.midY

        // 右上+左下: "\"，左上+右下: "/"
        if (isLeft && !isTop) || (!isLeft && isTop) {
            return .backslash
        } else {
            return .slash
        }
    }
}
