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

    @Published var isTransferring: Bool = false
    @Published var transferProgress: Double = 0.0

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var deviceCommandChar: CBCharacteristic?
    private var lockStatusChar: CBCharacteristic?
    private var deviceEventChar: CBCharacteristic?
    private var batteryLevelChar: CBCharacteristic?
    private var fileTransferChar: CBCharacteristic?
    private var pendingWriteContinuation: CheckedContinuation<Void, Error>?
    private var pendingReadyContinuation: CheckedContinuation<Void, Never>?

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
        fileTransferChar = nil
        pendingWriteContinuation?.resume(throwing: BLETransferError.disconnected)
        pendingWriteContinuation = nil
        pendingReadyContinuation?.resume()
        pendingReadyContinuation = nil
        lockStatus = .unknown
        devicePowerState = .unknown
        batteryLevel = nil
        isTransferring = false
        transferProgress = 0.0
        isNotificationsEnabled = false
        deviceEvents.removeAll()
        discoveredCharacteristics.removeAll()
        connectedDevice = nil
        connectedPeripheral = nil
    }

    // MARK: - File Transfer

    /// Set to true to simulate a transfer with fake progress (useful for UI demos
    /// without real Nordic hardware). Real BLE writes are skipped entirely.
    var useMockTransfer: Bool = false

    func sendFile(at url: URL) async throws {
        if useMockTransfer {
            try await simulateMockTransfer(url: url)
            return
        }

        guard let peripheral = connectedPeripheral else {
            throw BLETransferError.notConnected
        }
        guard let char = fileTransferChar ?? deviceCommandChar else {
            throw BLETransferError.noWritableCharacteristic
        }

        // Prefer .withoutResponse for bulk data transfer: it has higher throughput and is
        // what most custom BLE file-transfer characteristics expect. Many peripherals declare
        // both .write and .writeWithoutResponse but only implement Write Command (without
        // response) — sending a Write Request (with response) to such a characteristic
        // causes ATT error 6 "Request Not Supported".
        let writeType: CBCharacteristicWriteType
        if char.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else if char.properties.contains(.write) {
            writeType = .withResponse
        } else {
            throw BLETransferError.noWritableCharacteristic
        }

        let writeTypeName = writeType == .withResponse ? "withResponse" : "withoutResponse"

        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            throw BLETransferError.writeError(error,
                                              charUUID: char.uuid.uuidString,
                                              writeType: writeTypeName)
        }

        let chunkSize = peripheral.maximumWriteValueLength(for: writeType)
        let totalBytes = fileData.count
        var bytesSent = 0

        isTransferring = true
        transferProgress = 0.0
        defer { isTransferring = false }

        while bytesSent < totalBytes {
            guard connectedPeripheral != nil else {
                throw BLETransferError.disconnected
            }

            let end = min(bytesSent + chunkSize, totalBytes)
            let chunk = fileData.subdata(in: bytesSent..<end)

            if writeType == .withResponse {
                // didWriteValueFor resumes this continuation after each ACK
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    precondition(pendingWriteContinuation == nil,
                                 "BLEManager: overlapping file transfer writes — this should never happen")
                    pendingWriteContinuation = cont
                    peripheral.writeValue(chunk, for: char, type: .withResponse)
                }
            } else {
                // Wait for the peripheral's TX buffer to drain before sending
                if !peripheral.canSendWriteWithoutResponse {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        pendingReadyContinuation = cont
                    }
                    guard connectedPeripheral != nil else {
                        throw BLETransferError.disconnected
                    }
                }
                peripheral.writeValue(chunk, for: char, type: .withoutResponse)
            }

            bytesSent = end
            transferProgress = Double(bytesSent) / Double(totalBytes)
        }
    }

    private func simulateMockTransfer(url: URL) async throws {
        let totalBytes = (try? Data(contentsOf: url))?.count ?? 1
        let steps = 20

        isTransferring = true
        transferProgress = 0.0
        defer { isTransferring = false }

        for step in 1...steps {
            try await Task.sleep(nanoseconds: 150_000_000)   // 150 ms per step
            guard connectedPeripheral != nil else { throw BLETransferError.disconnected }
            transferProgress = Double(step) / Double(steps)
        }
        _ = totalBytes  // suppress unused warning
    }
}

// MARK: - BLETransferError

enum BLETransferError: LocalizedError {
    case notConnected
    case noWritableCharacteristic
    case writeError(Error, charUUID: String, writeType: String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No device connected. Please connect a device and try again."
        case .noWritableCharacteristic:
            return "Device does not expose a writable characteristic for file transfer."
        case .writeError(let error, let uuid, let type):
            return "Write failed on \(uuid) (\(type)): \(error.localizedDescription)"
        case .disconnected:
            return "Device disconnected during transfer."
        }
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
            print(char.uuid)
            switch char.uuid {
            case SmartLockService.deviceCommandCharUUID:
                deviceCommandChar = char

            case SmartLockService.fileTransferCharUUID:
                fileTransferChar = char

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
        // Route file-transfer chunk ACK to the waiting continuation (regardless of char UUID,
        // because fileTransferChar may fall back to deviceCommandChar on some peripherals)
        if let continuation = pendingWriteContinuation {
            pendingWriteContinuation = nil
            if let error {
                continuation.resume(throwing: BLETransferError.writeError(
                    error,
                    charUUID: characteristic.uuid.uuidString,
                    writeType: "withResponse"
                ))
            } else {
                continuation.resume(returning: ())
            }
            return
        }
        // Normal device command write (LED on/off)
        if let error {
            errorMessage = error.localizedDescription
            devicePowerState = .unknown
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

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if let cont = pendingReadyContinuation {
            pendingReadyContinuation = nil
            cont.resume()
        }
    }
}
