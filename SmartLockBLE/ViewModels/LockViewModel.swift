import Combine

class LockViewModel: ObservableObject {
    @Published private(set) var lockStatus: LockStatus = .unknown
    @Published private(set) var devicePowerState: DevicePowerState = .unknown
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var deviceName: String = "Smart Lock"
    @Published private(set) var isNotificationsEnabled: Bool = false
    @Published private(set) var deviceEvents: [DeviceEvent] = []
    @Published private(set) var discoveredCharacteristics: [DiscoveredChar] = []

    private let bleManager: BLEManager
    private var cancellables = Set<AnyCancellable>()

    init(bleManager: BLEManager) {
        self.bleManager = bleManager
        bindToManager()
    }

    private func bindToManager() {
        bleManager.$lockStatus.assign(to: &$lockStatus)
        bleManager.$devicePowerState.assign(to: &$devicePowerState)
        bleManager.$batteryLevel.assign(to: &$batteryLevel)
        bleManager.$connectedDevice
            .map { $0?.name ?? "Smart Lock" }
            .assign(to: &$deviceName)
        bleManager.$isNotificationsEnabled.assign(to: &$isNotificationsEnabled)
        bleManager.$deviceEvents.assign(to: &$deviceEvents)
        bleManager.$discoveredCharacteristics.assign(to: &$discoveredCharacteristics)
    }

    // MARK: - Commands

    func turnOn()           { bleManager.sendDeviceCommand(.on) }
    func turnOff()          { bleManager.sendDeviceCommand(.off) }
    func refresh()          { bleManager.readLockStatus() }
    func readBattery()      { bleManager.readBatteryLevel() }
    func disconnect()       { bleManager.disconnect() }
    func clearEvents()      { bleManager.clearEvents() }
    func setNotifications(_ enabled: Bool) { bleManager.setNotificationsEnabled(enabled) }
}
