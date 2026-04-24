import SwiftUI

struct DeviceRowView: View {
    let device: BLEDevice
    let isConnecting: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                Text("Signal: \(device.rssi) dBm  •  \(device.id.uuidString.prefix(8))...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnecting {
                ProgressView()
            } else {
                Button("Connect", action: onConnect)
                    .buttonStyle(.bordered)
                    .tint(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
