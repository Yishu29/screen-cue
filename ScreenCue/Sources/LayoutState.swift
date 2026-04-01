import CoreGraphics

struct ScreenGeometry {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum LayoutFrameResolver {
    static func clamped(savedFrame: CGRect, fallbackFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let base = savedFrame.width > 0 && savedFrame.height > 0 ? savedFrame : fallbackFrame
        return clamped(frame: base, inside: visibleFrame)
    }

    static func clamped(frame: CGRect, inside visibleFrame: CGRect) -> CGRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return frame }
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func bestMatchingScreenIndex(for frame: CGRect, candidateScreens: [ScreenGeometry]) -> Int? {
        guard !candidateScreens.isEmpty else { return nil }

        let matches = candidateScreens.enumerated().map { entry in
            (index: entry.offset, area: intersectionArea(entry.element.frame, frame))
        }
        guard let best = matches.max(by: { $0.area < $1.area }), best.area > 0 else {
            return nil
        }
        return best.index
    }

    static func bestVisibleFrame(
        for savedFrame: CGRect?,
        candidateScreens: [ScreenGeometry],
        fallbackVisibleFrame: CGRect
    ) -> CGRect {
        guard
            let savedFrame,
            let index = bestMatchingScreenIndex(for: savedFrame, candidateScreens: candidateScreens)
        else {
            return fallbackVisibleFrame
        }
        return candidateScreens[index].visibleFrame
    }

    /// 默认头像位置：录屏选区**右下角**（AppKit 坐标系原点在左下：`minY` 为底边）。
    static func defaultCameraFrame(recordingRegion: CGRect, size: CGFloat, margin: CGFloat) -> CGRect {
        CGRect(
            x: recordingRegion.maxX - size - margin,
            y: recordingRegion.minY + margin,
            width: size,
            height: size
        )
    }

    /// 默认录屏区域：占当前屏**可视区域**宽、高各 80%，居中。
    static func defaultRecordingRegionFrame(in visibleFrame: CGRect) -> CGRect {
        let width = visibleFrame.width * 0.8
        let height = visibleFrame.height * 0.8
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// 默认提词器位置：按屏幕计算，但落在默认录屏区域内的中间偏左上位置。
    static func defaultTeleprompterFrame(in visibleFrame: CGRect, size: CGSize) -> CGRect {
        let recordingRegion = defaultRecordingRegionFrame(in: visibleFrame)
        let targetCenter = CGPoint(
            x: recordingRegion.minX + recordingRegion.width * 0.34,
            y: recordingRegion.minY + recordingRegion.height * 0.68
        )
        let frame = CGRect(
            x: targetCenter.x - size.width / 2,
            y: targetCenter.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return clamped(frame: frame, inside: visibleFrame)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return max(0, intersection.width) * max(0, intersection.height)
    }
}
