import CoreBluetooth
import Combine

class ScanViewModel: ObservableObject {
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var discoveredDevices: [BLEDevice] = []
    @Published private(set) var bleState: CBManagerState = .unknown
    @Published private(set) var isConnecting: Bool = false

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

    func startScanning() { bleManager.startScanning() }
    func stopScanning()  { bleManager.stopScanning() }
    func connect(to device: BLEDevice) { bleManager.connect(to: device) }
}
