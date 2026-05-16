@preconcurrency import AVFoundation
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
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            let withMs = ISO8601DateFormatter()
            withMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withMs.date(from: s) { return date }
            let withoutMs = ISO8601DateFormatter()
            withoutMs.formatOptions = [.withInternetDateTime]
            if let date = withoutMs.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid ISO 8601 date: \(s)"
            ))
        }
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

    func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        try await request(method: "PUT", path: path, bodyData: try encoder.encode(body))
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

    func fetchOrCreateChat(traineeId: String) async throws -> ChatSessionResponse {
        let wrapper: DataWrapper<ChatSessionResponse> = try await post(
            "/api/chats",
            body: ["traineeId": traineeId]
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

    // MARK: - Push tokens

    func registerPushToken(_ token: String) async {
        struct Body: Encodable { let token: String; let platform: String }
        let _: EmptyResponse? = try? await post(
            "/api/push-tokens",
            body: Body(token: token, platform: "ios")
        )
    }

    func deletePushToken(_ token: String) async {
        struct Body: Encodable { let token: String }
        guard let bodyData = try? encoder.encode(Body(token: token)) else { return }
        let _: EmptyResponse? = try? await request(
            method: "DELETE",
            path: "/api/push-tokens",
            bodyData: bodyData
        )
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

    func fetchWorkoutPlanGroups(traineeId: String) async throws -> [WorkoutPlanGroupResponse] {
        let wrapper: DataWrapper<[WorkoutPlanGroupResponse]> = try await get(
            "/api/workout-plan-groups?traineeId=\(traineeId)"
        )
        return wrapper.data
    }

    func fetchWorkoutPlan(id: String) async throws -> WorkoutPlanDetailResponse {
        let wrapper: DataWrapper<WorkoutPlanDetailResponse> = try await get("/api/workout-plans/\(id)")
        return wrapper.data
    }

    func fetchAvailableWorkoutTags() async throws -> [WorkoutTagResponse] {
        let wrapper: DataWrapper<[WorkoutTagResponse]> = try await get("/api/workout-tags")
        return wrapper.data
    }

    func setWorkoutTags(workoutId: String, tagIds: [String]) async throws {
        struct Body: Encodable { let tagIds: [String] }
        let _: EmptyResponse = try await put("/api/workouts/\(workoutId)/tags", body: Body(tagIds: tagIds))
    }

    func publishWorkoutPlan(groupId: String, planId: String) async throws {
        struct Body: Encodable { let planId: String }
        let _: EmptyResponse = try await put(
            "/api/workout-plan-groups/\(groupId)/current-version",
            body: Body(planId: planId)
        )
    }

    func createDraftPlan(groupId: String, fromPlanId: String) async throws -> WorkoutPlanDetailResponse {
        struct Body: Encodable { let fromPlanId: String }
        let wrapper: DataWrapper<WorkoutPlanDetailResponse> = try await post(
            "/api/workout-plan-groups/\(groupId)/draft",
            body: Body(fromPlanId: fromPlanId)
        )
        return wrapper.data
    }

    func updateSessionQuality(workoutId: String, sessionQuality: Int) async throws {
        struct Body: Encodable { let sessionQuality: Int }
        let _: EmptyResponse = try await patch(
            "/api/workouts/\(workoutId)/session-quality",
            body: Body(sessionQuality: sessionQuality)
        )
    }

    func fetchVideos(limit: Int = 20, offset: Int = 0) async throws -> [VideoListItemResponse] {
        let wrapper: PaginatedWrapper<VideoListItemResponse> = try await get(
            "/api/videos?limit=\(limit)&offset=\(offset)&status=ready"
        )
        return wrapper.data
    }

    func editVideoMetadata(id: String, title: String, description: String?, tagIds: [String]?) async throws {
        struct Body: Encodable {
            let title: String
            let description: String?
            let tagIds: [String]?
        }
        let _: DataWrapper<VideoConfirmResponse> = try await patch(
            "/api/videos/\(id)",
            body: Body(title: title, description: description, tagIds: tagIds)
        )
    }

    func softDeleteVideo(id: String) async throws {
        try await delete("/api/videos/\(id)")
    }

    func fetchPortalLink(traineeId: String) async throws -> PortalLinkResponse {
        let wrapper: DataWrapper<PortalLinkResponse> = try await get("/api/trainees/\(traineeId)/portal-link")
        return wrapper.data
    }

    func uploadVideo(fileURL: URL, title: String, traineeId: String,
                     onProgress: @escaping (Double) -> Void = { _ in }) async throws -> VideoUploadResult {
        // Re-encode to bake in correct orientation before upload so the
        // raw file on S3 has the right physical dimensions regardless of
        // whether the backend transcoder respects rotation metadata.
        let correctedURL = await reencodeVideoWithCorrectOrientation(sourceURL: fileURL)

        let mimeType = correctedURL.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: correctedURL.path)[.size] as? Int) ?? 0

        // Read video metadata from the original file so display dimensions
        // reflect the true orientation, not a re-encoded file that may still
        // carry the source's preferredTransform in its container metadata.
        let metadata = await readVideoMetadata(from: fileURL)

        // Step 1: get presigned S3 upload URL from server
        let presign: PresignResponse = try await post(
            "/api/videos/presign",
            body: PresignRequest(
                fileName: fileURL.lastPathComponent,
                mimeType: mimeType,
                fileSizeBytes: fileSize,
                traineeId: traineeId,
                width: metadata?.width,
                height: metadata?.height,
                duration: metadata?.duration
            )
        )

        // Step 2: PUT file directly to S3 — no auth headers, the presigned URL carries auth
        guard let s3URL = URL(string: presign.uploadUrl) else {
            throw APIError.networkError(URLError(.badURL))
        }
        var s3Req = URLRequest(url: s3URL)
        s3Req.httpMethod = "PUT"
        s3Req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        do {
            let delegate = UploadProgressDelegate(onProgress: onProgress)
            let (_, s3Response) = try await URLSession.shared.upload(for: s3Req, fromFile: correctedURL, delegate: delegate)
            guard let http = s3Response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw APIError.serverError((s3Response as? HTTPURLResponse)?.statusCode ?? -1)
            }
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.networkError(error)
        }

        // Step 3: set title metadata
        let wrapper: DataWrapper<VideoConfirmResponse> = try await patch(
            "/api/videos/\(presign.videoId)",
            body: ["title": title]
        )

        // Step 4: trigger MediaConvert transcode
        let _: DataWrapper<VideoConfirmResponse> = try await post(
            "/api/videos/\(presign.videoId)/process",
            body: [String: String]()
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

struct WorkoutPlanGroupResponse: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let currentVersionId: String?
    let currentVersion: WorkoutPlanVersionSummaryResponse?
    let latestDraftId: String?
    let latestDraft: WorkoutPlanVersionSummaryResponse?
}

struct WorkoutPlanVersionSummaryResponse: Decodable, Sendable {
    let id: String
    let name: String
    let versionNumber: Int?
    let versionStatus: String?
    let occurredAt: Date?
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
    let isHidden: Bool?
}

struct WorkoutTagResponse: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct WorkoutTagEntryWorkoutResponse: Decodable, Sendable {
    let tag: WorkoutTagResponse
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
    let workoutTags: [WorkoutTagEntryWorkoutResponse]?
    let durationSeconds: Int?
    let preSessionEnergy: Int?
    let preSessionSoreness: Int?
    let preSessionStress: Int?
    let postSessionEnergy: Int?
    let sessionQuality: Int?
    let traineeRating: Int?
    let totalVolumeLbs: Double?
    let adherencePercent: Double?
}

struct WorkoutPlanNestedResponse: Decodable, Sendable {
    let id: String
    let name: String
    let occurredAt: Date?
}

struct ExerciseSetLogResponse: Decodable, Sendable {
    let reps: Int?
    let durationSeconds: Int?
    let weightLbs: Double?
    let completed: Bool?
}

struct WorkoutExerciseLinkResponse: Decodable, Sendable {
    let exerciseId: String
    let exercise: WorkoutExerciseNestedResponse?
    let setsData: [ExerciseSetLogResponse]?
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
    let status: String?
}

struct WorkoutPlanDetailResponse: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let versionStatus: String?
    let versionNumber: Int?
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
    let isHidden: Bool?
    let videoLinks: [VideoLinkResponse]?
}

struct VideoLinkResponse: Decodable, Sendable {
    let video: LinkedVideoResponse?
}

struct LinkedVideoResponse: Decodable, Sendable {
    let id: String
    let title: String?
    let fileUrl: String?
    let status: String?
}

struct ExercisePayload: Encodable, Sendable {
    let id: String?
    let name: String
    let type: String
    let sets: Int
    let reps: Int?
    let durationSeconds: Int?
    let comment: String?
    let videoIds: [String]?
    let isHidden: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, type, sets, reps, durationSeconds, comment, videoIds, isHidden
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let id { try container.encode(id, forKey: .id) }
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(sets, forKey: .sets)
        try container.encodeIfPresent(reps, forKey: .reps)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(videoIds, forKey: .videoIds)
        try container.encode(isHidden, forKey: .isHidden)
    }
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
    let width: Int?
    let height: Int?
    let duration: Double?
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

fileprivate struct VideoMetadata {
    let width: Int
    let height: Int
    let duration: Double
}

fileprivate func readVideoMetadata(from url: URL) async -> VideoMetadata? {
    let asset = AVURLAsset(url: url)
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
    guard let naturalSize = try? await videoTrack.load(.naturalSize) else { return nil }
    guard let preferredTransform = try? await videoTrack.load(.preferredTransform) else { return nil }
    let duration: Double
    do {
        let cmTime = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(cmTime)
        duration = seconds.isFinite ? seconds : 0
    } catch {
        duration = 0
    }
    let displaySize = naturalSize.applying(preferredTransform)
    let width = Int(abs(displaySize.width))
    let height = Int(abs(displaySize.height))
    return VideoMetadata(width: width, height: height, duration: duration)
}

/// Re-encodes the video so its pixel data matches its display orientation and
/// the output container carries an identity preferredTransform (no rotation hint).
/// Uses AVAssetReader + AVAssetWriter directly so the output track transform can
/// be set to identity — AVAssetExportSession always copies the source track's
/// preferredTransform, which causes players to double-rotate the content.
private func reencodeVideoWithCorrectOrientation(sourceURL: URL) async -> URL {
    let asset = AVURLAsset(url: sourceURL)
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
        return sourceURL
    }

    let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
    let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
    let displaySize = naturalSize.applying(preferredTransform)
    let renderWidth = Int(abs(displaySize.width))
    let renderHeight = Int(abs(displaySize.height))

    if renderWidth == Int(abs(naturalSize.width)),
       renderHeight == Int(abs(naturalSize.height)) {
        return sourceURL
    }

    guard let assetDuration = try? await asset.load(.duration) else { return sourceURL }

    // Rotation alone may place content in negative coordinates; shift it back.
    // Order matters: rotate first, then translate.
    let w = naturalSize.width
    let h = naturalSize.height
    let corners = [
        CGPoint.zero.applying(preferredTransform),
        CGPoint(x: w, y: 0).applying(preferredTransform),
        CGPoint(x: 0, y: h).applying(preferredTransform),
        CGPoint(x: w, y: h).applying(preferredTransform),
    ]
    let shiftX = corners.map(\.x).min() ?? 0
    let shiftY = corners.map(\.y).min() ?? 0
    let correction = CGAffineTransform(translationX: -shiftX, y: -shiftY)
    let correctedTransform = preferredTransform.concatenating(correction)

    let videoComposition: AVVideoComposition
    if #available(iOS 26, macOS 26, *) {
        var layerConfig = AVVideoCompositionLayerInstruction.Configuration()
        layerConfig.trackID = videoTrack.trackID
        layerConfig.setTransform(correctedTransform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

        var instrConfig = AVVideoCompositionInstruction.Configuration()
        instrConfig.timeRange = CMTimeRange(start: .zero, duration: assetDuration)
        instrConfig.layerInstructions = [layerInstruction]
        let instruction = AVVideoCompositionInstruction(configuration: instrConfig)

        var compConfig = AVVideoComposition.Configuration()
        compConfig.renderSize = CGSize(width: renderWidth, height: renderHeight)
        compConfig.frameDuration = CMTime(value: 1, timescale: 30)
        compConfig.instructions = [instruction]
        videoComposition = AVVideoComposition(configuration: compConfig)
    } else {
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(correctedTransform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)
        instruction.layerInstructions = [layerInstruction]

        let mutableComposition = AVMutableVideoComposition()
        mutableComposition.renderSize = CGSize(width: renderWidth, height: renderHeight)
        mutableComposition.frameDuration = CMTime(value: 1, timescale: 30)
        mutableComposition.instructions = [instruction]
        videoComposition = mutableComposition
    }

    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")

    guard let reader = try? AVAssetReader(asset: asset),
          let writer = try? AVAssetWriter(url: outputURL, fileType: .mp4) else {
        return sourceURL
    }

    // Decode through the composition (applies rotation + translation).
    let videoReaderOutput = AVAssetReaderVideoCompositionOutput(
        videoTracks: [videoTrack],
        videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    videoReaderOutput.videoComposition = videoComposition
    guard reader.canAdd(videoReaderOutput) else { return sourceURL }
    reader.add(videoReaderOutput)

    // Re-encode with identity transform so no rotation hint survives in the container.
    let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: renderWidth,
        AVVideoHeightKey: renderHeight,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000],
    ])
    videoWriterInput.transform = .identity
    videoWriterInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(videoWriterInput) else { return sourceURL }
    writer.add(videoWriterInput)

    // Audio: pass-through with no re-encode.
    var audioReaderOutput: AVAssetReaderTrackOutput? = nil
    var audioWriterInput: AVAssetWriterInput? = nil
    if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
        let aOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        if reader.canAdd(aOut) {
            reader.add(aOut)
            audioReaderOutput = aOut
            let fmts = try? await audioTrack.load(.formatDescriptions)
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil,
                                         sourceFormatHint: fmts?.first)
            aIn.expectsMediaDataInRealTime = false
            if writer.canAdd(aIn) {
                writer.add(aIn)
                audioWriterInput = aIn
            }
        }
    }

    reader.startReading()
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    // AVFoundation types predate Sendable; box them so the @Sendable closures
    // passed to requestMediaDataWhenReady only capture the wrapper (which IS
    // Sendable) rather than the raw AVFoundation objects directly.
    struct Box<T>: @unchecked Sendable { let v: T }
    let vIn  = Box(v: videoWriterInput)
    let vOut = Box(v: videoReaderOutput)

    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        // Single serial queue keeps `pending` access race-free across both tracks.
        let q = DispatchQueue(label: "video.reencode", qos: .userInitiated)
        var pending = 1 + (audioWriterInput != nil ? 1 : 0)

        func trackFinished() {
            pending -= 1
            if pending == 0 { writer.finishWriting { cont.resume() } }
        }

        vIn.v.requestMediaDataWhenReady(on: q) {
            while vIn.v.isReadyForMoreMediaData {
                if let buf = vOut.v.copyNextSampleBuffer() {
                    vIn.v.append(buf)
                } else {
                    vIn.v.markAsFinished()
                    trackFinished()
                    return
                }
            }
        }

        if let aIn = audioWriterInput, let aOut = audioReaderOutput {
            let bIn  = Box(v: aIn)
            let bOut = Box(v: aOut)
            bIn.v.requestMediaDataWhenReady(on: q) {
                while bIn.v.isReadyForMoreMediaData {
                    if let buf = bOut.v.copyNextSampleBuffer() {
                        bIn.v.append(buf)
                    } else {
                        bIn.v.markAsFinished()
                        trackFinished()
                        return
                    }
                }
            }
        }
    }

    guard writer.status == .completed else {
        try? FileManager.default.removeItem(at: outputURL)
        return sourceURL
    }
    return outputURL
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

// MARK: - Video feed types

struct VideoListItemResponse: Decodable, Identifiable, Sendable {
    let id: String
    let title: String?
    let description: String?
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

struct PortalLinkResponse: Decodable, Sendable {
    let url: String
    let expiresAt: Date
}

// MARK: - Chat types

struct ChatSessionResponse: Decodable, Sendable {
    let id: String
    let traineeId: String
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
