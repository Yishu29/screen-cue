import AppKit
import AVFoundation
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: OverlayWindow?
    private var teleprompterWindow: TeleprompterWindow?
    private var teleprompterView: TeleprompterView?
    private var recordingRegionWindow: RecordingRegionWindow?
    private var recordingDimOverlay: RecordingDimOverlayController?
    private var regionPickerWindow: RegionPickerWindow?
    private let cameraManager = CameraManager()
    private let screenRecorder = ScreenRecorder()
    private var microphoneSelection: MicrophoneSelection = .systemDefault
    private var lastScreenCaptureAccessRequestGranted = false
    private var statusItem: NSStatusItem?
    private var teleprompterVisibilityMenuItem: NSMenuItem?
    private var recordingMenuItem: NSMenuItem?

    private enum TeleprompterDefaults {
        static let textKey = "teleprompter.text"
        static let richTextKey = "teleprompter.rich_text.rtf"
        static let speedKey = "teleprompter.scroll.speed.points_per_second"
        static let opacityKey = "teleprompter.window.opacity"
    }

    private enum RecordingRegionDefaults {
        static let originXKey = "recording.region.origin.x"
        static let originYKey = "recording.region.origin.y"
        static let widthKey = "recording.region.width"
        static let heightKey = "recording.region.height"
    }

    private enum CameraOverlayDefaults {
        static let originXKey = "camera.overlay.origin.x"
        static let originYKey = "camera.overlay.origin.y"
        static let sizeKey = "camera.overlay.size"
    }

    private enum MicrophoneDefaults {
        static let kindKey = "recording.microphone.kind"
        static let deviceIDKey = "recording.microphone.device_id"
        static let deviceNameKey = "recording.microphone.device_name"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusMenu()
        createTeleprompterWindowIfNeeded()
        showTeleprompterWindowByDefault()
        loadPersistedMicrophoneSelection()
        createDefaultRecordingRegionIfNeeded()
        screenRecorder.onRecordingStateChanged = { [weak self] isRecording in
            DispatchQueue.main.async {
                self?.recordingMenuItem?.title = isRecording ? "停止录屏" : "开始录屏"
                self?.recordingRegionWindow?.orderOut(nil)
                if !isRecording {
                    self?.recordingDimOverlay?.hide()
                    self?.recordingDimOverlay = nil
                    self?.recordingRegionWindow?.orderFrontRegardless()
                    self?.raiseToolWindowsAboveRecordingRegion()
                }
            }
        }
        screenRecorder.onRecordingFinished = { [weak self] url, error in
            DispatchQueue.main.async {
                self?.handleRecordingFinished(outputURL: url, error: error)
            }
        }
        requestCameraPermissionAndLaunch()

        // 首帧后补建选区（极少数启动瞬间尚无 NSScreen）并统一叠放，避免 accessory 应用下窗口顺序异常。
        DispatchQueue.main.async { [weak self] in
            self?.createDefaultRecordingRegionIfNeeded()
            self?.recordingRegionWindow?.orderFrontRegardless()
            self?.raiseToolWindowsAboveRecordingRegion()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cameraManager.stop()
        teleprompterView?.stopScrolling()
    }

    private func requestCameraPermissionAndLaunch() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            createOverlayWindow()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.createOverlayWindow()
                    } else {
                        self?.showCameraPermissionAlert()
                    }
                }
            }
        default:
            showCameraPermissionAlert()
        }
    }

    private func createOverlayWindow() {
        let defaultRegion = recordingRegionWindow?.frame ?? defaultRecordingRegionFrame(on: NSScreen.main)
        let screens = NSScreen.screens
        let geometries = screenGeometries(from: screens)
        let defaultFrame = LayoutFrameResolver.defaultCameraFrame(
            recordingRegion: defaultRegion,
            size: 180,
            margin: 24
        )
        let fallbackVisible = screenForFrame(defaultRegion)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? defaultFrame
        let savedCameraFrame = persistedFrame(
            originXKey: CameraOverlayDefaults.originXKey,
            originYKey: CameraOverlayDefaults.originYKey,
            widthKey: CameraOverlayDefaults.sizeKey,
            heightKey: CameraOverlayDefaults.sizeKey
        )
        let targetVisible = LayoutFrameResolver.bestVisibleFrame(
            for: savedCameraFrame,
            candidateScreens: geometries,
            fallbackVisibleFrame: fallbackVisible
        )
        let frame = resolvedFrame(
            originXKey: CameraOverlayDefaults.originXKey,
            originYKey: CameraOverlayDefaults.originYKey,
            widthKey: CameraOverlayDefaults.sizeKey,
            heightKey: CameraOverlayDefaults.sizeKey,
            fallbackFrame: defaultFrame,
            visibleFrame: targetVisible
        )

        let window = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.onFrameChanged = { [weak self] frame in
            self?.persistFrame(
                frame,
                originXKey: CameraOverlayDefaults.originXKey,
                originYKey: CameraOverlayDefaults.originYKey,
                widthKey: CameraOverlayDefaults.sizeKey,
                heightKey: CameraOverlayDefaults.sizeKey
            )
        }

        window.contentView = OverlayCameraView(cameraManager: cameraManager)
        window.makeKeyAndOrderFront(nil)

        cameraManager.start()
        overlayWindow = window
        raiseToolWindowsAboveRecordingRegion()
    }

    /// 保证摄像头、提词器叠在选区红框之上（选区为 floating−1，工具窗为 `.floating`；再统一 front 顺序避免同层时序问题）。
    private func raiseToolWindowsAboveRecordingRegion() {
        if let teleprompterWindow, teleprompterWindow.isVisible {
            teleprompterWindow.orderFrontRegardless()
        }
        overlayWindow?.orderFrontRegardless()
    }

    private func setupStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "video.circle.fill",
                accessibilityDescription: AppBrand.displayName
            )
            button.imagePosition = .imageOnly
            button.toolTip = AppBrand.displayName
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示窗口", action: #selector(showOverlayWindow), keyEquivalent: "s"))
        let visibilityItem = NSMenuItem(title: "显示提词器", action: #selector(toggleTeleprompterWindowVisibility), keyEquivalent: "t")
        teleprompterVisibilityMenuItem = visibilityItem
        menu.addItem(visibilityItem)
        menu.addItem(NSMenuItem(title: "提词器：开始/暂停", action: #selector(toggleTeleprompterScrolling), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "选择录屏区域", action: #selector(selectRecordingRegion), keyEquivalent: "g"))
        let recordingItem = NSMenuItem(title: "开始录屏", action: #selector(toggleScreenRecording), keyEquivalent: "e")
        recordingMenuItem = recordingItem
        menu.addItem(recordingItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
    }

    @objc
    private func showOverlayWindow() {
        overlayWindow?.makeKeyAndOrderFront(nil)
        raiseToolWindowsAboveRecordingRegion()
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func createTeleprompterWindowIfNeeded() {
        if teleprompterWindow != nil, teleprompterView != nil { return }

        let window = TeleprompterWindow()
        let view = TeleprompterView(frame: .zero)

        let defaults = UserDefaults.standard
        let defaultPrompter = "在这里可以输入提词器内容。"
        let savedRichText = defaults.data(forKey: TeleprompterDefaults.richTextKey).flatMap(TeleprompterRichTextCodec.decode)
        let savedRichTextTrimmed = savedRichText?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let savedText = defaults.string(forKey: TeleprompterDefaults.textKey) ?? ""
        let trimmed = savedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSavedRichText = !savedRichTextTrimmed.isEmpty
        // 兼容旧版本仅保存纯文本的偏好。
        let hasSavedText = defaults.object(forKey: TeleprompterDefaults.textKey) != nil && !trimmed.isEmpty

        let speed = defaults.double(forKey: TeleprompterDefaults.speedKey)
        let scrollSpeed = speed > 0 ? CGFloat(speed) : 60

        let opacity = defaults.double(forKey: TeleprompterDefaults.opacityKey)
        let backgroundOpacity = opacity > 0 ? CGFloat(opacity) : 0.5

        if let savedRichText, hasSavedRichText {
            view.setAttributedText(savedRichText)
        } else {
            let text = hasSavedText ? savedText : defaultPrompter
            view.setText(text)
        }
        view.setScrollSpeed(scrollSpeed)
        view.setBackgroundOpacity(backgroundOpacity)

        view.onTextChanged = { text in
            UserDefaults.standard.set(text, forKey: TeleprompterDefaults.textKey)
        }
        view.onAttributedTextChanged = { attributedText in
            let defaults = UserDefaults.standard
            if let richTextData = TeleprompterRichTextCodec.encode(attributedText) {
                defaults.set(richTextData, forKey: TeleprompterDefaults.richTextKey)
            } else {
                defaults.removeObject(forKey: TeleprompterDefaults.richTextKey)
            }
        }
        view.onSpeedChanged = { speed in
            UserDefaults.standard.set(Double(speed), forKey: TeleprompterDefaults.speedKey)
        }
        view.onOpacityChanged = { opacity in
            UserDefaults.standard.set(Double(opacity), forKey: TeleprompterDefaults.opacityKey)
        }
        window.contentView = view
        window.sharingType = .none

        // 启动时会默认展示提词器，这里先保持隐藏，交由启动流程统一显示。
        window.orderOut(nil)
        updateTeleprompterVisibilityMenuTitle()

        teleprompterWindow = window
        teleprompterView = view
    }

    @objc
    private func toggleTeleprompterWindowVisibility() {
        createTeleprompterWindowIfNeeded()
        guard let teleprompterWindow else { return }

        if teleprompterWindow.isVisible {
            teleprompterWindow.orderOut(nil)
        } else {
            teleprompterWindow.makeKeyAndOrderFront(nil)
            teleprompterWindow.orderFrontRegardless()
            teleprompterView?.focusTextEditor()
        }

        updateTeleprompterVisibilityMenuTitle()
    }

    @objc
    private func toggleTeleprompterScrolling() {
        createTeleprompterWindowIfNeeded()
        guard let view = teleprompterView else { return }

        if view.isScrolling {
            view.stopScrolling()
        } else {
            view.startScrolling(loop: true)
        }
    }

    private func showCameraPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要相机权限"
        alert.informativeText = "请在 系统设置 -> 隐私与安全性 -> 相机 中允许 \(AppBrand.displayName) 访问相机。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func updateTeleprompterVisibilityMenuTitle() {
        let isVisible = teleprompterWindow?.isVisible ?? false
        teleprompterVisibilityMenuItem?.title = isVisible ? "隐藏提词器" : "显示提词器"
    }

    private func showTeleprompterWindowByDefault() {
        guard let window = teleprompterWindow else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        teleprompterView?.focusTextEditor()
        updateTeleprompterVisibilityMenuTitle()
    }

    private func createDefaultRecordingRegionIfNeeded() {
        guard recordingRegionWindow == nil else { return }
        let fallbackScreen = screenForCurrentMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let screens = NSScreen.screens
        let geometries = screenGeometries(from: screens)
        let targetScreen = persistedRecordingRegionFrame()
            .flatMap { persistedFrame in
                guard let index = LayoutFrameResolver.bestMatchingScreenIndex(
                    for: persistedFrame,
                    candidateScreens: geometries
                ) else {
                    return nil
                }
                return screens[index]
            } ?? fallbackScreen
        guard let targetScreen else { return }
        let frame = resolvedFrame(
            originXKey: RecordingRegionDefaults.originXKey,
            originYKey: RecordingRegionDefaults.originYKey,
            widthKey: RecordingRegionDefaults.widthKey,
            heightKey: RecordingRegionDefaults.heightKey,
            fallbackFrame: defaultRecordingRegionFrame(on: targetScreen),
            visibleFrame: targetScreen.visibleFrame
        )
        let regionWindow = RecordingRegionWindow(frame: frame, targetScreen: targetScreen)
        configureRecordingRegionWindow(regionWindow)
        recordingRegionWindow = regionWindow
        regionWindow.orderFrontRegardless()
        raiseToolWindowsAboveRecordingRegion()
    }

    @objc
    private func selectRecordingRegion() {
        guard !screenRecorder.isRecording else { return }
        let preferredScreen = recordingRegionWindow?.targetScreen
            ?? screenForCurrentMouse()
            ?? NSScreen.main
        guard let targetScreen = preferredScreen else { return }
        let picker = RegionPickerWindow(screen: targetScreen)
        picker.onRegionPicked = { [weak self] pickedFrame in
            self?.applyRecordingRegion(frame: pickedFrame, on: targetScreen)
        }
        picker.onCancelled = { [weak self] in
            self?.regionPickerWindow = nil
        }
        regionPickerWindow = picker
        picker.beginPicking()
    }

    @objc
    private func toggleScreenRecording() {
        if screenRecorder.isRecording {
            screenRecorder.stopRecording()
            return
        }
        requestScreenCapturePermissionThenStartRecording()
    }

    private func requestScreenCapturePermissionThenStartRecording() {
        if CGPreflightScreenCaptureAccess() {
            lastScreenCaptureAccessRequestGranted = true
            requestMicrophonePermissionThenStartRecording()
            return
        }

        // Trigger system permission prompt when needed, then attempt recording anyway.
        // On some macOS versions, preflight may lag behind real permission state.
        lastScreenCaptureAccessRequestGranted = CGRequestScreenCaptureAccess()
        requestMicrophonePermissionThenStartRecording()
    }

    private func requestMicrophonePermissionThenStartRecording() {
        let selection = resolvedMicrophoneSelection()
        switch RecordingLaunchPolicy.microphoneStartAction(
            selection: selection,
            authorizationStatus: microphonePermissionStatus()
        ) {
        case .startRecordingImmediately:
            Task { await startScreenRecordingNow() }
        case .requestPermission:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        Task { await self?.startScreenRecordingNow() }
                    } else {
                        self?.showAlert(
                            RecordingLaunchPolicy.microphonePermissionDeniedAlert(),
                            style: .warning
                        )
                    }
                }
            }
        case .showPermissionDeniedAlert:
            showAlert(RecordingLaunchPolicy.microphonePermissionDeniedAlert(), style: .warning)
        }
    }

    private func excludedRecordingWindowIDs(dimExtra: [CGWindowID] = []) -> [CGWindowID] {
        var ids = dimExtra
        // 选区红框窗口：orderOut 后仍可能被 SCK 采进首帧，必须从捕获里排除。
        if let recordingRegionWindow {
            ids.append(CGWindowID(recordingRegionWindow.windowNumber))
        }
        if let teleprompterWindow, teleprompterWindow.isVisible {
            ids.append(CGWindowID(teleprompterWindow.windowNumber))
        }
        return ids
    }

    @MainActor
    private func startScreenRecordingNow() async {
        if recordingRegionWindow == nil {
            createDefaultRecordingRegionIfNeeded()
        }
        guard let regionWindow = recordingRegionWindow else { return }
        regionWindow.refreshTargetScreen()
        guard let targetScreen = regionWindow.targetScreen else { return }
        let microphoneSelection = resolvedMicrophoneSelection()

        let recordingRect = regionWindow.frame

        let dim = RecordingDimOverlayController()
        let dimWindowIDs = dim.prepare(recordingRectInScreenCoords: recordingRect)
        let excludedWindowIDs = excludedRecordingWindowIDs(dimExtra: dimWindowIDs)

        let outputURL = makeRecordingOutputURL()
        do {
            try await screenRecorder.startRecording(
                screen: targetScreen,
                regionOnScreen: recordingRect,
                excludedWindowIDs: excludedWindowIDs,
                microphoneSelection: microphoneSelection,
                outputURL: outputURL,
                beforeCaptureStarts: {
                    regionWindow.orderOut(nil)
                    dim.show()
                }
            )
            recordingDimOverlay = dim
        } catch {
            dim.hide()
            regionWindow.orderFrontRegardless()
            raiseToolWindowsAboveRecordingRegion()
            if !CGPreflightScreenCaptureAccess() {
                showAlert(
                    RecordingLaunchPolicy.screenCaptureFailureAlert(
                        hasPreflightAccess: lastScreenCaptureAccessRequestGranted
                    ),
                    style: .informational
                )
                return
            }
            showRecordingErrorAlert(error)
        }
    }

    private func screenForCurrentMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
    }

    private func applyRecordingRegion(frame: NSRect, on screen: NSScreen) {
        if let window = recordingRegionWindow {
            window.updateTargetScreen(screen)
            window.setFrame(frame, display: true)
            configureRecordingRegionWindow(window)
            window.orderFrontRegardless()
        } else {
            let window = RecordingRegionWindow(frame: frame, targetScreen: screen)
            configureRecordingRegionWindow(window)
            recordingRegionWindow = window
            window.orderFrontRegardless()
        }
        raiseToolWindowsAboveRecordingRegion()
        regionPickerWindow = nil
    }

    private func configureRecordingRegionWindow(_ window: RecordingRegionWindow) {
        window.onFrameChanged = { [weak self] frame in
            self?.persistFrame(
                frame,
                originXKey: RecordingRegionDefaults.originXKey,
                originYKey: RecordingRegionDefaults.originYKey,
                widthKey: RecordingRegionDefaults.widthKey,
                heightKey: RecordingRegionDefaults.heightKey
            )
        }
        window.onStartRecordingClicked = { [weak self] in
            self?.toggleScreenRecording()
        }
        window.onMicrophoneButtonClicked = { [weak self] anchorView in
            self?.showMicrophoneMenu(from: anchorView)
        }
        updateRecordingRegionMicrophoneUI()
    }

    private func defaultRecordingRegionFrame(on screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        return LayoutFrameResolver.defaultRecordingRegionFrame(in: visible)
    }

    private func screenGeometries(from screens: [NSScreen]) -> [ScreenGeometry] {
        screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    private func persistedRecordingRegionFrame() -> NSRect? {
        persistedFrame(
            originXKey: RecordingRegionDefaults.originXKey,
            originYKey: RecordingRegionDefaults.originYKey,
            widthKey: RecordingRegionDefaults.widthKey,
            heightKey: RecordingRegionDefaults.heightKey
        )
    }

    private func resolvedFrame(
        originXKey: String,
        originYKey: String,
        widthKey: String,
        heightKey: String,
        fallbackFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        let defaults = UserDefaults.standard
        let savedWidth = defaults.double(forKey: widthKey)
        let savedHeight = defaults.double(forKey: heightKey)
        let savedOriginX = defaults.double(forKey: originXKey)
        let savedOriginY = defaults.double(forKey: originYKey)
        // double(forKey:) 对缺失键也返回 0，会与「从未持久化」混淆；必须检查键是否存在才信任存档。
        let hasPersistedGeometry =
            defaults.object(forKey: widthKey) != nil
            && defaults.object(forKey: heightKey) != nil
            && defaults.object(forKey: originXKey) != nil
            && defaults.object(forKey: originYKey) != nil
            && savedWidth > 0
            && savedHeight > 0
        let baseFrame: NSRect
        if hasPersistedGeometry {
            baseFrame = NSRect(x: savedOriginX, y: savedOriginY, width: savedWidth, height: savedHeight)
        } else {
            baseFrame = fallbackFrame
        }
        return LayoutFrameResolver.clamped(frame: baseFrame, inside: visibleFrame)
    }

    private func persistFrame(
        _ frame: NSRect,
        originXKey: String,
        originYKey: String,
        widthKey: String,
        heightKey: String
    ) {
        let defaults = UserDefaults.standard
        defaults.set(Double(frame.origin.x), forKey: originXKey)
        defaults.set(Double(frame.origin.y), forKey: originYKey)
        defaults.set(Double(frame.width), forKey: widthKey)
        defaults.set(Double(frame.height), forKey: heightKey)
    }

    private func persistedFrame(
        originXKey: String,
        originYKey: String,
        widthKey: String,
        heightKey: String
    ) -> NSRect? {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: widthKey)
        let height = defaults.double(forKey: heightKey)
        let originX = defaults.double(forKey: originXKey)
        let originY = defaults.double(forKey: originYKey)
        let hasPersistedGeometry =
            defaults.object(forKey: widthKey) != nil
            && defaults.object(forKey: heightKey) != nil
            && defaults.object(forKey: originXKey) != nil
            && defaults.object(forKey: originYKey) != nil
            && width > 0
            && height > 0
        guard hasPersistedGeometry else { return nil }
        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func screenForFrame(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, frame) < intersectionArea(rhs.frame, frame)
        }
    }

    private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return max(0, intersection.width) * max(0, intersection.height)
    }

    private func availableAudioInputDevices() -> [AudioInputDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
            .map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persistedMicrophoneSelectionFromDefaults() -> PersistedMicrophoneSelection? {
        let defaults = UserDefaults.standard
        let kind = defaults.string(forKey: MicrophoneDefaults.kindKey)
        let deviceID = defaults.string(forKey: MicrophoneDefaults.deviceIDKey)
        let deviceName = defaults.string(forKey: MicrophoneDefaults.deviceNameKey)
        guard kind != nil || deviceID != nil || deviceName != nil else { return nil }
        return PersistedMicrophoneSelection(kindRawValue: kind ?? "systemDefault", deviceID: deviceID, deviceName: deviceName)
    }

    private func loadPersistedMicrophoneSelection() {
        microphoneSelection = MicrophoneSelection.resolvePersistedSelection(
            persistedMicrophoneSelectionFromDefaults(),
            availableDevices: availableAudioInputDevices()
        )
        persistMicrophoneSelection(microphoneSelection)
    }

    private func persistMicrophoneSelection(_ selection: MicrophoneSelection) {
        microphoneSelection = selection
        let persisted = selection.persisted
        let defaults = UserDefaults.standard
        defaults.set(persisted.kindRawValue, forKey: MicrophoneDefaults.kindKey)
        if let deviceID = persisted.deviceID {
            defaults.set(deviceID, forKey: MicrophoneDefaults.deviceIDKey)
        } else {
            defaults.removeObject(forKey: MicrophoneDefaults.deviceIDKey)
        }
        if let deviceName = persisted.deviceName {
            defaults.set(deviceName, forKey: MicrophoneDefaults.deviceNameKey)
        } else {
            defaults.removeObject(forKey: MicrophoneDefaults.deviceNameKey)
        }
        updateRecordingRegionMicrophoneUI()
    }

    private func resolvedMicrophoneSelection() -> MicrophoneSelection {
        let resolved = MicrophoneSelection.resolvePersistedSelection(
            microphoneSelection.persisted,
            availableDevices: availableAudioInputDevices()
        )
        if resolved != microphoneSelection {
            persistMicrophoneSelection(resolved)
        }
        return resolved
    }

    private func updateRecordingRegionMicrophoneUI() {
        let title = "麦克风：\(resolvedMicrophoneSelection().displayName)"
        recordingRegionWindow?.setMicrophoneButtonTitle(title)
    }

    private func showMicrophoneMenu(from anchorView: NSView) {
        let current = resolvedMicrophoneSelection()
        let menu = NSMenu()

        func makeItem(title: String, selection: MicrophoneSelection) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = selection
            item.state = selection == current ? .on : .off
            return item
        }

        menu.addItem(makeItem(title: "不使用麦克风", selection: .none))
        menu.addItem(makeItem(title: "系统默认", selection: .systemDefault))

        let devices = availableAudioInputDevices()
        if !devices.isEmpty {
            menu.addItem(.separator())
            for device in devices {
                menu.addItem(makeItem(title: device.name, selection: .device(id: device.id, name: device.name)))
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.maxY + 6), in: anchorView)
        recordingRegionWindow?.refreshAccessoryVisibility()
    }

    @objc
    private func selectMicrophone(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? MicrophoneSelection else { return }
        persistMicrophoneSelection(selection)
    }

    private func makeRecordingOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "\(AppBrand.displayName)_\(formatter.string(from: Date())).mov"
        let baseDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return baseDir.appendingPathComponent(fileName)
    }

    private func handleRecordingFinished(outputURL: URL?, error: Error?) {
        if let error {
            showRecordingErrorAlert(error)
            return
        }
        guard let outputURL else { return }
        let alert = NSAlert()
        alert.messageText = "录屏完成"
        alert.informativeText = "文件已保存到：\(outputURL.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开文件夹")
        alert.addButton(withTitle: "好")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        }
    }

    private func showRecordingErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "录屏失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showAlert(_ content: RecordingAlertContent, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = content.messageText
        alert.informativeText = content.informativeText
        alert.alertStyle = style
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func microphonePermissionStatus() -> RecordingMicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

final class CameraManager {
    let session = AVCaptureSession()
    private var configured = false

    func start() {
        configureIfNeeded()
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        session.commitConfiguration()
    }
}
