import Foundation

struct AudioInputDevice: Equatable {
    let id: String
    let name: String
}

struct PersistedMicrophoneSelection: Equatable {
    let kindRawValue: String
    let deviceID: String?
    let deviceName: String?
}

enum MicrophoneSelection: Equatable {
    case none
    case systemDefault
    case device(id: String, name: String)

    var persisted: PersistedMicrophoneSelection {
        switch self {
        case .none:
            return PersistedMicrophoneSelection(kindRawValue: "none", deviceID: nil, deviceName: nil)
        case .systemDefault:
            return PersistedMicrophoneSelection(kindRawValue: "systemDefault", deviceID: nil, deviceName: nil)
        case let .device(id, name):
            return PersistedMicrophoneSelection(kindRawValue: "device", deviceID: id, deviceName: name)
        }
    }

    var displayName: String {
        switch self {
        case .none:
            return "关闭"
        case .systemDefault:
            return "系统默认"
        case let .device(_, name):
            return name
        }
    }

    static func resolvePersistedSelection(
        _ persisted: PersistedMicrophoneSelection?,
        availableDevices: [AudioInputDevice]
    ) -> MicrophoneSelection {
        guard let persisted else { return .systemDefault }
        switch persisted.kindRawValue {
        case "none":
            return .none
        case "device":
            guard let deviceID = persisted.deviceID,
                  let device = availableDevices.first(where: { $0.id == deviceID }) else {
                return .systemDefault
            }
            return .device(id: device.id, name: device.name)
        default:
            return .systemDefault
        }
    }
}
