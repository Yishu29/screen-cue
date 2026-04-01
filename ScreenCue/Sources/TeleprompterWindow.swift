import AppKit

final class TeleprompterWindow: NSWindow {
    private static let defaults = UserDefaults.standard
    private static let defaultsOriginXKey = "teleprompter.window.origin.x"
    private static let defaultsOriginYKey = "teleprompter.window.origin.y"
    private static let defaultsWidthKey = "teleprompter.window.width"
    private static let defaultsHeightKey = "teleprompter.window.height"
    private static let resizeBorderWidth: CGFloat = 16
    private static let resizeCornerSize: CGFloat = 24
    private static let minWidth: CGFloat = 360
    private static let minHeight: CGFloat = 180

    private enum ResizeEdge {
        case left
        case right
        case top
        case bottom
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    private var activeResizeEdge: ResizeEdge?
    private var hoverResizeEdge: ResizeEdge?
    private var initialMouseLocationOnScreen: NSPoint = .zero
    private var initialFrame: NSRect = .zero

    init() {
        let defaultSize = NSSize(width: 520, height: 240)
        let screens = NSScreen.screens
        let fallbackVisible = NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame ?? .zero
        let candidateScreens = screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }

        let savedW = Self.defaults.double(forKey: Self.defaultsWidthKey)
        let savedH = Self.defaults.double(forKey: Self.defaultsHeightKey)
        let width = savedW > 0 ? CGFloat(savedW) : defaultSize.width
        let height = savedH > 0 ? CGFloat(savedH) : defaultSize.height

        let savedX = Self.defaults.double(forKey: Self.defaultsOriginXKey)
        let savedY = Self.defaults.double(forKey: Self.defaultsOriginYKey)
        let hasSavedOrigin =
            Self.defaults.object(forKey: Self.defaultsOriginXKey) != nil
            && Self.defaults.object(forKey: Self.defaultsOriginYKey) != nil
        let hasSavedSize =
            Self.defaults.object(forKey: Self.defaultsWidthKey) != nil
            && Self.defaults.object(forKey: Self.defaultsHeightKey) != nil
            && width > 0
            && height > 0
        let savedFrame = (hasSavedOrigin && hasSavedSize)
            ? CGRect(x: savedX, y: savedY, width: width, height: height)
            : nil
        let visible = LayoutFrameResolver.bestVisibleFrame(
            for: savedFrame,
            candidateScreens: candidateScreens,
            fallbackVisibleFrame: fallbackVisible
        )

        let origin: CGPoint
        if hasSavedOrigin, visible != .zero {
            origin = CGPoint(x: CGFloat(savedX), y: CGFloat(savedY))
            // Clamp to visible frame to avoid off-screen restoration.
            let clampedX = min(max(origin.x, visible.minX), visible.maxX - width)
            let clampedY = min(max(origin.y, visible.minY), visible.maxY - height)
            self.frameOriginClamped = CGPoint(x: clampedX, y: clampedY)
        } else {
            self.frameOriginClamped = LayoutFrameResolver.defaultTeleprompterFrame(
                in: visible,
                size: NSSize(width: width, height: height)
            ).origin
        }

        super.init(
            contentRect: NSRect(origin: self.frameOriginClamped, size: NSSize(width: width, height: height)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.ignoresMouseEvents = false
        self.isMovableByWindowBackground = true
        self.acceptsMouseMovedEvents = true

        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
    }

    private var frameOriginClamped: CGPoint

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        persistFrame()
    }

    override func mouseDown(with event: NSEvent) {
        activeResizeEdge = hoverResizeEdge
        if activeResizeEdge != nil {
            isMovableByWindowBackground = false
            initialMouseLocationOnScreen = NSEvent.mouseLocation
            initialFrame = frame
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let edge = activeResizeEdge else {
            super.mouseDragged(with: event)
            return
        }
        resizeWindow(edge: edge, currentPointInWindow: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        isMovableByWindowBackground = true
        activeResizeEdge = nil
        updateCursor(for: event.locationInWindow)
        super.mouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event.locationInWindow)
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: event.locationInWindow)
        super.cursorUpdate(with: event)
    }

    private func resizeWindow(edge: ResizeEdge, currentPointInWindow _: NSPoint) {
        let currentScreenPoint = NSEvent.mouseLocation
        let dx = currentScreenPoint.x - initialMouseLocationOnScreen.x
        let dy = currentScreenPoint.y - initialMouseLocationOnScreen.y
        var next = initialFrame

        switch edge {
        case .left:
            next.origin.x += dx
            next.size.width -= dx
        case .right:
            next.size.width += dx
        case .top:
            next.size.height += dy
        case .bottom:
            next.origin.y += dy
            next.size.height -= dy
        case .topLeft:
            next.origin.x += dx
            next.size.width -= dx
            next.size.height += dy
        case .topRight:
            next.size.width += dx
            next.size.height += dy
        case .bottomLeft:
            next.origin.x += dx
            next.size.width -= dx
            next.origin.y += dy
            next.size.height -= dy
        case .bottomRight:
            next.size.width += dx
            next.origin.y += dy
            next.size.height -= dy
        }

        if next.size.width < Self.minWidth {
            let delta = Self.minWidth - next.size.width
            next.size.width = Self.minWidth
            if edge == .left || edge == .topLeft || edge == .bottomLeft {
                next.origin.x -= delta
            }
        }
        if next.size.height < Self.minHeight {
            let delta = Self.minHeight - next.size.height
            next.size.height = Self.minHeight
            if edge == .bottom || edge == .bottomLeft || edge == .bottomRight {
                next.origin.y -= delta
            }
        }

        setFrame(next, display: true)
        persistFrame()
    }

    private func resizeEdge(at point: NSPoint) -> ResizeEdge? {
        let bounds = CGRect(origin: .zero, size: frame.size)
        guard bounds.contains(point) else { return nil }
        let b = Self.resizeBorderWidth
        let c = Self.resizeCornerSize
        let nearLeft = point.x <= b
        let nearRight = point.x >= bounds.maxX - b
        let nearBottom = point.y <= b
        let nearTop = point.y >= bounds.maxY - b
        let inLeftCornerX = point.x <= c
        let inRightCornerX = point.x >= bounds.maxX - c
        let inBottomCornerY = point.y <= c
        let inTopCornerY = point.y >= bounds.maxY - c

        if inLeftCornerX && inTopCornerY { return .topLeft }
        if inRightCornerX && inTopCornerY { return .topRight }
        if inLeftCornerX && inBottomCornerY { return .bottomLeft }
        if inRightCornerX && inBottomCornerY { return .bottomRight }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        return nil
    }

    private func updateCursor(for point: NSPoint) {
        hoverResizeEdge = resizeEdge(at: point)
        guard let edge = hoverResizeEdge else {
            NSCursor.arrow.set()
            return
        }

        switch edge {
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            NSCursor.crosshair.set()
        }
    }

    private func persistFrame() {
        Self.defaults.set(Double(frame.origin.x), forKey: Self.defaultsOriginXKey)
        Self.defaults.set(Double(frame.origin.y), forKey: Self.defaultsOriginYKey)
        Self.defaults.set(Double(frame.size.width), forKey: Self.defaultsWidthKey)
        Self.defaults.set(Double(frame.size.height), forKey: Self.defaultsHeightKey)
    }
}

