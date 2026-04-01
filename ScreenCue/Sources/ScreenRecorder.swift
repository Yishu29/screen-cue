import AppKit
import AVFoundation
import ScreenCaptureKit

enum ScreenRecorderError: LocalizedError {
    case missingDisplayID
    case unavailableDisplay
    case alreadyRecording
    case failedToStopRecording

    var errorDescription: String? {
        switch self {
        case .missingDisplayID:
            return "无法识别目标屏幕。"
        case .unavailableDisplay:
            return "当前屏幕无法用于录制。"
        case .alreadyRecording:
            return "当前正在录屏。"
        case .failedToStopRecording:
            return "停止录屏失败。"
        }
    }
}

@available(macOS 15.0, *)
final class ScreenRecorder: NSObject, SCRecordingOutputDelegate {
    private struct CaptureDiagnostics {
        let outputURL: URL
        let lines: [String]

        func write() {
            let text = lines.joined(separator: "\n") + "\n"
            try? FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? text.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private(set) var isRecording = false
    private var isStopping = false
    private var didDeliverCompletion = false
    private(set) var lastDiagnosticsURL: URL?

    var onRecordingStateChanged: ((Bool) -> Void)?
    var onRecordingFinished: ((URL?, Error?) -> Void)?

    /// `beforeCaptureStarts` 在已拿到 `SCShareableContent` 并建好 `SCContentFilter` 之后、`startCapture` 之前调用。
    /// 用于先让需排除的窗口出现在 `exceptingWindows` 里，再隐藏选区红框、显示蒙版等，否则 `orderOut` 过的窗口不在枚举里会导致排除失效。
    func startRecording(
        screen: NSScreen,
        regionOnScreen: NSRect,
        excludedWindowIDs: [CGWindowID],
        microphoneSelection: MicrophoneSelection,
        outputURL: URL,
        beforeCaptureStarts: (@MainActor () -> Void)? = nil
    ) async throws {
        guard !isRecording else { throw ScreenRecorderError.alreadyRecording }
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw ScreenRecorderError.missingDisplayID
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenRecorderError.unavailableDisplay
        }

        let excludedWindows = shareableContent.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: excludedWindows)
        let configuration = makeStreamConfiguration(
            display: display,
            screen: screen,
            regionOnScreen: regionOnScreen,
            filter: filter,
            microphoneSelection: microphoneSelection
        )
        writeDiagnostics(
            screen: screen,
            display: display,
            filter: filter,
            regionOnScreen: regionOnScreen,
            configuration: configuration,
            excludedWindowIDs: excludedWindowIDs,
            resolvedExcludedWindowCount: excludedWindows.count,
            microphoneSelection: microphoneSelection
        )

        if let beforeCaptureStarts {
            await MainActor.run {
                beforeCaptureStarts()
            }
            await Task.yield()
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)

        try stream.addRecordingOutput(recordingOutput)
        try await stream.startCapture()

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.outputURL = outputURL
        isRecording = true
        isStopping = false
        didDeliverCompletion = false
        onRecordingStateChanged?(true)
    }

    func stopRecording() {
        guard let stream, let recordingOutput, isRecording else { return }
        guard !isStopping else { return }
        isStopping = true

        Task {
            do {
                try stream.removeRecordingOutput(recordingOutput)
            } catch {
                await MainActor.run {
                    self.finishRecording(error: error)
                }
            }
        }
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in
            let resolvedError = shouldTreatAsSuccessfulStop(for: error) ? nil : error
            finishRecording(error: resolvedError)
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            finishRecording(error: nil)
        }
    }

    private func cleanup() {
        stream = nil
        self.recordingOutput = nil
        outputURL = nil
        isStopping = false
        didDeliverCompletion = false
    }

    @MainActor
    private func finishRecording(error: Error?) {
        guard !didDeliverCompletion else { return }
        didDeliverCompletion = true

        let finalURL = outputURL
        let finalError = error
        let currentStream = stream

        Task {
            if let currentStream {
                try? await currentStream.stopCapture()
            }
            await MainActor.run {
                self.isRecording = false
                self.onRecordingStateChanged?(false)
                self.onRecordingFinished?(finalURL, finalError)
                self.cleanup()
            }
        }
    }

    private func shouldTreatAsSuccessfulStop(for error: Error) -> Bool {
        guard isStopping, let outputURL else { return false }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > 0
        else {
            return false
        }

        let nsError = error as NSError
        return nsError.domain == "com.apple.ReplayKit.RPRecordingErrorDomain"
    }

    private func makeStreamConfiguration(
        display: SCDisplay,
        screen: NSScreen,
        regionOnScreen: NSRect,
        filter: SCContentFilter,
        microphoneSelection: MicrophoneSelection
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let cropRect = convertToDisplayCropRect(regionOnScreen, in: screen, display: display)

        configuration.sourceRect = cropRect
        // 与系统捕获坐标系一致的点→像素倍率；自行用 display / NSScreen 推算在缩放显示器上容易偏小。
        let pointToPixel = CGFloat(filter.pointPixelScale)
        let fallbackScaleX = CGFloat(display.width) / max(1, screen.frame.width)
        let fallbackScaleY = CGFloat(display.height) / max(1, screen.frame.height)
        let scale = pointToPixel > 0 ? pointToPixel : max(fallbackScaleX, fallbackScaleY)

        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.width = max(1, Int(ceil(cropRect.width * scale)))
        configuration.height = max(1, Int(ceil(cropRect.height * scale)))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.showsCursor = true
        configuration.capturesAudio = false
        switch microphoneSelection {
        case .none:
            configuration.captureMicrophone = false
            configuration.microphoneCaptureDeviceID = nil
        case .systemDefault:
            configuration.captureMicrophone = true
            configuration.microphoneCaptureDeviceID = nil
        case let .device(id, _):
            configuration.captureMicrophone = true
            configuration.microphoneCaptureDeviceID = id
        }
        return configuration
    }

    private func convertToDisplayCropRect(_ region: NSRect, in screen: NSScreen, display: SCDisplay) -> CGRect {
        let clipped = region.intersection(screen.frame)
        let globalCGRect = convertAppKitRectToCoreGraphics(clipped)

        // ScreenCaptureKit display capture expects sourceRect in display-local
        // coordinates, but with CoreGraphics' top-left-based global geometry.
        return CGRect(
            x: globalCGRect.minX - display.frame.minX,
            y: globalCGRect.minY - display.frame.minY,
            width: globalCGRect.width,
            height: globalCGRect.height
        )
    }

    private func convertAppKitRectToCoreGraphics(_ rect: CGRect) -> CGRect {
        let mainScreenHeight = mainScreenFrameHeight()
        return CGRect(
            x: rect.minX,
            y: mainScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func mainScreenFrameHeight() -> CGFloat {
        let mainDisplayID = CGMainDisplayID()
        let mainScreen = NSScreen.screens.first {
            guard let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(screenNumber.uint32Value) == mainDisplayID
        }
        return mainScreen?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }

    private func writeDiagnostics(
        screen: NSScreen,
        display: SCDisplay,
        filter: SCContentFilter,
        regionOnScreen: NSRect,
        configuration: SCStreamConfiguration,
        excludedWindowIDs: [CGWindowID],
        resolvedExcludedWindowCount: Int,
        microphoneSelection: MicrophoneSelection
    ) {
        let diagnosticsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(AppBrand.displayName)")
            .appendingPathComponent("screen-recorder-diagnostics.txt")
        lastDiagnosticsURL = diagnosticsURL

        let screenNumber = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let cgBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber))
        let sourceRect = configuration.sourceRect
        let globalCGRect = convertAppKitRectToCoreGraphics(regionOnScreen.intersection(screen.frame))
        let cropRect = convertToDisplayCropRect(regionOnScreen, in: screen, display: display)
        let scaleX = CGFloat(display.width) / max(1, screen.frame.width)
        let scaleY = CGFloat(display.height) / max(1, screen.frame.height)
        let pointToPixel = CGFloat(filter.pointPixelScale)

        var lines: [String] = []
        lines.append("timestamp=\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("mainDisplayID=\(CGMainDisplayID())")
        lines.append("selectedScreen.id=\(screenNumber)")
        lines.append("selectedScreen.frame=\(NSStringFromRect(screen.frame))")
        lines.append("selectedScreen.visibleFrame=\(NSStringFromRect(screen.visibleFrame))")
        lines.append("selectedScreen.backingScaleFactor=\(screen.backingScaleFactor)")
        lines.append("selectedScreen.cgDisplayBounds=\(cgBounds)")
        lines.append("regionOnScreen=\(NSStringFromRect(regionOnScreen))")
        lines.append("globalCGRect=\(NSStringFromRect(globalCGRect))")
        lines.append("clippedCropRect=\(NSStringFromRect(cropRect))")
        lines.append("sourceRect=\(NSStringFromRect(sourceRect))")
        lines.append("configuration.width=\(configuration.width)")
        lines.append("configuration.height=\(configuration.height)")
        lines.append("configuration.captureResolution=\(configuration.captureResolution.rawValue)")
        lines.append("configuration.captureMicrophone=\(configuration.captureMicrophone)")
        lines.append("configuration.microphoneCaptureDeviceID=\(configuration.microphoneCaptureDeviceID ?? "nil")")
        lines.append("microphoneSelection=\(String(describing: microphoneSelection))")
        lines.append("filter.pointPixelScale=\(pointToPixel)")
        lines.append("scaleX=\(scaleX)")
        lines.append("scaleY=\(scaleY)")
        lines.append("display.displayID=\(display.displayID)")
        lines.append("display.frame=\(NSStringFromRect(display.frame))")
        lines.append("display.width=\(display.width)")
        lines.append("display.height=\(display.height)")
        lines.append("filter.contentRect=\(NSStringFromRect(filter.contentRect))")
        lines.append("filter.pointPixelScale=\(filter.pointPixelScale)")
        let excludedWindowIDsText = excludedWindowIDs.map { String($0) }.joined(separator: ",")
        lines.append("excludedWindowIDs=\(excludedWindowIDsText)")
        lines.append("excludedWindowsResolved=\(resolvedExcludedWindowCount)_of_\(excludedWindowIDs.count)")
        lines.append("allScreens.begin")
        for candidate in NSScreen.screens {
            let candidateID = (candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            lines.append("screen id=\(candidateID) frame=\(NSStringFromRect(candidate.frame)) visible=\(NSStringFromRect(candidate.visibleFrame)) scale=\(candidate.backingScaleFactor) cgBounds=\(CGDisplayBounds(CGDirectDisplayID(candidateID)))")
        }
        lines.append("allScreens.end")

        CaptureDiagnostics(outputURL: diagnosticsURL, lines: lines).write()
    }
}
