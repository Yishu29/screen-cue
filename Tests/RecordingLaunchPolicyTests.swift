import Foundation
import CoreGraphics

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct RecordingLaunchPolicyTests {
    static func main() {
        testSavedRecordingRegionPrefersBestMatchingScreen()
        testNoMicrophoneModeStartsWithoutPermissionPrompt()
        testDeniedMicrophonePermissionDoesNotStartRecording()
        testMissingScreenCapturePermissionShowsGrantAccessMessage()
        testPendingScreenCapturePermissionShowsRetryMessage()
        print("PASS")
    }

    private static func testSavedRecordingRegionPrefersBestMatchingScreen() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 1728, height: 1117)
        ]
        let savedFrame = CGRect(x: 1700, y: 120, width: 900, height: 700)

        let index = RecordingLaunchPolicy.bestMatchingScreenIndex(
            for: savedFrame,
            candidateFrames: screens
        )

        expect(index == 1, "Saved frame should restore onto the screen with the largest overlap")
    }

    private static func testNoMicrophoneModeStartsWithoutPermissionPrompt() {
        let action = RecordingLaunchPolicy.microphoneStartAction(
            selection: .none,
            authorizationStatus: .denied
        )

        expect(action == .startRecordingImmediately, "No-microphone mode should skip microphone permission checks")
    }

    private static func testDeniedMicrophonePermissionDoesNotStartRecording() {
        let action = RecordingLaunchPolicy.microphoneStartAction(
            selection: .systemDefault,
            authorizationStatus: .denied
        )

        expect(action == .showPermissionDeniedAlert, "Denied microphone access should show an alert instead of starting recording")
    }

    private static func testMissingScreenCapturePermissionShowsGrantAccessMessage() {
        let alert = RecordingLaunchPolicy.screenCaptureFailureAlert(hasPreflightAccess: false)

        expect(alert.messageText == "需要录屏权限", "Missing screen capture permission should show the grant-access title")
        expect(alert.informativeText.contains("屏幕与系统录制"), "Missing screen capture permission should tell the user where to grant access")
    }

    private static func testPendingScreenCapturePermissionShowsRetryMessage() {
        let alert = RecordingLaunchPolicy.screenCaptureFailureAlert(hasPreflightAccess: true)

        expect(alert.messageText == "录屏权限尚未生效", "Pending screen capture permission should preserve the retry title")
        expect(alert.informativeText.contains("完全退出"), "Pending screen capture permission should tell the user to restart the app")
    }
}
