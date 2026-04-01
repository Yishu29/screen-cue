import AppKit

enum TeleprompterTextFormatAction {
    case increaseFontSize
    case decreaseFontSize
    case resetFontSize
    case toggleBold
    case toggleItalic
    case toggleUnderline
}

enum TeleprompterRichTextCodec {
    static func encode(_ text: NSAttributedString) -> Data? {
        try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func decode(_ data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }
}

enum TeleprompterTextFormatter {
    static let defaultFontSize: CGFloat = 32
    static let minFontSize: CGFloat = 12
    static let maxFontSize: CGFloat = 96
    static let defaultFont = NSFont.systemFont(ofSize: defaultFontSize, weight: .regular)
    static let defaultTextColor = NSColor.white
    static let defaultAttributes: [NSAttributedString.Key: Any] = [
        .font: defaultFont,
        .foregroundColor: defaultTextColor
    ]

    static func apply(
        _ action: TeleprompterTextFormatAction,
        to storage: NSTextStorage,
        selectedRange: NSRange,
        typingAttributes: inout [NSAttributedString.Key: Any]
    ) {
        guard selectedRange.length > 0 else {
            typingAttributes = applying(action, to: mergedAttributes(from: typingAttributes))
            return
        }

        storage.beginEditing()
        switch action {
        case .toggleUnderline:
            let baseline = mergedAttributes(from: storage.attributes(at: selectedRange.location, effectiveRange: nil))
            let enableUnderline = (baseline[.underlineStyle] as? Int ?? 0) == 0
            if enableUnderline {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
            } else {
                storage.removeAttribute(.underlineStyle, range: selectedRange)
            }
        case .increaseFontSize, .decreaseFontSize, .resetFontSize:
            storage.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
                let font = (value as? NSFont) ?? defaultFont
                storage.addAttribute(.font, value: resizedFont(font, for: action), range: range)
            }
        case .toggleBold:
            let baseline = mergedAttributes(from: storage.attributes(at: selectedRange.location, effectiveRange: nil))
            let enableBold = !font(from: baseline).fontDescriptor.symbolicTraits.contains(.bold)
            storage.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
                let font = (value as? NSFont) ?? defaultFont
                storage.addAttribute(.font, value: boldFont(from: font, enabled: enableBold), range: range)
            }
        case .toggleItalic:
            let baseline = mergedAttributes(from: storage.attributes(at: selectedRange.location, effectiveRange: nil))
            let enableItalic = !font(from: baseline).fontDescriptor.symbolicTraits.contains(.italic)
            storage.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
                let font = (value as? NSFont) ?? defaultFont
                storage.addAttribute(.font, value: italicFont(from: font, enabled: enableItalic), range: range)
            }
        }
        storage.endEditing()
    }

    static func applyColor(
        _ color: NSColor,
        to storage: NSTextStorage,
        selectedRange: NSRange,
        typingAttributes: inout [NSAttributedString.Key: Any]
    ) {
        if selectedRange.length > 0 {
            storage.addAttribute(.foregroundColor, value: color, range: selectedRange)
        } else {
            var updated = mergedAttributes(from: typingAttributes)
            updated[.foregroundColor] = color
            typingAttributes = updated
        }
    }

    static func applyTypingAttributes(
        _ typingAttributes: [NSAttributedString.Key: Any],
        to storage: NSTextStorage,
        insertedRange: NSRange
    ) {
        guard insertedRange.length > 0 else { return }
        storage.addAttributes(mergedAttributes(from: typingAttributes), range: insertedRange)
    }

    static func toggledBoldFont(from font: NSFont) -> NSFont {
        let enableBold = !font.fontDescriptor.symbolicTraits.contains(.bold)
        return boldFont(from: font, enabled: enableBold)
    }

    private static func applying(
        _ action: TeleprompterTextFormatAction,
        to attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var updated = mergedAttributes(from: attributes)
        let currentFont = font(from: updated)

        switch action {
        case .increaseFontSize, .decreaseFontSize, .resetFontSize:
            updated[.font] = resizedFont(currentFont, for: action)
        case .toggleBold:
            let enableBold = !currentFont.fontDescriptor.symbolicTraits.contains(.bold)
            updated[.font] = boldFont(from: currentFont, enabled: enableBold)
        case .toggleItalic:
            let enableItalic = !currentFont.fontDescriptor.symbolicTraits.contains(.italic)
            updated[.font] = italicFont(from: currentFont, enabled: enableItalic)
        case .toggleUnderline:
            let currentUnderline = updated[.underlineStyle] as? Int ?? 0
            if currentUnderline == 0 {
                updated[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                updated.removeValue(forKey: .underlineStyle)
            }
        }

        return updated
    }

    private static func mergedAttributes(from attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var merged = defaultAttributes
        for (key, value) in attributes {
            merged[key] = value
        }
        return merged
    }

    private static func font(from attributes: [NSAttributedString.Key: Any]) -> NSFont {
        (attributes[.font] as? NSFont) ?? defaultFont
    }

    private static func resizedFont(_ font: NSFont, for action: TeleprompterTextFormatAction) -> NSFont {
        let targetSize: CGFloat
        switch action {
        case .increaseFontSize:
            targetSize = min(maxFontSize, font.pointSize + 2)
        case .decreaseFontSize:
            targetSize = max(minFontSize, font.pointSize - 2)
        case .resetFontSize:
            targetSize = defaultFontSize
        case .toggleBold, .toggleItalic, .toggleUnderline:
            targetSize = font.pointSize
        }
        return NSFont(descriptor: font.fontDescriptor, size: targetSize) ?? font.withSize(targetSize)
    }

    private static func boldFont(from font: NSFont, enabled: Bool) -> NSFont {
        let manager = NSFontManager.shared
        let converted = enabled
            ? manager.convert(font, toHaveTrait: .boldFontMask)
            : manager.convert(font, toNotHaveTrait: .boldFontMask)
        return NSFont(descriptor: converted.fontDescriptor, size: font.pointSize) ?? converted
    }

    private static func italicFont(from font: NSFont, enabled: Bool) -> NSFont {
        let manager = NSFontManager.shared
        let converted = enabled
            ? manager.convert(font, toHaveTrait: .italicFontMask)
            : manager.convert(font, toNotHaveTrait: .italicFontMask)
        return NSFont(descriptor: converted.fontDescriptor, size: font.pointSize) ?? converted
    }
}

private final class TeleprompterTextView: NSTextView {
    var onAttributedContentChanged: ((NSAttributedString) -> Void)?
    private var colorPanelObserver: NSObjectProtocol?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == "v" { pasteAsPlainText(self); return true }
        if key == "a" { selectAll(self); return true }
        if key == "c" { copy(self); return true }
        if key == "x" { cut(self); return true }
        if key == "z" { undoManager?.undo(); return true }
        if key == "y" { undoManager?.redo(); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let fontSizeMenu = NSMenu()
        let fontSizeItem = NSMenuItem(title: "文字大小", action: nil, keyEquivalent: "")
        fontSizeItem.submenu = fontSizeMenu
        fontSizeMenu.addItem(NSMenuItem(title: "放大", action: #selector(increaseFontSizeFromMenu(_:)), keyEquivalent: ""))
        fontSizeMenu.addItem(NSMenuItem(title: "缩小", action: #selector(decreaseFontSizeFromMenu(_:)), keyEquivalent: ""))
        fontSizeMenu.addItem(NSMenuItem(title: "恢复默认", action: #selector(resetFontSizeFromMenu(_:)), keyEquivalent: ""))
        menu.addItem(fontSizeItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "文字颜色...", action: #selector(openColorPanelFromMenu(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "加粗", action: #selector(toggleBoldFromMenu(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "斜体", action: #selector(toggleItalicFromMenu(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "下划线", action: #selector(toggleUnderlineFromMenu(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "复制", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "剪切", action: #selector(cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "粘贴", action: #selector(pasteAsPlainText(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "全选", action: #selector(selectAll(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    @objc
    override func pasteAsPlainText(_ sender: Any?) {
        guard let pastedText = NSPasteboard.general.string(forType: .string), !pastedText.isEmpty else { return }
        insertPlainText(pastedText)
    }

    func applyDefaultStyleToWholeText() {
        let all = NSRange(location: 0, length: (string as NSString).length)
        guard all.length > 0 else { return }
        textStorage?.setAttributes(TeleprompterTextFormatter.defaultAttributes, range: all)
        typingAttributes = TeleprompterTextFormatter.defaultAttributes
    }

    private func insertPlainText(_ text: String) {
        guard let storage = textStorage else { return }
        let selected = selectedRange()
        storage.replaceCharacters(in: selected, with: text)
        let insertedRange = NSRange(location: selected.location, length: (text as NSString).length)
        TeleprompterTextFormatter.applyTypingAttributes(typingAttributes, to: storage, insertedRange: insertedRange)
        let location = selected.location + (text as NSString).length
        setSelectedRange(NSRange(location: location, length: 0))
        didChangeText()
    }

    @objc
    private func increaseFontSizeFromMenu(_ sender: Any?) {
        applyFormattingAction(.increaseFontSize)
    }

    @objc
    private func decreaseFontSizeFromMenu(_ sender: Any?) {
        applyFormattingAction(.decreaseFontSize)
    }

    @objc
    private func resetFontSizeFromMenu(_ sender: Any?) {
        applyFormattingAction(.resetFontSize)
    }

    @objc
    private func toggleBoldFromMenu(_ sender: Any?) {
        applyFormattingAction(.toggleBold)
    }

    @objc
    private func toggleItalicFromMenu(_ sender: Any?) {
        applyFormattingAction(.toggleItalic)
    }

    @objc
    private func toggleUnderlineFromMenu(_ sender: Any?) {
        applyFormattingAction(.toggleUnderline)
    }

    @objc
    private func openColorPanelFromMenu(_ sender: Any?) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = currentTextColor()
        if colorPanelObserver == nil {
            colorPanelObserver = NotificationCenter.default.addObserver(
                forName: NSColorPanel.colorDidChangeNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                self?.applySelectedColorFromPanel()
            }
        }
        panel.orderFront(nil)
    }

    private func applyFormattingAction(_ action: TeleprompterTextFormatAction) {
        guard let storage = textStorage else { return }
        var updatedTypingAttributes = typingAttributes
        let selection = selectedRange()
        TeleprompterTextFormatter.apply(
            action,
            to: storage,
            selectedRange: selection,
            typingAttributes: &updatedTypingAttributes
        )
        typingAttributes = updatedTypingAttributes
        if selection.length > 0 {
            onAttributedContentChanged?(storage)
        }
    }

    private func applySelectedColorFromPanel() {
        guard let storage = textStorage else { return }
        var updatedTypingAttributes = typingAttributes
        let selection = selectedRange()
        TeleprompterTextFormatter.applyColor(
            NSColorPanel.shared.color,
            to: storage,
            selectedRange: selection,
            typingAttributes: &updatedTypingAttributes
        )
        typingAttributes = updatedTypingAttributes
        if selection.length > 0 {
            onAttributedContentChanged?(storage)
        }
    }

    private func currentTextColor() -> NSColor {
        let selection = selectedRange()
        if selection.length > 0,
           let color = textStorage?.attribute(.foregroundColor, at: selection.location, effectiveRange: nil) as? NSColor {
            return color
        }
        return (typingAttributes[.foregroundColor] as? NSColor) ?? TeleprompterTextFormatter.defaultTextColor
    }

    deinit {
        if let colorPanelObserver {
            NotificationCenter.default.removeObserver(colorPanelObserver)
        }
    }
}

final class TeleprompterView: NSView, NSTextViewDelegate {
    var onTextChanged: ((String) -> Void)?
    var onAttributedTextChanged: ((NSAttributedString) -> Void)?
    var onSpeedChanged: ((CGFloat) -> Void)?
    var onOpacityChanged: ((CGFloat) -> Void)?

    private let controlsContainer = NSView()
    private let playButton = NSButton(title: "▶", target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "速度")
    private let speedSlider = NSSlider(value: 60, minValue: 10, maxValue: 220, target: nil, action: nil)
    private let opacityLabel = NSTextField(labelWithString: "透明度")
    private let opacitySlider = NSSlider(value: 0.5, minValue: 0.1, maxValue: 1.0, target: nil, action: nil)

    private let scrollView = NSScrollView()
    private let textView = TeleprompterTextView()

    private var scrollTimer: Timer?
    private var lastTick: CFAbsoluteTime = 0
    private var scrollOffsetY: CGFloat = 0

    var scrollSpeedPointsPerSecond: CGFloat = 60
    private(set) var isScrolling: Bool = false
    private(set) var backgroundOpacity: CGFloat = 0.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        updateBackgroundColor()

        controlsContainer.wantsLayer = true
        controlsContainer.layer?.cornerRadius = 12
        controlsContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        addSubview(controlsContainer)

        playButton.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        playButton.bezelStyle = .circular
        playButton.target = self
        playButton.action = #selector(toggleScrolling)
        controlsContainer.addSubview(playButton)

        speedLabel.textColor = NSColor.labelColor
        speedLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        controlsContainer.addSubview(speedLabel)

        speedSlider.target = self
        speedSlider.action = #selector(speedSliderChanged(_:))
        controlsContainer.addSubview(speedSlider)

        opacityLabel.textColor = NSColor.labelColor
        opacityLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        controlsContainer.addSubview(opacityLabel)

        opacitySlider.target = self
        opacitySlider.action = #selector(opacitySliderChanged(_:))
        controlsContainer.addSubview(opacitySlider)

        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = false

        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = self
        textView.onAttributedContentChanged = { [weak self] text in
            self?.onAttributedTextChanged?(text)
            self?.updateContentHeightIfPossible()
        }
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = NSColor.white
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textColor = NSColor.white

        if let tc = textView.textContainer {
            tc.widthTracksTextView = true
            tc.heightTracksTextView = false
            tc.lineFragmentPadding = 4
        }

        textView.font = TeleprompterTextFormatter.defaultFont
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = TeleprompterTextFormatter.defaultAttributes

        scrollView.documentView = textView
        addSubview(scrollView)
        updatePlayButtonTitle()
    }

    override func layout() {
        super.layout()
        let margin: CGFloat = 14
        let controlsHeight: CGFloat = 84

        controlsContainer.frame = NSRect(
            x: margin,
            y: bounds.height - margin - controlsHeight,
            width: max(100, bounds.width - margin * 2),
            height: controlsHeight
        )

        playButton.frame = NSRect(x: 12, y: 21, width: 42, height: 42)

        let sliderX: CGFloat = 70
        let sliderWidth = max(120, controlsContainer.bounds.width - sliderX - 14)
        speedLabel.frame = NSRect(x: sliderX, y: 52, width: 50, height: 16)
        speedSlider.frame = NSRect(x: sliderX + 54, y: 48, width: sliderWidth - 54, height: 20)
        opacityLabel.frame = NSRect(x: sliderX, y: 24, width: 50, height: 16)
        opacitySlider.frame = NSRect(x: sliderX + 54, y: 20, width: sliderWidth - 54, height: 20)

        let contentTopGap: CGFloat = 10
        let contentY: CGFloat = margin
        let contentHeight = max(80, controlsContainer.frame.minY - contentTopGap - contentY)
        scrollView.frame = NSRect(x: margin, y: contentY, width: bounds.width - margin * 2, height: contentHeight)
        scrollView.contentView.frame = scrollView.bounds

        // 布局变化后更新可滚动范围。
        updateContentHeightIfPossible()
        scrollTo(offsetY: min(scrollOffsetY, maxScrollOffsetY()))
    }

    func setText(_ text: String) {
        // 避免程序化写入触发 textDidChange 时序问题（例如在 onTextChanged 尚未接线时写入默认值）。
        textView.delegate = nil
        textView.string = text
        textView.applyDefaultStyleToWholeText()
        scrollOffsetY = 0
        updateContentHeightIfPossible()
        scrollTo(offsetY: 0)
        textView.delegate = self
    }

    func setAttributedText(_ text: NSAttributedString) {
        textView.delegate = nil
        textView.textStorage?.setAttributedString(text)
        textView.typingAttributes = text.length > 0
            ? text.attributes(at: text.length - 1, effectiveRange: nil)
            : TeleprompterTextFormatter.defaultAttributes
        scrollOffsetY = 0
        updateContentHeightIfPossible()
        scrollTo(offsetY: 0)
        textView.delegate = self
    }

    func setScrollSpeed(_ speed: CGFloat) {
        scrollSpeedPointsPerSecond = max(0, speed)
        speedSlider.floatValue = Float(scrollSpeedPointsPerSecond)
    }

    func setBackgroundOpacity(_ opacity: CGFloat) {
        backgroundOpacity = max(0.1, min(1.0, opacity))
        opacitySlider.floatValue = Float(backgroundOpacity)
        updateBackgroundColor()
    }

    func focusTextEditor() {
        window?.makeFirstResponder(textView)
    }

    func startScrolling(loop: Bool = true) {
        guard !isScrolling else { return }
        isScrolling = true
        textView.isEditable = false
        updatePlayButtonTitle()
        scrollOffsetY = scrollView.contentView.bounds.origin.y

        lastTick = CFAbsoluteTimeGetCurrent()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick(loop: loop)
        }

        RunLoop.main.add(scrollTimer!, forMode: .common)
    }

    func stopScrolling() {
        isScrolling = false
        scrollTimer?.invalidate()
        scrollTimer = nil
        textView.isEditable = true
        updatePlayButtonTitle()
    }

    private func tick(loop: Bool) {
        updateContentHeightIfPossible()
        let now = CFAbsoluteTimeGetCurrent()
        let dt = max(0, now - lastTick)
        lastTick = now

        let delta = scrollSpeedPointsPerSecond * CGFloat(dt)
        scrollOffsetY += delta

        let maxOffset = maxScrollOffsetY()
        if scrollOffsetY >= maxOffset {
            if loop {
                scrollOffsetY = 0
            } else {
                scrollOffsetY = maxOffset
                stopScrolling()
                return
            }
        }

        scrollTo(offsetY: scrollOffsetY)
    }

    private func scrollTo(offsetY: CGFloat) {
        let target = NSPoint(x: 0, y: offsetY)
        scrollView.contentView.scroll(to: target)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollOffsetY = scrollView.contentView.bounds.origin.y
    }

    private func updateContentHeightIfPossible() {
        // 强制 layoutManager 计算 usedRect，从而得到文本总高度。
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }

        // 使用当前视图宽度，允许文本在高度方向上无限扩展。
        container.containerSize = CGSize(width: max(1, textView.bounds.width), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let contentHeight = max(1, ceil(used.height))

        let targetHeight = max(scrollView.contentSize.height, contentHeight + textView.textContainerInset.height * 2)
        if abs(textView.frame.height - targetHeight) > 0.5 {
            textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: targetHeight)
        }
    }

    private func maxScrollOffsetY() -> CGFloat {
        let content = textView.frame.height
        let visible = max(1, scrollView.contentSize.height)
        return max(0, content - visible)
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = NSColor.gray.withAlphaComponent(backgroundOpacity).cgColor
    }

    private func updatePlayButtonTitle() {
        playButton.title = isScrolling ? "⏸" : "▶"
    }

    @objc
    private func toggleScrolling() {
        if isScrolling {
            stopScrolling()
        } else {
            startScrolling(loop: true)
        }
    }

    @objc
    private func speedSliderChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.floatValue)
        setScrollSpeed(value)
        onSpeedChanged?(value)
    }

    @objc
    private func opacitySliderChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.floatValue)
        setBackgroundOpacity(value)
        onOpacityChanged?(value)
    }

    func textDidChange(_ notification: Notification) {
        onTextChanged?(textView.string)
        if let storage = textView.textStorage {
            onAttributedTextChanged?(storage)
        }
        updateContentHeightIfPossible()
    }
}

