import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()

    var body: some View {
        NavigationStack {
            Group {
                switch bleManager.connectionState {
                case .connected:
                    LockControlView(bleManager: bleManager)
                default:
                    ScanView(bleManager: bleManager)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { bleManager.errorMessage != nil },
            set: { if !$0 { bleManager.errorMessage = nil } }
        )) {
            Button("OK") { bleManager.errorMessage = nil }
        } message: {
            Text(bleManager.errorMessage ?? "")
        }
    }
}
