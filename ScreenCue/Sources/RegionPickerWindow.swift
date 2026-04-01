import AppKit

final class RegionPickerWindow: NSWindow {
    var onRegionPicked: ((NSRect) -> Void)?
    var onCancelled: (() -> Void)?

    private let pickerView: RegionPickerView

    init(screen: NSScreen) {
        let screenFrame = screen.frame
        pickerView = RegionPickerView(frame: screenFrame)
        super.init(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // Keep picker above app windows but below menu bar.
        level = .floating
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = pickerView

        pickerView.onSelected = { [weak self] rect in
            self?.orderOut(nil)
            self?.onRegionPicked?(rect)
            self?.onCancelled?()
        }
        pickerView.onCancelled = { [weak self] in
            self?.orderOut(nil)
            self?.onCancelled?()
        }
    }

    func beginPicking() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}

private final class RegionPickerView: NSView {
    var onSelected: ((NSRect) -> Void)?
    var onCancelled: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard let selectionRect = normalizedSelectionRect() else { return }
        NSColor.clear.setFill()
        selectionRect.fill(using: .clear)

        NSColor.systemYellow.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 2
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        startPoint = p
        currentPoint = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = normalizedSelectionRect(), rect.width >= 20, rect.height >= 20 else {
            onCancelled?()
            return
        }

        guard let window else {
            onCancelled?()
            return
        }

        let screenRect = NSRect(
            x: window.frame.origin.x + rect.origin.x,
            y: window.frame.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        onSelected?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // esc
            onCancelled?()
            return
        }
        super.keyDown(with: event)
    }

    private func normalizedSelectionRect() -> NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }
}
