import Foundation

// MARK: - Client

struct Client: Identifiable {
    var id: String = UUID().uuidString
    var firstName: String
    var lastName: String
    var email: String
    var plan: String
    var sessions: Int
    var lastSeen: String
    var status: ClientStatus
    var trainerId: String?
    var colorIndex: Int
    var videos: [ClientVideo]
    var workouts: [WorkoutPlan]

    var initials: String { "\(firstName.prefix(1))\(lastName.prefix(1))" }
    var fullName: String { "\(firstName) \(lastName)" }
}

enum ClientStatus: String, CaseIterable {
    case active, inactive
}

// MARK: - Video

struct ClientVideo: Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var date: String
    var duration: String
    var url: URL?
    var createdAt: Date?
}

// MARK: - Workout

struct WorkoutPlan: Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var exercises: [Exercise]
}

struct Exercise {
    var name: String
    var sets: String
    var rest: String
}

// MARK: - Video Feed

struct VideoFeedItem: Identifiable {
    let id: String
    let title: String
    let fileURL: URL?
    let durationSeconds: Int
    let createdAt: Date?
    let uploaderName: String
    let uploaderId: String
    let traineeId: String?
    let traineeName: String?
    let tags: [String]

    var duration: String {
        guard durationSeconds > 0 else { return "" }
        return String(format: "%02d:%02d", durationSeconds / 60, durationSeconds % 60)
    }

    var dateString: String {
        createdAt?.formatted(.dateTime.month(.abbreviated).day().year()) ?? ""
    }

    var traineeInitials: String? {
        guard let name = traineeName, !name.isEmpty else { return nil }
        let parts = name.components(separatedBy: " ")
        return "\(parts.first?.prefix(1) ?? "")\(parts.dropFirst().first?.prefix(1) ?? "")"
    }

    var traineeColorIndex: Int { traineeId.map { abs($0.hashValue) % 5 } ?? 0 }

    var uploaderInitials: String {
        let parts = uploaderName.components(separatedBy: " ")
        return "\(parts.first?.prefix(1) ?? "")\(parts.dropFirst().first?.prefix(1) ?? "")"
    }

    var uploaderColorIndex: Int { abs(uploaderId.hashValue) % 5 }
}

// MARK: - Chat

struct ChatMessageItem: Identifiable {
    let id: String
    let senderId: String
    let senderName: String
    let text: String
    let createdAt: Date?
    let isFromClient: Bool

    var timeString: String {
        guard let date = createdAt else { return "" }
        let df = DateFormatter()
        df.dateFormat = Calendar.current.isDateInToday(date) ? "h:mma" : "EEE h:mma"
        return df.string(from: date)
    }
}

// MARK: - Trainer

struct Trainer: Identifiable {
    var id: String = UUID().uuidString
    var firstName: String
    var lastName: String
    var email: String
    var role: TrainerRole
    var sessions: Int
    var colorIndex: Int

    var initials: String { "\(firstName.prefix(1))\(lastName.prefix(1))" }
    var fullName: String { "\(firstName) \(lastName)" }
}

enum TrainerRole: String, CaseIterable {
    case trainerManager = "trainer_manager"
    case trainer = "trainer"
    case admin = "admin"

    var displayName: String {
        switch self {
        case .trainerManager: return "Head Trainer"
        case .trainer:        return "Trainer"
        case .admin:          return "Admin"
        }
    }
}
