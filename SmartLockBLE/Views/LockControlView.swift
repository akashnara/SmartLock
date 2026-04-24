import SwiftUI

struct LockControlView: View {
    @StateObject private var viewModel: LockViewModel

    init(bleManager: BLEManager) {
        _viewModel = StateObject(wrappedValue: LockViewModel(bleManager: bleManager))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection
                onOffSection
                lockStatusSection
                notificationSection
                batterySection
                deviceInfoSection
                disconnectButton
            }
            .padding()
        }
        .navigationTitle(viewModel.deviceName)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.refresh()
            viewModel.readBattery()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "lock.shield.fill")
                .font(.title)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.deviceName)
                    .font(.headline)
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - ON / OFF

    private var onOffSection: some View {
        VStack(spacing: 12) {
            Text("Device Control")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                // ON button
                Button {
                    viewModel.turnOn()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "power.circle.fill")
                            .font(.system(size: 44))
                        Text("ON")
                            .font(.title3.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        viewModel.devicePowerState == .on
                            ? Color.green
                            : Color.green.opacity(0.15)
                    )
                    .foregroundStyle(
                        viewModel.devicePowerState == .on ? .white : .green
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(viewModel.devicePowerState == .on || viewModel.devicePowerState == .processing)

                // OFF button
                Button {
                    viewModel.turnOff()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "power.circle")
                            .font(.system(size: 44))
                        Text("OFF")
                            .font(.title3.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        viewModel.devicePowerState == .off
                            ? Color.red
                            : Color.red.opacity(0.15)
                    )
                    .foregroundStyle(
                        viewModel.devicePowerState == .off ? .white : .red
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(viewModel.devicePowerState == .off || viewModel.devicePowerState == .processing)
            }

            // Processing indicator
            if viewModel.devicePowerState == .processing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Sending command...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Lock Status

    private var lockStatusSection: some View {
        HStack {
            Image(systemName: viewModel.lockStatus.systemImage)
                .font(.title2)
                .foregroundStyle(viewModel.lockStatus.color)
                .frame(width: 36)
            Text("Lock Status")
                .font(.headline)
            Spacer()
            Text(viewModel.lockStatus.displayText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(viewModel.lockStatus.color)
            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .padding(.leading, 4)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Device Notifications

    private var notificationSection: some View {
        VStack(spacing: 0) {
            // Header row with toggle
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
                Text("Device Notifications")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.isNotificationsEnabled },
                    set: { viewModel.setNotifications($0) }
                ))
                .labelsHidden()
            }
            .padding()

            Divider()

            if !viewModel.isNotificationsEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .foregroundStyle(.secondary)
                    Text("Enable notifications to receive device events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if viewModel.deviceEvents.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Listening for events...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    // Clear button
                    HStack {
                        Text("\(viewModel.deviceEvents.count) event(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { viewModel.clearEvents() }
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Event list (max visible = 5, scrollable)
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.deviceEvents) { event in
                            EventRowView(event: event)
                            Divider().padding(.leading, 52)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Battery

    private var batterySection: some View {
        HStack {
            Label("Battery", systemImage: batteryIcon)
                .font(.headline)
            Spacer()
            if let level = viewModel.batteryLevel {
                Text("\(level)%")
                    .font(.headline)
                    .foregroundStyle(batteryColor)
            } else {
                Button("Read") { viewModel.readBattery() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Device Info (discovered characteristics)

    @State private var showDeviceInfo = false

    private var deviceInfoSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation { showDeviceInfo.toggle() }
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Device Info")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showDeviceInfo ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            if showDeviceInfo {
                Divider()
                if viewModel.discoveredCharacteristics.isEmpty {
                    Text("No characteristics discovered yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.discoveredCharacteristics) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Char: \(item.charUUID)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                                Text("Service: \(item.serviceUUID)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text("[\(item.properties)]")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            Divider().padding(.leading)
                        }
                        Text("Copy Write char UUID → SmartLockService.deviceCommandCharUUID\nCopy Notify char UUID → SmartLockService.deviceEventCharUUID")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding()
                    }
                }
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Disconnect

    private var disconnectButton: some View {
        Button(role: .destructive) {
            viewModel.disconnect()
        } label: {
            Label("Disconnect", systemImage: "bluetooth.slash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helpers

    private var batteryIcon: String {
        guard let level = viewModel.batteryLevel else { return "battery.0" }
        if level >= 75 { return "battery.100" }
        if level >= 50 { return "battery.75" }
        if level >= 25 { return "battery.50" }
        return "battery.25"
    }

    private var batteryColor: Color {
        guard let level = viewModel.batteryLevel else { return .gray }
        if level > 50 { return .green }
        if level > 20 { return .orange }
        return .red
    }
}

// MARK: - EventRowView

private struct EventRowView: View {
    let event: DeviceEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.description)
                    .font(.subheadline.weight(.medium))
                Text(event.formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(event.rawData.map { String(format: "%02X", $0) }.joined(separator: " "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
