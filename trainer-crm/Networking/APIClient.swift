import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case unauthorized
    case notFound
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized):             return true
        case (.notFound, .notFound):                     return true
        case (.serverError(let a), .serverError(let b)): return a == b
        case (.networkError, .networkError):             return true
        case (.decodingError, .decodingError):           return true
        default:                                         return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:        return "Session expired. Please log in again."
        case .notFound:            return "Resource not found."
        case .serverError(let c):  return "Server error (\(c))."
        case .networkError(let e): return e.localizedDescription
        case .decodingError:       return "Unexpected response from server."
        }
    }
}

extension Notification.Name {
    static let apiUnauthorized = Notification.Name("APIUnauthorized")
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: Config.apiBaseURL)!

    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder = JSONEncoder()

    // MARK: - Primitives

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(method: "GET", path: path)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        try await request(method: "POST", path: path, bodyData: try encoder.encode(body))
    }

    func patch<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        try await request(method: "PATCH", path: path, bodyData: try encoder.encode(body))
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: path)
    }

    // MARK: - Domain methods

    func fetchMe() async throws -> UserResponse {
        let wrapper: DataWrapper<UserResponse> = try await get("/api/auth/me")
        return wrapper.data
    }

    func fetchTrainees(limit: Int = 50, offset: Int = 0) async throws -> [TraineeResponse] {
        let wrapper: PaginatedWrapper<TraineeResponse> = try await get("/api/trainees?limit=\(limit)&offset=\(offset)")
        return wrapper.data
    }

    func createTrainee(name: String, email: String) async throws -> TraineeResponse {
        let wrapper: DataWrapper<TraineeResponse> = try await post("/api/trainees", body: ["name": name, "email": email])
        return wrapper.data
    }

    func updateTrainee(id: String, name: String?, email: String?) async throws -> TraineeResponse {
        var body: [String: String] = [:]
        if let name  { body["name"]  = name  }
        if let email { body["email"] = email }
        let wrapper: DataWrapper<TraineeResponse> = try await patch("/api/trainees/\(id)", body: body)
        return wrapper.data
    }

    func fetchTrainee(id: String) async throws -> TraineeDetailResponse {
        let wrapper: DataWrapper<TraineeDetailResponse> = try await get("/api/trainees/\(id)")
        return wrapper.data
    }

    func deleteTrainee(id: String) async throws {
        try await delete("/api/trainees/\(id)")
    }

    func fetchTrainers(limit: Int = 50, offset: Int = 0) async throws -> [TrainerResponse] {
        let wrapper: PaginatedWrapper<TrainerResponse> = try await get("/api/trainers?limit=\(limit)&offset=\(offset)")
        return wrapper.data
    }

    func createTrainer(name: String, email: String, role: String) async throws -> TrainerResponse {
        let wrapper: DataWrapper<TrainerResponse> = try await post("/api/trainers", body: ["name": name, "email": email, "role": role])
        return wrapper.data
    }

    func updateTrainer(id: String, name: String?, email: String?, role: String?) async throws -> TrainerResponse {
        var body: [String: String] = [:]
        if let name  { body["name"]  = name  }
        if let email { body["email"] = email }
        if let role  { body["role"]  = role  }
        let wrapper: DataWrapper<TrainerResponse> = try await patch("/api/trainers/\(id)", body: body)
        return wrapper.data
    }

    func deleteTrainer(id: String) async throws {
        try await delete("/api/trainers/\(id)")
    }

    func fetchOrCreateChat(traineeId: String, trainerId: String) async throws -> ChatSessionResponse {
        let wrapper: DataWrapper<ChatSessionResponse> = try await post(
            "/api/chats",
            body: ["traineeId": traineeId, "trainerId": trainerId]
        )
        return wrapper.data
    }

    func fetchChatMessages(chatId: String) async throws -> [ChatMessageResponse] {
        let wrapper: DataWrapper<[ChatMessageResponse]> = try await get("/api/chats/\(chatId)/messages")
        return wrapper.data
    }

    func sendChatMessage(chatId: String, text: String) async throws -> ChatMessageResponse {
        let wrapper: DataWrapper<ChatMessageResponse> = try await post(
            "/api/chats/\(chatId)/messages",
            body: ["text": text]
        )
        return wrapper.data
    }

    func createWorkoutPlan(traineeId: String, name: String, exercises: [ExercisePayload] = []) async throws -> WorkoutPlanResponse {
        let wrapper: DataWrapper<WorkoutPlanResponse> = try await post(
            "/api/workout-plans",
            body: WorkoutPlanCreateBody(traineeId: traineeId, name: name, exercises: exercises)
        )
        return wrapper.data
    }

    func updateWorkoutPlan(id: String, name: String, exercises: [ExercisePayload]) async throws -> WorkoutPlanResponse {
        struct UpdateBody: Encodable {
            let name: String
            let exercises: [ExercisePayload]
        }
        let wrapper: DataWrapper<WorkoutPlanResponse> = try await patch(
            "/api/workout-plans/\(id)",
            body: UpdateBody(name: name, exercises: exercises)
        )
        return wrapper.data
    }

    func fetchVideos(limit: Int = 20, offset: Int = 0) async throws -> [VideoListItemResponse] {
        let wrapper: PaginatedWrapper<VideoListItemResponse> = try await get(
            "/api/videos?limit=\(limit)&offset=\(offset)&status=ready"
        )
        return wrapper.data
    }

    func uploadVideo(fileURL: URL, title: String, traineeId: String) async throws -> VideoUploadResult {
        let mimeType = fileURL.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0

        // Step 1: get presigned S3 upload URL from server
        let presign: PresignResponse = try await post(
            "/api/videos/presign",
            body: PresignRequest(fileName: fileURL.lastPathComponent, mimeType: mimeType, fileSizeBytes: fileSize, traineeId: traineeId)
        )

        // Step 2: PUT file directly to S3 — no auth headers, the presigned URL carries auth
        guard let s3URL = URL(string: presign.uploadUrl) else {
            throw APIError.networkError(URLError(.badURL))
        }
        var s3Req = URLRequest(url: s3URL)
        s3Req.httpMethod = "PUT"
        s3Req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        do {
            let (_, s3Response) = try await session.upload(for: s3Req, fromFile: fileURL)
            guard let http = s3Response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw APIError.serverError((s3Response as? HTTPURLResponse)?.statusCode ?? -1)
            }
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }

        // Step 3: confirm upload → triggers MediaConvert (202 in prod, 200 in dev)
        let wrapper: DataWrapper<VideoConfirmResponse> = try await patch(
            "/api/videos/\(presign.videoId)",
            body: ["title": title]
        )
        return VideoUploadResult(videoId: presign.videoId, fileUrl: wrapper.data.fileUrl)
    }

    // MARK: - Private

    private func request<T: Decodable>(method: String, path: String, bodyData: Data? = nil) async throws -> T {
        guard let token = KeychainStore.load() else {
            signOut()
            throw APIError.unauthorized
        }
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.networkError(URLError(.badURL))
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let bodyData {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200...299:
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            signOut()
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            throw APIError.serverError(http.statusCode)
        }
    }

    private func signOut() {
        KeychainStore.delete()
        NotificationCenter.default.post(name: .apiUnauthorized, object: nil)
    }
}

// MARK: - Response types

struct EmptyResponse: Codable, Sendable {}

struct DataWrapper<T: Decodable>: Decodable {
    let data: T
}
extension DataWrapper: Sendable where T: Sendable {}

struct PaginatedWrapper<T: Decodable>: Decodable {
    let data: [T]
    let pagination: PaginationInfo
}
extension PaginatedWrapper: Sendable where T: Sendable {}

struct PaginationInfo: Decodable, Sendable {
    let limit: Int
    let offset: Int
}

struct UserResponse: Decodable, Sendable {
    let id: String
    let email: String
    let name: String
    let roles: [String]
}

struct TraineeResponse: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let email: String
    let planCount: Int?
    let lastPlanAt: Date?
    let createdAt: Date?
}

struct TrainerResponse: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let email: String
    let roles: [String]?
    let videoCount: Int?
    let createdAt: Date?
}

struct WorkoutPlanResponse: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let traineeId: String
    let occurredAt: Date?
    let comment: String?
    let exercises: [ExerciseResponse]?
}

struct ExerciseResponse: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    let sets: Int?
    let reps: Int?
    let durationSeconds: Int?
    let weightLbs: Double?
    let comment: String?
}

struct TraineeDetailResponse: Decodable, Sendable {
    let id: String
    let name: String
    let email: String
    let workouts: [WorkoutSessionResponse]?
    let workoutPlans: [WorkoutPlanDetailResponse]?
    let directVideos: [DirectVideoResponse]?
}

struct WorkoutSessionResponse: Decodable, Identifiable, Sendable {
    let id: String
    let comment: String?
    let workoutPlan: WorkoutPlanNestedResponse?
    let videoLinks: [VideoLinkResponse]?
    let exerciseLinks: [WorkoutExerciseLinkResponse]?
}

struct WorkoutPlanNestedResponse: Decodable, Sendable {
    let id: String
    let name: String
    let occurredAt: Date?
}

struct WorkoutExerciseLinkResponse: Decodable, Sendable {
    let exerciseId: String
    let exercise: WorkoutExerciseNestedResponse?
}

struct WorkoutExerciseNestedResponse: Decodable, Sendable {
    let id: String
    let name: String
    let type: String
    let sets: Int
    let reps: Int?
    let durationSeconds: Int?
    let weightLbs: Double?
}

struct DirectVideoResponse: Decodable, Sendable {
    let id: String
    let title: String?
    let fileUrl: String?
    let durationSeconds: Int?
    let createdAt: Date?
}

struct WorkoutPlanDetailResponse: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let exercises: [ExerciseDetailResponse]?
    let videoLinks: [VideoLinkResponse]?
}

struct ExerciseDetailResponse: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    let sets: Int?
    let reps: Int?
    let durationSeconds: Int?
    let comment: String?
    let videoLinks: [VideoLinkResponse]?
}

struct VideoLinkResponse: Decodable, Sendable {
    let video: LinkedVideoResponse?
}

struct LinkedVideoResponse: Decodable, Sendable {
    let id: String
    let title: String?
    let fileUrl: String?
}

struct ExercisePayload: Encodable, Sendable {
    let name: String
    let type: String
    let sets: Int
    let reps: Int?
    let durationSeconds: Int?
    let comment: String?
    let videoIds: [String]?
}

struct WorkoutPlanCreateBody: Encodable, Sendable {
    let traineeId: String
    let name: String
    let exercises: [ExercisePayload]
}

// MARK: - Video types

struct PresignRequest: Encodable, Sendable {
    let fileName: String
    let mimeType: String
    let fileSizeBytes: Int
    let traineeId: String?
}

struct PresignResponse: Decodable, Sendable {
    let videoId: String
    let uploadUrl: String
}

struct VideoConfirmResponse: Decodable, Sendable {
    let id: String
    let fileUrl: String?
    let title: String?
    let status: String?
}

struct VideoUploadResult: Sendable {
    let videoId: String
    let fileUrl: String?
}

// MARK: - Video feed types

struct VideoListItemResponse: Decodable, Identifiable, Sendable {
    let id: String
    let title: String?
    let fileUrl: String?
    let durationSeconds: Int?
    let createdAt: Date?
    let traineeId: String?
    let uploader: VideoUploaderResponse?
    let videoTags: [VideoTagEntryResponse]?
}

struct VideoUploaderResponse: Decodable, Sendable {
    let id: String
    let name: String
}

struct VideoTagEntryResponse: Decodable, Sendable {
    struct TagInfo: Decodable, Sendable {
        let id: String
        let name: String
    }
    let tag: TagInfo
}

// MARK: - Chat types

struct ChatSessionResponse: Decodable, Sendable {
    let id: String
    let traineeId: String
    let trainerId: String
}

struct ChatMessageResponse: Decodable, Identifiable, Sendable {
    struct Sender: Decodable, Sendable {
        let id: String
        let name: String
    }
    struct Content: Decodable, Sendable {
        let text: String
    }
    let id: String
    let chatId: String
    let senderId: String
    let sender: Sender
    let content: Content
    let createdAt: Date?
}

// MARK: - Data helpers

private extension Data {
    static func += (lhs: inout Data, rhs: String.UTF8View) {
        lhs.append(contentsOf: rhs)
    }
}
