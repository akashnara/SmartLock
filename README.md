# SmartLock BLE — iOS Demo App

A Swift/SwiftUI proof-of-concept iOS app for controlling a BLE SmartLock device built on the **Nordic nRF5 LED Button Service (LBS)** profile. Demonstrates scanning, connecting, device control, status monitoring, file download, and BLE file transfer in a clean MVVM architecture.

---

## Features

### Core (main branch)
| Feature | Description |
|---|---|
| BLE Scanning | Discover nearby BLE peripherals in real time |
| Device Connection | One-tap connect with live connection state feedback |
| ON / OFF Control | Write commands to the LED characteristic (Nordic LBS) |
| Lock Status | Read & observe button state (locked / unlocked) |
| Device Notifications | Subscribe to button-press events via BLE notify |
| Battery Level | Read standard GATT Battery Service (0x180F / 0x2A19) |
| Event Log | Live scrollable log of button-press / release events (max 50) |
| Device Info | Expandable debug view of all discovered services & characteristics |
| Error Handling | Global alert for BLE errors; Bluetooth unavailable screen |

### Feature Branch — `fileDownloadAndTransfer`
| Feature | Description |
|---|---|
| Download File | Download a binary file from a remote URL via `URLSession` with live progress |
| BLE File Transfer | Send the downloaded file to the connected peripheral in MTU-sized chunks |
| Transfer Progress | Real-time progress bar (blue = downloading, purple = BLE transfer) |
| Mock Transfer Mode | Simulate a full transfer with fake progress for UI demos without real hardware |
| Device Search | Live local search in the device list (visible only when > 10 devices found) |

---

## Architecture

The app follows **MVVM** with a single shared `BLEManager` as the source of truth for all Bluetooth state.

```
┌─────────────────────────────────────────────────┐
│  SwiftUI Views                                  │
│  ContentView → ScanView / LockControlView       │
└──────────────────┬──────────────────────────────┘
                   │ @StateObject + Combine bindings
┌──────────────────▼──────────────────────────────┐
│  ViewModels                                     │
│  ScanViewModel          LockViewModel           │
│  · filteredDevices      · downloadFile()        │
│  · showSearch           · startTransfer()       │
│  · searchText           · cancelDownload()      │
└──────────────────┬──────────────────────────────┘
                   │ method calls + @Published
┌──────────────────▼──────────────────────────────┐
│  BLEManager  (NSObject, ObservableObject)       │
│  · CBCentralManagerDelegate                     │
│  · CBPeripheralDelegate                         │
│  · sendDeviceCommand()   sendFile()             │
│  · CheckedContinuation for async BLE writes     │
└──────────────────┬──────────────────────────────┘
                   │ CoreBluetooth
┌──────────────────▼──────────────────────────────┐
│  Hardware — Nordic nRF5 SmartLock               │
│  Nordic LED Button Service (LBS)                │
└─────────────────────────────────────────────────┘
```

### Key Design Decisions

- **Single Source of Truth** — `BLEManager` owns all BLE state. ViewModels are thin Combine projections using `.assign(to:)`.
- **State-Driven Navigation** — `ContentView` switches between `ScanView` and `LockControlView` based on `bleManager.connectionState`. No `NavigationLink` needed.
- **Async/Await BLE Bridge** — `sendFile(at:)` uses `CheckedContinuation` to bridge the `peripheral(_:didWriteValueFor:error:)` delegate callback into `async/await`, enabling a clean sequential write loop.
- **Write Type Auto-Detection** — File transfer prefers `.writeWithoutResponse` (higher throughput, what most custom BLE data characteristics expect). Falls back to `.withResponse` only if the characteristic doesn't support Without Response.
- **Dependency Injection** — `BLEManager` is created once in `ContentView` and passed down via `init(bleManager:)`.

---

## Project Structure

```
SmartLockBLE/
├── App/
│   └── SmartLockBLEApp.swift       Entry point (@main)
│
├── BLE/
│   ├── BLEManager.swift            Core Bluetooth manager
│   │                               CBCentralManager + CBPeripheralDelegate
│   │                               Scanning, connection, commands, file transfer
│   └── SmartLockService.swift      Nordic LBS UUID constants + DeviceCommand enum
│
├── Models/
│   ├── BLEDevice.swift             Wraps CBPeripheral with name + RSSI
│   ├── LockStatus.swift            Enum: locked / unlocked / unknown / processing
│   └── DeviceEvent.swift           Button press/release event with timestamp
│
├── ViewModels/
│   ├── ScanViewModel.swift         Scan state, device list, local search filter
│   └── LockViewModel.swift         Lock control, download, transfer state + methods
│
├── Views/
│   ├── ContentView.swift           Navigation hub (scan ↔ lock control)
│   ├── ScanView.swift              Device list with search bar
│   ├── DeviceRowView.swift         Single device row (stateless)
│   └── LockControlView.swift       Connected device control screen
│
└── Services/                       (fileDownloadAndTransfer branch)
    └── DownloadService.swift       Async file download with streaming progress
```

---

## BLE Protocol — Nordic LBS (LED Button Service)

| Role | UUID | Operation |
|---|---|---|
| LBS Primary Service | `00001523-1212-EFDE-1523-785FEABCD123` | — |
| LED Characteristic (Command) | `00001525-1212-EFDE-1523-785FEABCD123` | Write |
| Button Characteristic (Event) | `00001524-1212-EFDE-1523-785FEABCD123` | Read + Notify |
| File Transfer Characteristic | `00001526-1212-EFDE-1523-785FEABCD123` | Write (optional) |
| Battery Service | `180F` | — |
| Battery Level | `2A19` | Read |

### Command Bytes (LED Characteristic)
| Command | Byte |
|---|---|
| LED ON | `0x01` |
| LED OFF | `0x00` |

### Button Notification Values
| Value | Meaning |
|---|---|
| `0x01` | Button Pressed → Lock Status: Locked |
| `0x00` | Button Released → Lock Status: Unlocked |

> **Configuring for your device:** Open the **Device Info** section in the app after connecting. Copy the Write characteristic UUID into `SmartLockService.deviceCommandCharUUID` and the Notify characteristic UUID into `SmartLockService.deviceEventCharUUID` in `SmartLockService.swift`.

---

## File Download & Transfer (fileDownloadAndTransfer branch)

### Flow
```
[Download File button]
        ↓
DownloadService.downloadFile()          — URLSession.bytes(from:) streaming
        ↓ progress 0→100%
Temp file saved to FileManager.temporaryDirectory
        ↓
Alert: "Download Complete" → [Transfer] or [Cancel]
        ↓ Transfer tapped
BLEManager.sendFile(at:)               — chunked BLE writes
        ↓ MTU-sized chunks (auto-detected)
peripheral.writeValue(chunk, for: char, type: writeType)
        ↓ didWriteValueFor → CheckedContinuation resumes
        ↓ progress 0→100%
Transfer complete → temp file deleted
```

### Write Type Detection
```swift
// Prefer withoutResponse (bulk data, higher throughput)
if char.properties.contains(.writeWithoutResponse) → .withoutResponse
else if char.properties.contains(.write)           → .withResponse
else                                               → throw noWritableCharacteristic
```

### Characteristic Fallback
`fileTransferChar (0x00001526)` → if not found → falls back to `deviceCommandChar (0x00001525)`

### Mock Transfer Mode
Enable the **Mock Transfer** toggle inside Device Info to simulate a full BLE transfer with fake progress (3 seconds, 20 steps). Useful for demoing the UI without Nordic hardware.

> **Important:** BLE file transfer only works with a device that has a compatible GATT server (e.g., Nordic nRF5 running LBS firmware). Standard consumer devices (Mac, Android phone, Windows PC) do not accept arbitrary data writes to their BLE characteristics.

---

## Device Search (fileDownloadAndTransfer branch)

- The search bar appears **automatically** when more than **10 devices** are discovered.
- Search is **local** — filters the already-discovered list, no new BLE scan triggered.
- **Case-insensitive**, matches device name anywhere (prefix, middle, suffix).
- Cleared automatically when a new scan starts.
- Shows a **"No devices match"** state when the query has no results.

---

## Requirements

| Requirement | Value |
|---|---|
| iOS | 16.6+ |
| Xcode | 15+ |
| Swift | 5.9+ |
| Device | Physical iPhone/iPad (BLE not available in Simulator) |
| Hardware | Nordic nRF5 development kit running LBS firmware (for real transfer) |

---

## Getting Started

1. **Clone the repo**
   ```bash
   git clone https://github.com/akashnara/SmartLock.git
   cd SmartLock
   ```

2. **Open in Xcode**
   ```bash
   open SmartLockBLE.xcodeproj
   ```

3. **Select your team** in Signing & Capabilities → set your Apple Developer team.

4. **Run on a physical device** — BLE is not available in the iOS Simulator.

5. **Tap Scan** → discover nearby BLE devices → tap **Connect** on your Nordic SmartLock.

---

## Branches

| Branch | Description |
|---|---|
| `main` | Core BLE scanning, connection, device control |
| `fileDownloadAndTransfer` | + File download, BLE transfer, device search |

```bash
# Switch to feature branch
git checkout fileDownloadAndTransfer

# Switch back to main
git checkout main
```

---

## Error Handling

| Scenario | Handling |
|---|---|
| Bluetooth off | "Bluetooth Unavailable" screen with Settings prompt |
| BLE error | Global alert via `bleManager.errorMessage` |
| Connect failed | Alert + state reset |
| Download — no internet | "No internet connection" alert |
| Download — HTTP error | "Server returned error {code}" alert |
| Transfer — not connected | "No device connected" alert |
| Transfer — no writable char | "Device does not expose a writable characteristic" alert |
| Transfer — write rejected | Alert with characteristic UUID + write type for diagnosis |
| Transfer — disconnect mid-send | `CheckedContinuation` resumed with `.disconnected` error → alert |

---

## License

MIT — free to use, modify, and distribute.
