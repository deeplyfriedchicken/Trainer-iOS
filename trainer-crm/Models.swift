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
