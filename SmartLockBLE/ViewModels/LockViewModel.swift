import Combine
import Foundation

class LockViewModel: ObservableObject {
    @Published private(set) var lockStatus: LockStatus = .unknown
    @Published private(set) var devicePowerState: DevicePowerState = .unknown
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var deviceName: String = "Smart Lock"
    @Published private(set) var isNotificationsEnabled: Bool = false
    @Published private(set) var deviceEvents: [DeviceEvent] = []
    @Published private(set) var discoveredCharacteristics: [DiscoveredChar] = []

    // Download / Transfer state
    @Published var showDownloadCompleteAlert: Bool = false
    @Published private(set) var isDownloading: Bool = false
    @Published private(set) var downloadProgress: Double = 0.0
    @Published private(set) var isTransferring: Bool = false
    @Published private(set) var transferProgress: Double = 0.0
    @Published var downloadError: String?
    @Published var transferError: String?

    private let bleManager: BLEManager
    private var cancellables = Set<AnyCancellable>()
    private var downloadedFileURL: URL?

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
        bleManager.$isTransferring.assign(to: &$isTransferring)
        bleManager.$transferProgress.assign(to: &$transferProgress)
    }

    var useMockTransfer: Bool {
        get { bleManager.useMockTransfer }
        set { bleManager.useMockTransfer = newValue }
    }

    // MARK: - Commands

    func turnOn()           { bleManager.sendDeviceCommand(.on) }
    func turnOff()          { bleManager.sendDeviceCommand(.off) }
    func refresh()          { bleManager.readLockStatus() }
    func readBattery()      { bleManager.readBatteryLevel() }
    func disconnect()       { bleManager.disconnect() }
    func clearEvents()      { bleManager.clearEvents() }
    func setNotifications(_ enabled: Bool) { bleManager.setNotificationsEnabled(enabled) }

    // MARK: - Download

    func downloadFile() {
        guard !isDownloading && !isTransferring else { return }
        isDownloading = true
        downloadProgress = 0.0
        downloadError = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await DownloadService.downloadFile { [weak self] progress in
                    self?.downloadProgress = progress
                }
                downloadedFileURL = url
                isDownloading = false
                showDownloadCompleteAlert = true
            } catch {
                isDownloading = false
                downloadProgress = 0.0
                downloadError = error.localizedDescription
            }
        }
    }

    func startTransfer() {
        guard let fileURL = downloadedFileURL else { return }
        showDownloadCompleteAlert = false

        Task { [weak self] in
            guard let self else { return }
            do {
                try await bleManager.sendFile(at: fileURL)
                cleanupTempFile()
                downloadedFileURL = nil
            } catch {
                cleanupTempFile()
                downloadedFileURL = nil
                transferError = error.localizedDescription
            }
        }
    }

    func cancelDownload() {
        showDownloadCompleteAlert = false
        cleanupTempFile()
        downloadedFileURL = nil
        downloadProgress = 0.0
    }

    private func cleanupTempFile() {
        guard let url = downloadedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
