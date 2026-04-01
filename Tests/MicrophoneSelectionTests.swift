import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct MicrophoneSelectionTests {
    static func main() {
        let persisted = PersistedMicrophoneSelection(
            kindRawValue: "device",
            deviceID: "mic-123",
            deviceName: "USB Mic"
        )
        let available = [
            AudioInputDevice(id: "builtin", name: "MacBook Mic"),
            AudioInputDevice(id: "mic-123", name: "USB Mic")
        ]

        let restored = MicrophoneSelection.resolvePersistedSelection(
            persisted,
            availableDevices: available
        )
        expect(
            restored == .device(id: "mic-123", name: "USB Mic"),
            "Should restore saved device when still available"
        )

        let missing = MicrophoneSelection.resolvePersistedSelection(
            PersistedMicrophoneSelection(kindRawValue: "device", deviceID: "gone", deviceName: "Old Mic"),
            availableDevices: available
        )
        expect(missing == .systemDefault, "Missing device should fall back to system default")

        let none = MicrophoneSelection.none.persisted
        expect(none.kindRawValue == "none", "None selection should persist as none")
        expect(none.deviceID == nil, "None selection should not persist device ID")

        print("PASS")
    }
}
