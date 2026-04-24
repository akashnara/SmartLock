import CoreBluetooth

// Nordic LBS (LED Button Service) — Nordic nRF5 SDK demo peripheral
enum SmartLockService {
    // LBS primary service
    static let lockServiceUUID       = CBUUID(string: "00001523-1212-EFDE-1523-785FEABCD123")

    // LED characteristic — Write: 0x01 = ON, 0x00 = OFF
    static let deviceCommandCharUUID = CBUUID(string: "00001525-1212-EFDE-1523-785FEABCD123")

    // Button characteristic — Notify: 0x01 = pressed, 0x00 = released
    static let deviceEventCharUUID   = CBUUID(string: "00001524-1212-EFDE-1523-785FEABCD123")

    // Lock status re-uses button char for state display
    static let lockStatusCharUUID    = CBUUID(string: "00001524-1212-EFDE-1523-785FEABCD123")

    // Standard GATT Battery Service (0x180F / 0x2A19)
    static let batteryServiceUUID    = CBUUID(string: "180F")
    static let batteryLevelCharUUID  = CBUUID(string: "2A19")
}

// Command bytes written to the LED characteristic
enum DeviceCommand: UInt8 {
    case on  = 0x01   // LED ON
    case off = 0x00   // LED OFF
}
