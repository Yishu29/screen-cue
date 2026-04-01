import Foundation
import CoreGraphics

enum RecordingMicrophonePermissionStatus {
    case authorized
    case notDetermined
    case denied
    case restricted
}

enum RecordingMicrophoneStartAction: Equatable {
    case startRecordingImmediately
    case requestPermission
    case showPermissionDeniedAlert
}

struct RecordingAlertContent: Equatable {
    let messageText: String
    let informativeText: String
}

enum RecordingLaunchPolicy {
    static func bestMatchingScreenIndex(for frame: CGRect, candidateFrames: [CGRect]) -> Int? {
        candidateFrames.enumerated().max { lhs, rhs in
            intersectionArea(lhs.element, frame) < intersectionArea(rhs.element, frame)
        }?.offset
    }

    static func microphoneStartAction(
        selection: MicrophoneSelection,
        authorizationStatus: RecordingMicrophonePermissionStatus
    ) -> RecordingMicrophoneStartAction {
        if selection == .none {
            return .startRecordingImmediately
        }

        switch authorizationStatus {
        case .authorized:
            return .startRecordingImmediately
        case .notDetermined:
            return .requestPermission
        case .denied, .restricted:
            return .showPermissionDeniedAlert
        }
    }

    static func microphonePermissionDeniedAlert() -> RecordingAlertContent {
        RecordingAlertContent(
            messageText: "需要麦克风权限",
            informativeText: "你当前选择了带麦克风录制，但系统未允许访问麦克风。请在系统设置 > 隐私与安全性 > 麦克风中允许 \(AppBrand.displayName)，或切换为“不使用麦克风”。"
        )
    }

    static func screenCaptureFailureAlert(hasPreflightAccess: Bool) -> RecordingAlertContent {
        if hasPreflightAccess {
            return RecordingAlertContent(
                messageText: "录屏权限尚未生效",
                informativeText: "你已授权但系统仍未放行。请完全退出 \(AppBrand.displayName) 后重启；若仍无效，在系统设置中关闭后重新勾选“屏幕与系统录制”。"
            )
        }

        return RecordingAlertContent(
            messageText: "需要录屏权限",
            informativeText: "请在系统设置 > 隐私与安全性 > 屏幕与系统录制中允许 \(AppBrand.displayName)，然后重新打开应用再试。"
        )
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return max(0, intersection.width) * max(0, intersection.height)
    }
}
