import AppKit

final class RecordingRegionWindow: NSWindow {
    private enum ResizeEdge {
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private static let minWidth: CGFloat = 240
    private static let minHeight: CGFloat = 160
    private static let borderWidth: CGFloat = 10
    private static let cornerSize: CGFloat = 18
    private static let accessoryHeight: CGFloat = 32
    private static let accessorySpacing: CGFloat = 8
    private static let accessoryHorizontalPadding: CGFloat = 12
    private static let accessoryBottomInset: CGFloat = 6

    private var activeResizeEdge: ResizeEdge?
    private var hoverResizeEdge: ResizeEdge?
    private var dragStartMouseOnScreen: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero

    private let rootView = NSView(frame: .zero)
    private let borderView = RegionBorderView(frame: .zero)
    private let accessoryView = AccessoryBackgroundView(frame: .zero)
    private let startRecordingButton = NSButton(title: "开始录屏", target: nil, action: nil)
    private let microphoneButton = NSButton(title: "麦克风：系统默认", target: nil, action: nil)
    private(set) var targetScreen: NSScreen?
    var onFrameChanged: ((NSRect) -> Void)?
    var onStartRecordingClicked: (() -> Void)?
    var onMicrophoneButtonClicked: ((NSView) -> Void)?

    init(frame: NSRect, targetScreen: NSScreen) {
        self.targetScreen = targetScreen
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // 低于摄像头/提词器（.floating），避免大选区盖住工具窗；但不能用 .normal：accessory 菜单栏应用下 .normal 窗常被压在其它应用后面，选区像「没显示」。
        level = NSWindow.Level(Int(NSWindow.Level.floating.rawValue) - 1)
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        sharingType = .none
        configureContentViews()
        configureStartRecordingButton()
        configureMicrophoneButton()
        updateAccessoryLayout()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func updateTargetScreen(_ screen: NSScreen) {
        targetScreen = screen
        updateAccessoryLayout()
    }

    func refreshTargetScreen() {
        if let bestScreen = Self.screenContainingLargestPortion(of: frame) {
            targetScreen = bestScreen
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        refreshTargetScreen()
        updateAccessoryLayout()
        onFrameChanged?(frame)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        super.setFrame(frameRect, display: flag, animate: animateFlag)
        refreshTargetScreen()
        updateAccessoryLayout()
        onFrameChanged?(frame)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        refreshTargetScreen()
        updateAccessoryLayout()
        onFrameChanged?(frame)
    }

    func setMicrophoneButtonTitle(_ title: String) {
        microphoneButton.title = title
        applyButtonTitleStyle(
            microphoneButton,
            title: microphoneButton.title,
            color: NSColor.white
        )
        updateAccessoryLayout()
    }

    func refreshAccessoryVisibility() {
        accessoryView.isHidden = false
        updateAccessoryLayout()
    }

    override func mouseDown(with event: NSEvent) {
        activeResizeEdge = resizeEdge(at: event.locationInWindow)
        if activeResizeEdge != nil {
            isMovableByWindowBackground = false
            dragStartMouseOnScreen = NSEvent.mouseLocation
            dragStartFrame = frame
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let edge = activeResizeEdge else {
            super.mouseDragged(with: event)
            return
        }
        resizeWindow(edge: edge)
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

    private func resizeWindow(edge: ResizeEdge) {
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartMouseOnScreen.x
        let dy = current.y - dragStartMouseOnScreen.y
        var next = dragStartFrame

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

        if next.width < Self.minWidth {
            let delta = Self.minWidth - next.width
            next.size.width = Self.minWidth
            if edge == .left || edge == .topLeft || edge == .bottomLeft {
                next.origin.x -= delta
            }
        }
        if next.height < Self.minHeight {
            let delta = Self.minHeight - next.height
            next.size.height = Self.minHeight
            if edge == .bottom || edge == .bottomLeft || edge == .bottomRight {
                next.origin.y -= delta
            }
        }

        if let screen = targetScreen {
            // 启动恢复与拖拽/缩放都统一使用 visibleFrame，避免退出后再次启动被系统菜单栏/Dock 重新“挤回去”。
            let bounds = screen.visibleFrame
            next.origin.x = min(max(next.origin.x, bounds.minX), bounds.maxX - next.width)
            next.origin.y = min(max(next.origin.y, bounds.minY), bounds.maxY - next.height)
        }
        setFrame(next, display: true)
    }

    private func resizeEdge(at point: NSPoint) -> ResizeEdge? {
        let bounds = CGRect(origin: .zero, size: frame.size)
        guard bounds.contains(point) else { return nil }
        let b = Self.borderWidth
        let c = Self.cornerSize
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
            NSCursor.openHand.set()
            return
        }
        switch edge {
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .topLeft, .bottomRight:
            NSCursor.closedHand.set()
        case .topRight, .bottomLeft:
            NSCursor.crosshair.set()
        }
    }

    private static func screenContainingLargestPortion(of rect: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }
    }

    private func configureContentViews() {
        rootView.frame = NSRect(origin: .zero, size: frame.size)
        rootView.autoresizingMask = [.width, .height]
        contentView = rootView

        borderView.frame = rootView.bounds
        borderView.autoresizingMask = [.width, .height]
        rootView.addSubview(borderView)

        accessoryView.frame = .zero
        accessoryView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        rootView.addSubview(accessoryView)
    }

    private func configureStartRecordingButton() {
        startRecordingButton.target = self
        startRecordingButton.action = #selector(handleStartRecordingButtonClick(_:))
        startRecordingButton.setButtonType(.momentaryPushIn)
        startRecordingButton.bezelStyle = .rounded
        startRecordingButton.font = .systemFont(ofSize: 12, weight: .semibold)
        applyButtonTitleStyle(
            startRecordingButton,
            title: startRecordingButton.title,
            color: NSColor.white
        )
    }

    private func configureMicrophoneButton() {
        microphoneButton.target = self
        microphoneButton.action = #selector(handleMicrophoneButtonClick(_:))
        microphoneButton.setButtonType(.momentaryPushIn)
        microphoneButton.bezelStyle = .rounded
        microphoneButton.font = .systemFont(ofSize: 12, weight: .medium)
        applyButtonTitleStyle(
            microphoneButton,
            title: microphoneButton.title,
            color: NSColor.white
        )
    }

    private func applyButtonTitleStyle(_ button: NSButton, title: String, color: NSColor) {
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        button.sizeToFit()
    }

    private func updateAccessoryLayout() {
        guard rootView.superview != nil || contentView === rootView else { return }
        let contentBounds = rootView.bounds
        let startButtonWidth = max(96, startRecordingButton.intrinsicContentSize.width + Self.accessoryHorizontalPadding * 2)
        let micButtonWidth = max(160, microphoneButton.intrinsicContentSize.width + Self.accessoryHorizontalPadding * 2)
        let desiredWidth = startButtonWidth + micButtonWidth + Self.accessorySpacing + Self.accessoryHorizontalPadding * 2
        let frameWidth = min(max(desiredWidth, 260), max(220, contentBounds.width - 24))
        let origin = NSPoint(
            x: (contentBounds.width - frameWidth) / 2,
            y: Self.accessoryBottomInset
        )

        accessoryView.frame = NSRect(
            x: origin.x,
            y: origin.y,
            width: frameWidth,
            height: Self.accessoryHeight
        )
        let availableButtonsWidth = frameWidth - Self.accessoryHorizontalPadding * 2 - Self.accessorySpacing
        let rightWidth = max(140, availableButtonsWidth - startButtonWidth)
        startRecordingButton.frame = NSRect(
            x: Self.accessoryHorizontalPadding,
            y: 4,
            width: startButtonWidth,
            height: Self.accessoryHeight - 8
        )
        microphoneButton.frame = NSRect(
            x: startRecordingButton.frame.maxX + Self.accessorySpacing,
            y: 4,
            width: rightWidth,
            height: Self.accessoryHeight - 8
        )
        if startRecordingButton.superview !== accessoryView {
            startRecordingButton.removeFromSuperview()
            accessoryView.addSubview(startRecordingButton)
        }
        if microphoneButton.superview !== accessoryView {
            microphoneButton.removeFromSuperview()
            accessoryView.addSubview(microphoneButton)
        }
    }

    @objc
    private func handleStartRecordingButtonClick(_ sender: NSButton) {
        onStartRecordingClicked?()
    }

    @objc
    private func handleMicrophoneButtonClick(_ sender: NSButton) {
        onMicrophoneButtonClicked?(sender)
    }
}

private extension NSRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}

private final class RegionBorderView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let outer = bounds.insetBy(dx: 1, dy: 1)
        NSColor.systemRed.withAlphaComponent(0.95).setStroke()
        let outline = NSBezierPath(rect: outer)
        outline.lineWidth = 2
        outline.stroke()

        NSColor.systemRed.withAlphaComponent(0.3).setFill()
        let fill = NSBezierPath(rect: outer)
        fill.fill()
    }
}

private final class AccessoryBackgroundView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.7).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()

        NSColor.white.withAlphaComponent(0.15).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
