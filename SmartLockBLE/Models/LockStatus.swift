import SwiftUI

enum LockStatus: Equatable {
    case locked
    case unlocked
    case unknown
    case processing

    var displayText: String {
        switch self {
        case .locked:     return "Locked"
        case .unlocked:   return "Unlocked"
        case .unknown:    return "Unknown"
        case .processing: return "Processing..."
        }
    }

    var color: Color {
        switch self {
        case .locked:     return .red
        case .unlocked:   return .green
        case .unknown:    return .gray
        case .processing: return .orange
        }
    }

    var systemImage: String {
        switch self {
        case .locked:     return "lock.fill"
        case .unlocked:   return "lock.open.fill"
        case .unknown:    return "lock.slash.fill"
        case .processing: return "arrow.clockwise"
        }
    }
}
