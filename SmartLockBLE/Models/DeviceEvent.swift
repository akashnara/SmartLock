import Foundation

struct DeviceEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let rawData: Data
    let description: String
    let icon: String

    init(data: Data) {
        self.timestamp = Date()
        self.rawData = data

        // Nordic LBS button characteristic: 0x01 = pressed, 0x00 = released
        switch data.first {
        case 0x01: description = "Button Pressed";   icon = "hand.tap.fill"
        case 0x00: description = "Button Released";  icon = "hand.raised"
        case let byte?:
            description = "Event: 0x\(String(byte, radix: 16, uppercase: true))"
            icon = "bell.fill"
        default:
            description = "Unknown Event"
            icon = "questionmark.circle"
        }
    }

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}
