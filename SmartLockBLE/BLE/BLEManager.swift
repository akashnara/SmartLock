import CoreBluetooth
import SwiftUI
import Combine

class BLEManager: NSObject, ObservableObject {

    enum ConnectionState {
        case disconnected, connecting, connected, disconnecting
    }

    @Published var bleState: CBManagerState = .unknown
    @Published var isScanning = false
    @Published var discoveredDevices: [BLEDevice] = []
    @Published var connectedDevice: BLEDevice?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lockStatus: LockStatus = .unknown
    @Published var batteryLevel: Int?
    @Published var errorMessage: String?

    // ON/OFF & device event notifications
    @Published var devicePowerState: DevicePowerState = .unknown
    @Published var isNotificationsEnabled = false
    @Published var deviceEvents: [DeviceEvent] = []

    // Debug: list of all (serviceUUID, charUUID, properties) found on connected device
    @Published var discoveredCharacteristics: [DiscoveredChar] = []

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var deviceCommandChar: CBCharacteristic?
    private var lockStatusChar: CBCharacteristic?
    private var deviceEventChar: CBCharacteristic?
    private var batteryLevelChar: CBCharacteristic?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scan

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            errorMessage = "Bluetooth is not available."
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(withServices: nil,
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    // MARK: - Connection

    func connect(to device: BLEDevice) {
        stopScanning()
        connectedDevice = device
        connectedPeripheral = device.peripheral
        connectionState = .connecting
        centralManager.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        connectionState = .disconnecting
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - ON / OFF Commands

    func sendDeviceCommand(_ command: DeviceCommand) {
        guard let char = deviceCommandChar, let peripheral = connectedPeripheral else {
            errorMessage = "Device command characteristic not found."
            return
        }
        devicePowerState = .processing
        peripheral.writeValue(Data([command.rawValue]), for: char, type: .withResponse)
        // Optimistically update state; corrected by notify if device sends one
        devicePowerState = (command == .on) ? .on : .off
    }

    // MARK: - Notifications

    func setNotificationsEnabled(_ enabled: Bool) {
        guard let char = deviceEventChar, let peripheral = connectedPeripheral else {
            errorMessage = "Device event characteristic not found."
            return
        }
        peripheral.setNotifyValue(enabled, for: char)
        isNotificationsEnabled = enabled
        if !enabled { deviceEvents.removeAll() }
    }

    func clearEvents() {
        deviceEvents.removeAll()
    }

    // MARK: - Status / Battery

    func readLockStatus() {
        guard let char = lockStatusChar, let peripheral = connectedPeripheral else { return }
        peripheral.readValue(for: char)
    }

    func readBatteryLevel() {
        guard let char = batteryLevelChar, let peripheral = connectedPeripheral else { return }
        peripheral.readValue(for: char)
    }

    // MARK: - Private

    private func resetState() {
        deviceCommandChar = nil
        lockStatusChar = nil
        deviceEventChar = nil
        batteryLevelChar = nil
        lockStatus = .unknown
        devicePowerState = .unknown
        batteryLevel = nil
        isNotificationsEnabled = false
        deviceEvents.removeAll()
        discoveredCharacteristics.removeAll()
        connectedDevice = nil
        connectedPeripheral = nil
    }
}

// MARK: - DiscoveredChar

struct DiscoveredChar: Identifiable {
    let id = UUID()
    let serviceUUID: String
    let charUUID: String
    let properties: String

    static func from(_ char: CBCharacteristic, service: CBService) -> DiscoveredChar {
        var props: [String] = []
        if char.properties.contains(.read)                 { props.append("Read") }
        if char.properties.contains(.write)                { props.append("Write") }
        if char.properties.contains(.writeWithoutResponse) { props.append("WriteNoRsp") }
        if char.properties.contains(.notify)               { props.append("Notify") }
        if char.properties.contains(.indicate)             { props.append("Indicate") }
        return DiscoveredChar(
            serviceUUID: service.uuid.uuidString,
            charUUID: char.uuid.uuidString,
            properties: props.joined(separator: ", ")
        )
    }
}

// MARK: - DevicePowerState

enum DevicePowerState: Equatable {
    case on, off, unknown, processing

    var displayText: String {
        switch self {
        case .on:         return "ON"
        case .off:        return "OFF"
        case .unknown:    return "Unknown"
        case .processing: return "..."
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bleState = central.state
        if central.state != .poweredOn {
            isScanning = false
            discoveredDevices.removeAll()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let device = BLEDevice(peripheral: peripheral, rssi: RSSI.intValue)
        guard !discoveredDevices.contains(where: { $0.id == device.id }) else { return }
        discoveredDevices.append(device)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        peripheral.delegate = self
        // Discover ALL services so the device works even before UUIDs are configured
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectionState = .disconnected
        errorMessage = error?.localizedDescription ?? "Failed to connect."
        resetState()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectionState = .disconnected
        resetState()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { errorMessage = error.localizedDescription; return }
        discoveredCharacteristics.removeAll()
        // Discover ALL characteristics for every service
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error { errorMessage = error.localizedDescription; return }
        service.characteristics?.forEach { char in
            discoveredCharacteristics.append(.from(char, service: service))

            // Primary: match by UUID (update SmartLockService.swift with your device's real UUIDs)
            switch char.uuid {
            case SmartLockService.deviceCommandCharUUID:
                deviceCommandChar = char

            case SmartLockService.lockStatusCharUUID:
                lockStatusChar = char
                deviceEventChar = char  // same char on Nordic LBS (00001524)
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)

            case SmartLockService.batteryLevelCharUUID:
                batteryLevelChar = char
                peripheral.readValue(for: char)

            default:
                // Fallback: assign by BLE property when UUID hasn't been configured yet
                let props = char.properties
                if deviceCommandChar == nil && (props.contains(.write) || props.contains(.writeWithoutResponse)) {
                    deviceCommandChar = char
                }
                if lockStatusChar == nil && props.contains(.read) {
                    lockStatusChar = char
                    peripheral.readValue(for: char)
                }
                if deviceEventChar == nil && props.contains(.notify) {
                    deviceEventChar = char
                }
                if batteryLevelChar == nil && service.uuid == SmartLockService.batteryServiceUUID {
                    batteryLevelChar = char
                    peripheral.readValue(for: char)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error { errorMessage = error.localizedDescription; return }
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case SmartLockService.lockStatusCharUUID:
            // Nordic LBS button char (00001524): 0x01 = pressed, 0x00 = released
            lockStatus = (data.first == 0x01) ? .locked : .unlocked
            devicePowerState = (data.first == 0x01) ? .on : .off
            // Every notification from the button char is a device event
            let event = DeviceEvent(data: data)
            deviceEvents.insert(event, at: 0)
            if deviceEvents.count > 50 { deviceEvents.removeLast() }

        case SmartLockService.batteryLevelCharUUID:
            batteryLevel = Int(data.first ?? 0)

        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            errorMessage = error.localizedDescription
            devicePowerState = .unknown
            return
        }
        // For Nordic LBS the LED write has no read-back; reflect the command we sent
        if characteristic.uuid == SmartLockService.deviceCommandCharUUID {
            // devicePowerState was set to .processing before write; resolve it now
            // The actual byte we wrote is no longer accessible here, so we keep
            // whatever the UI optimistically set — button state arrives via notify
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error { errorMessage = error.localizedDescription; return }
        if characteristic.uuid == SmartLockService.deviceEventCharUUID {
            isNotificationsEnabled = characteristic.isNotifying
        }
    }
}
