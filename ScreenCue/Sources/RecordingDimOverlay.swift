import AppKit

/// 录屏时在每台显示器上显示「非录制区置灰、录制区透明」，窗口本身从 SC 捕获中排除。
final class RecordingDimOverlayController {
    private var windows: [NSWindow] = []

    /// 蒙版窗口先 `orderFront`（仍参与合成以便进入 `SCShareableContent`），但视图暂不绘制蒙版；`startCapture` 前再 `show()` 开始绘制，避免 `orderOut`/`alpha=0` 导致无法被 `exceptingWindows` 匹配。
    func prepare(recordingRectInScreenCoords recordingRect: NSRect) -> [CGWindowID] {
        hide()
        var ids: [CGWindowID] = []
        for screen in NSScreen.screens {
            let window = Self.makeWindow(for: screen)
            guard let view = window.contentView as? RecordingDimOverlayView else { continue }
            view.holeRect = Self.localHoleRect(recordingRect: recordingRect, screen: screen)
            view.defersDimDrawing = true
            window.alphaValue = 1
            window.orderFrontRegardless()
            windows.append(window)
            ids.append(CGWindowID(window.windowNumber))
        }
        return ids
    }

    func show() {
        for window in windows {
            window.alphaValue = 1
            if let view = window.contentView as? RecordingDimOverlayView {
                view.defersDimDrawing = false
            }
            window.contentView?.needsDisplay = true
            window.orderFrontRegardless()
        }
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private static func localHoleRect(recordingRect: NSRect, screen: NSScreen) -> NSRect? {
        let inter = recordingRect.intersection(screen.frame)
        guard inter.width > 0.5, inter.height > 0.5 else { return nil }
        return NSRect(
            x: inter.minX - screen.frame.minX,
            y: inter.minY - screen.frame.minY,
            width: inter.width,
            height: inter.height
        )
    }

    private static func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(Int(NSWindow.Level.floating.rawValue) + 3)
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.setFrame(screen.frame, display: false)

        let view = RecordingDimOverlayView(frame: window.contentLayoutRect)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        return window
    }
}

private final class RecordingDimOverlayView: NSView {
    private static let outerHighlightWidth: CGFloat = 3

    /// 为让 SCK 能枚举到本窗口：前台期间可先不画蒙版（透视到下层选区红框）。
    var defersDimDrawing = false {
        didSet { needsDisplay = true }
    }

    var holeRect: NSRect? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if defersDimDrawing { return }

        let dimColor = NSColor.black.withAlphaComponent(0.48)

        if let hole = holeRect, hole.width > 0.5, hole.height > 0.5 {
            let path = NSBezierPath()
            path.appendRect(bounds)
            path.appendRect(hole)
            path.windingRule = .evenOdd
            dimColor.setFill()
            path.fill()

            // 红框完全画在录制区外侧，避免任何线条压进透明洞。
            let outerHole = hole.insetBy(dx: -Self.outerHighlightWidth, dy: -Self.outerHighlightWidth)
            let ring = NSBezierPath()
            ring.appendRect(outerHole)
            ring.appendRect(hole)
            ring.windingRule = .evenOdd
            NSColor.systemRed.withAlphaComponent(0.95).setFill()
            ring.fill()
        } else {
            dimColor.setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }
}
