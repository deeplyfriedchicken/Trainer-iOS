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
    var workouts: [Workout]
    var workoutPlans: [WorkoutPlan]

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
    var isProcessing: Bool = false
}

// MARK: - Workout

struct WorkoutPlan: Identifiable {
    var id: String = UUID().uuidString
    var groupId: String? = nil
    var name: String
    var versionStatus: String = "published"   // "draft" | "published"
    var versionNumber: Int = 1
    var exercises: [Exercise]

    var isDraft: Bool { versionStatus == "draft" }
    var isPublished: Bool { versionStatus == "published" }
}

struct WorkoutTag: Identifiable {
    var id: String
    var name: String
}

struct Workout: Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var occurredAt: Date?
    var comment: String?
    var exercises: [Exercise]
    var tags: [WorkoutTag] = []
    var durationSeconds: Int? = nil
    var preSessionEnergy: Int? = nil
    var preSessionSoreness: Int? = nil
    var preSessionStress: Int? = nil
    var postSessionEnergy: Int? = nil
    var sessionQuality: Int? = nil
    var traineeRating: Int? = nil
    var totalVolumeLbs: Double? = nil
    var adherencePercent: Double? = nil
}

enum ExerciseType: String, CaseIterable {
    case reps, duration
    var displayName: String {
        switch self {
        case .reps:     return "Reps"
        case .duration: return "Duration"
        }
    }
}

struct Exercise: Identifiable {
    var id: String = UUID().uuidString
    var serverId: String? = nil
    var name: String
    var exerciseType: ExerciseType = .reps
    var sets: Int = 3
    var reps: Int? = 10
    var durationSeconds: Int? = nil
    var comment: String = ""
    var videoIds: [String] = []
    var setsData: [ExerciseSetLog] = []
    var isHidden: Bool = false

    var displaySets: String {
        switch exerciseType {
        case .reps:     return "\(sets)×\(reps ?? 0) reps"
        case .duration: return "\(sets)×\(durationSeconds ?? 0)s"
        }
    }
}

struct ExerciseSetLog {
    var reps: Int?
    var durationSeconds: Int?
    var weightLbs: Double?
    var completed: Bool
}

// MARK: - Video Feed

struct VideoFeedItem: Identifiable {
    let id: String
    var title: String
    let fileURL: URL?
    let durationSeconds: Int
    let createdAt: Date?
    let uploaderName: String
    let uploaderId: String
    let traineeId: String?
    let traineeName: String?
    let tags: [String]
    let tagIds: [String]
    var description: String?

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

extension VideoFeedItem {
    init(from video: ClientVideo, clientId: String, clientName: String,
         uploaderName: String, uploaderId: String) {
        let parts = video.duration.split(separator: ":").compactMap { Int($0) }
        let seconds = parts.count >= 2 ? parts[0] * 60 + parts[1] : 0
        self.init(
            id: video.id,
            title: video.title,
            fileURL: video.url,
            durationSeconds: seconds,
            createdAt: video.createdAt,
            uploaderName: uploaderName,
            uploaderId: uploaderId,
            traineeId: clientId,
            traineeName: clientName,
            tags: [],
            tagIds: [],
            description: nil
        )
    }
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
