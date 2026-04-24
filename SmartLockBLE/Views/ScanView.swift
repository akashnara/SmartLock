import SwiftUI
import CoreBluetooth

struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel

    init(bleManager: BLEManager) {
        _viewModel = StateObject(wrappedValue: ScanViewModel(bleManager: bleManager))
    }

    var body: some View {
        Group {
            if viewModel.bleState == .poweredOn {
                deviceListView
            } else {
                bluetoothUnavailableView
            }
        }
        .navigationTitle("Smart Lock")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(viewModel.isScanning ? "Stop" : "Scan") {
                    viewModel.isScanning ? viewModel.stopScanning() : viewModel.startScanning()
                }
                .disabled(viewModel.bleState != .poweredOn || viewModel.isConnecting)
            }
        }
    }

    private var deviceListView: some View {
        List {
            if viewModel.discoveredDevices.isEmpty {
                HStack(spacing: 12) {
                    if viewModel.isScanning { ProgressView() }
                    Text(viewModel.isScanning ? "Scanning for devices..." : "No devices found. Tap Scan.")
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.discoveredDevices) { device in
                    DeviceRowView(device: device, isConnecting: viewModel.isConnecting) {
                        viewModel.connect(to: device)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var bluetoothUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bluetooth.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(bleStateMessage)
                .font(.headline)
            Text("Please enable Bluetooth in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bleStateMessage: String {
        switch viewModel.bleState {
        case .poweredOff:   return "Bluetooth is Off"
        case .unauthorized: return "Bluetooth Not Authorized"
        case .unsupported:  return "Bluetooth Not Supported"
        default:            return "Bluetooth Unavailable"
        }
    }
}
