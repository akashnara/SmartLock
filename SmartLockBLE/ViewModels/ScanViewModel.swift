import CoreBluetooth
import Combine

class ScanViewModel: ObservableObject {
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var discoveredDevices: [BLEDevice] = []
    @Published private(set) var bleState: CBManagerState = .unknown
    @Published private(set) var isConnecting: Bool = false
    @Published var searchText: String = ""

    // Search bar is only visible once there are more than 10 devices
    var showSearch: Bool { discoveredDevices.count > 10 }

    // Devices filtered by searchText; returns the full list when search is empty
    var filteredDevices: [BLEDevice] {
        guard showSearch && !searchText.isEmpty else { return discoveredDevices }
        return discoveredDevices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let bleManager: BLEManager
    private var cancellables = Set<AnyCancellable>()

    init(bleManager: BLEManager) {
        self.bleManager = bleManager
        bindToManager()
    }

    private func bindToManager() {
        bleManager.$isScanning
            .assign(to: &$isScanning)
        bleManager.$discoveredDevices
            .assign(to: &$discoveredDevices)
        bleManager.$bleState
            .assign(to: &$bleState)
        bleManager.$connectionState
            .map { $0 == .connecting }
            .assign(to: &$isConnecting)
    }

    func startScanning() {
        searchText = ""
        bleManager.startScanning()
    }
    func stopScanning()  { bleManager.stopScanning() }
    func connect(to device: BLEDevice) { bleManager.connect(to: device) }
}
