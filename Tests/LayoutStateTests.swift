import Foundation
import CoreGraphics

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct LayoutStateTests {
    static func main() {
        testBestVisibleFramePrefersScreenContainingSavedFrame()
        testBestVisibleFrameFallsBackWhenSavedFrameNoLongerMatchesAnyScreen()

        let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let saved = CGRect(x: 900, y: 650, width: 240, height: 180)
        let restored = LayoutFrameResolver.clamped(
            savedFrame: saved,
            fallbackFrame: .zero,
            visibleFrame: visible
        )
        expect(restored.maxX <= visible.maxX, "Restored frame should be clamped inside visible frame")
        expect(restored.maxY <= visible.maxY, "Restored frame should be vertically clamped")

        let region = CGRect(x: 100, y: 100, width: 780, height: 520)
        let camera = LayoutFrameResolver.defaultCameraFrame(
            recordingRegion: region,
            size: 180,
            margin: 24
        )
        expect(camera.maxX <= region.maxX, "Default camera should sit inside region on the right")
        expect(camera.minY >= region.minY, "Default camera should sit inside region on the bottom")

        let defaultRegion = LayoutFrameResolver.defaultRecordingRegionFrame(in: visible)
        expect(abs(defaultRegion.width - 800) < 0.5, "Default recording region width should be 80% of visible")
        expect(abs(defaultRegion.height - 560) < 0.5, "Default recording region height should be 80% of visible")

        let teleprompter = LayoutFrameResolver.defaultTeleprompterFrame(
            in: visible,
            size: CGSize(width: 520, height: 240)
        )
        let teleprompterCenter = CGPoint(x: teleprompter.midX, y: teleprompter.midY)
        expect(defaultRegion.contains(teleprompterCenter), "Default teleprompter center should stay inside recording region")
        expect(teleprompterCenter.x < defaultRegion.midX, "Default teleprompter should sit left of recording region center")
        expect(teleprompterCenter.y > defaultRegion.midY, "Default teleprompter should sit above recording region center")

        print("PASS")
    }

    private static func testBestVisibleFramePrefersScreenContainingSavedFrame() {
        let screens = [
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
            ),
            ScreenGeometry(
                frame: CGRect(x: 1440, y: 0, width: 1728, height: 1117),
                visibleFrame: CGRect(x: 1440, y: 40, width: 1728, height: 1037)
            )
        ]
        let savedFrame = CGRect(x: 1800, y: 200, width: 520, height: 240)
        let restoredVisible = LayoutFrameResolver.bestVisibleFrame(
            for: savedFrame,
            candidateScreens: screens,
            fallbackVisibleFrame: screens[0].visibleFrame
        )

        expect(restoredVisible == screens[1].visibleFrame, "Saved frame should restore using the visible frame of its original screen")
    }

    private static func testBestVisibleFrameFallsBackWhenSavedFrameNoLongerMatchesAnyScreen() {
        let screens = [
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
            )
        ]
        let staleSavedFrame = CGRect(x: 2200, y: 200, width: 520, height: 240)
        let restoredVisible = LayoutFrameResolver.bestVisibleFrame(
            for: staleSavedFrame,
            candidateScreens: screens,
            fallbackVisibleFrame: screens[0].visibleFrame
        )

        expect(restoredVisible == screens[0].visibleFrame, "Unmatched saved frame should fall back to the default visible frame")
    }
}
