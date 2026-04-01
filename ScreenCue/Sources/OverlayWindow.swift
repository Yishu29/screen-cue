import AppKit

final class OverlayWindow: NSWindow {
    private enum DragMode {
        case move
        case resize
    }

    private static let resizeBorderWidth: CGFloat = 12
    private let minWindowSize: CGFloat = 120
    private let maxWindowSize: CGFloat = 480

    private var initialMouseLocationOnScreen: NSPoint = .zero
    private var initialFrame: NSRect = .zero
    private var dragMode: DragMode = .move
    private var initialDistanceToCenter: CGFloat = 0
    var onFrameChanged: ((NSRect) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        onFrameChanged?(frame)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        super.setFrame(frameRect, display: flag, animate: animateFlag)
        onFrameChanged?(frame)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        onFrameChanged?(frame)
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseLocationOnScreen = NSEvent.mouseLocation
        initialFrame = frame
        dragMode = isInResizeBorder(event.locationInWindow) ? .resize : .move
        if dragMode == .resize {
            let center = NSPoint(x: initialFrame.midX, y: initialFrame.midY)
            initialDistanceToCenter = hypot(
                initialMouseLocationOnScreen.x - center.x,
                initialMouseLocationOnScreen.y - center.y
            )
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let currentLocation = NSEvent.mouseLocation
        switch dragMode {
        case .move:
            moveWindow(currentLocation)
        case .resize:
            resizeWindow(currentLocation)
        }
    }

    private func isInResizeBorder(_ point: NSPoint) -> Bool {
        OverlayWindow.isInResizeBorder(point: point, bounds: CGRect(origin: .zero, size: frame.size))
    }

    static func isInResizeBorder(point: CGPoint, bounds: CGRect) -> Bool {
        guard bounds.contains(point) else { return false }
        let innerRect = bounds.insetBy(dx: resizeBorderWidth, dy: resizeBorderWidth)
        return !innerRect.contains(point)
    }

    private func moveWindow(_ currentLocationOnScreen: NSPoint) {
        guard let screen = screen else { return }
        var nextFrame = initialFrame
        nextFrame.origin.x += currentLocationOnScreen.x - initialMouseLocationOnScreen.x
        nextFrame.origin.y += currentLocationOnScreen.y - initialMouseLocationOnScreen.y

        let visible = screen.visibleFrame
        nextFrame.origin.x = min(max(nextFrame.origin.x, visible.minX - nextFrame.width + 40), visible.maxX - 40)
        nextFrame.origin.y = min(max(nextFrame.origin.y, visible.minY), visible.maxY - 40)

        setFrame(nextFrame, display: true)
    }

    private func resizeWindow(_ currentLocationOnScreen: NSPoint) {
        let center = NSPoint(x: initialFrame.midX, y: initialFrame.midY)
        let currentDistance = hypot(
            currentLocationOnScreen.x - center.x,
            currentLocationOnScreen.y - center.y
        )
        let radialDelta = (currentDistance - initialDistanceToCenter) * 2
        let targetSize = max(minWindowSize, min(maxWindowSize, initialFrame.width + radialDelta))

        // Keep center fixed for smoother resize interaction.
        let nextOrigin = NSPoint(x: center.x - targetSize / 2, y: center.y - targetSize / 2)
        let nextFrame = NSRect(origin: nextOrigin, size: NSSize(width: targetSize, height: targetSize))
        setFrame(nextFrame, display: true)
    }
}
