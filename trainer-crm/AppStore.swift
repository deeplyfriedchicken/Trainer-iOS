import FirebaseMessaging
import Foundation
import Observation
import UIKit
import WebKit

@Observable
@MainActor
class AppStore {
    // MARK: - State

    var clients: [Client] = []
    var trainers: [Trainer] = []
    var currentUser: UserResponse? = nil
    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var error: APIError? = nil
    var refreshMessage: String? = nil

    var uploadTasks: [UploadTask] = []
    var isShowingRecording = false

    var feedVideos: [VideoFeedItem] = []
    var isFeedLoading: Bool = false
    var feedHasMore: Bool = true
    private let feedPageSize = 20

    private let api = APIClient.shared

    // MARK: - Auth

    func checkAuth() async {
        guard KeychainStore.load() != nil else {
            isAuthenticated = false
            return
        }
        do {
            let me = try await api.fetchMe()
            currentUser = me
            isAuthenticated = true
            await loadInitialData()
            await registerFCMToken()
        } catch APIError.unauthorized {
            signOut()
        } catch {
            isAuthenticated = true
        }
    }

    func registerFCMToken() async {
        await withCheckedContinuation { continuation in
            Messaging.messaging().token { token, _ in
                if let token {
                    Task { await self.api.registerPushToken(token) }
                }
                continuation.resume()
            }
        }
    }

    func signOut() {
        if let fcmToken = Messaging.messaging().fcmToken {
            Task { await api.deletePushToken(fcmToken) }
        }
        KeychainStore.delete()
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { }
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        clients = []
        trainers = []
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Data loading

    func loadInitialData() async {
        isLoading = true
        defer { isLoading = false }
        async let fetchedTrainers = try? api.fetchTrainers()
        async let fetchedClients  = try? api.fetchTrainees()
        let (t, c) = await (fetchedTrainers, fetchedClients)
        trainers = (t ?? []).map(Trainer.init)
        clients  = (c ?? []).map(Client.init)
        isAuthenticated = true
    }

    func refreshData() async {
        async let fetchedTrainers = try? api.fetchTrainers()
        async let fetchedClients  = try? api.fetchTrainees()
        let (t, c) = await (fetchedTrainers, fetchedClients)
        if let t { trainers = t.map(Trainer.init) }
        if let c { clients  = c.map(Client.init) }
        refreshMessage = "Data refreshed"
    }

    // MARK: - Client CRUD

    func addClient(_ client: Client) {
        clients.append(client)
        Task {
            do {
                let created = try await api.createTrainee(
                    name: client.fullName,
                    email: client.email
                )
                if let idx = clients.firstIndex(where: { $0.id == client.id }) {
                    clients[idx].id = created.id
                }
            } catch {
                self.error = (error as? APIError) ?? .networkError(error)
            }
        }
    }

    func updateClient(_ updated: Client) {
        if let idx = clients.firstIndex(where: { $0.id == updated.id }) {
            clients[idx] = updated
        }
        Task {
            do {
                _ = try await api.updateTrainee(id: updated.id, name: updated.fullName, email: updated.email)
            } catch {
                self.error = (error as? APIError) ?? .networkError(error)
            }
        }
    }

    func loadClientDetail(_ clientId: String, showRefreshToast: Bool = false) async {
        let detail: TraineeDetailResponse
        do {
            detail = try await api.fetchTrainee(id: clientId)
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
            return
        }
        guard let idx = clients.firstIndex(where: { $0.id == clientId }) else { return }

        // Plans — sourced from the trainee detail which includes exercises + videos inline.
        // The detail returns non-archived plans (draft + published), so both states show up.
        clients[idx].workoutPlans = (detail.workoutPlans ?? []).map { plan in
            let exs = (plan.exercises ?? []).map { mapExerciseDetail($0) }
            return WorkoutPlan(
                id: plan.id,
                groupId: plan.workoutPlanGroupId,
                name: plan.name,
                versionStatus: plan.versionStatus ?? "draft",
                versionNumber: plan.versionNumber ?? 1,
                exercises: exs
            )
        }

        // Workouts — sets_data JSONB is gone; sets are now in workout.sets keyed by exerciseId.
        clients[idx].workouts = (detail.workouts ?? []).map { w in
            let setsByExercise: [String: [WorkoutSetResponse]] = Dictionary(
                grouping: w.sets ?? [],
                by: \.exerciseId
            )
            return Workout(
                id: w.id,
                name: w.workoutPlan?.name ?? "Workout",
                occurredAt: w.workoutPlan?.occurredAt,
                comment: w.comment,
                exercises: (w.exerciseLinks ?? []).map { link in
                    let ex = link.exercise
                    let sets = (setsByExercise[ex?.id ?? link.exerciseId] ?? [])
                        .sorted { $0.position < $1.position }
                    return Exercise(
                        id: ex?.id ?? link.exerciseId,
                        name: ex?.name ?? "Exercise",
                        exerciseType: ex?.type == "duration" ? .duration : .reps,
                        sets: ex?.sets ?? 1,
                        reps: ex?.reps,
                        durationSeconds: ex?.durationSeconds,
                        comment: "",
                        videoIds: [],
                        setsData: sets.map {
                            ExerciseSetLog(reps: $0.reps, durationSeconds: $0.durationSeconds,
                                           weightLbs: $0.weightLbs, completed: $0.completed)
                        }
                    )
                },
                tags: (w.workoutTags ?? []).map { WorkoutTag(id: $0.tag.id, name: $0.tag.name) },
                durationSeconds: w.durationSeconds,
                preSessionEnergy: w.preSessionEnergy,
                preSessionSoreness: w.preSessionSoreness,
                preSessionStress: w.preSessionStress,
                postSessionEnergy: w.postSessionEnergy,
                sessionQuality: w.sessionQuality,
                traineeRating: w.traineeRating,
                totalVolumeLbs: w.totalVolumeLbs,
                adherencePercent: w.adherencePercent
            )
        }

        let directVideos: [ClientVideo] = (detail.directVideos ?? []).map { v in
            let dateStr = v.createdAt.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? ""
            let durStr: String = {
                guard let s = v.durationSeconds, s > 0 else { return "" }
                return String(format: "%02d:%02d", s / 60, s % 60)
            }()
            return ClientVideo(id: v.id, title: v.title ?? "Recording",
                               date: dateStr, duration: durStr,
                               url: v.fileUrl.flatMap(URL.init), createdAt: v.createdAt,
                               isProcessing: v.status.map { $0 != "ready" } ?? false)
        }

        let planLinkedVideos: [ClientVideo] = (detail.workoutPlans ?? []).flatMap { plan in
            let planVideos = (plan.videoLinks ?? []).compactMap { link -> ClientVideo? in
                guard let v = link.video else { return nil }
                return ClientVideo(id: v.id, title: v.title ?? plan.name,
                                   date: "", duration: "",
                                   url: v.fileUrl.flatMap(URL.init),
                                   isProcessing: v.status.map { $0 != "ready" } ?? false)
            }
            let exerciseVideos = (plan.exercises ?? []).flatMap { ex in
                (ex.videoLinks ?? []).compactMap { link -> ClientVideo? in
                    guard let v = link.video else { return nil }
                    return ClientVideo(id: v.id, title: v.title ?? plan.name,
                                       date: "", duration: "",
                                       url: v.fileUrl.flatMap(URL.init),
                                       isProcessing: v.status.map { $0 != "ready" } ?? false)
                }
            }
            return planVideos + exerciseVideos
        }

        let workoutLinkedVideos: [ClientVideo] = (detail.workouts ?? []).flatMap { w in
            (w.videoLinks ?? []).compactMap { link -> ClientVideo? in
                guard let v = link.video else { return nil }
                return ClientVideo(id: v.id, title: v.title ?? w.workoutPlan?.name ?? "Workout",
                                   date: "", duration: "",
                                   url: v.fileUrl.flatMap(URL.init),
                                   isProcessing: v.status.map { $0 != "ready" } ?? false)
            }
        }

        let serverIds = Set(directVideos.map(\.id))
            .union(planLinkedVideos.map(\.id))
            .union(workoutLinkedVideos.map(\.id))
        let localOnly = clients[idx].videos.filter { !serverIds.contains($0.id) }
        let combined = directVideos + planLinkedVideos + workoutLinkedVideos + localOnly
        var seen = Set<String>()
        clients[idx].videos = combined.filter { seen.insert($0.id).inserted }
        if showRefreshToast { refreshMessage = "Client data refreshed" }
    }

    @discardableResult
    func addVideo(clientId: String, video: ClientVideo,
                  onProgress: @escaping (Double) -> Void = { _ in }) async throws -> String {
        guard let fileURL = video.url else { return video.id }
        let uploaded = try await api.uploadVideo(
            fileURL: fileURL,
            title: video.title,
            traineeId: clientId,
            onProgress: onProgress
        )
        // Cache thumbnail from the local file now — remote fetch is slow and unreliable.
        if let img = await generateThumbnail(from: fileURL, size: CGSize(width: 480, height: 270)) {
            ThumbnailCache.shared.set(img, for: uploaded.videoId)
        }
        guard let cidx = clients.firstIndex(where: { $0.id == clientId }),
              let vidx = clients[cidx].videos.firstIndex(where: { $0.id == video.id })
        else { return uploaded.videoId }
        clients[cidx].videos[vidx].id = uploaded.videoId
        clients[cidx].videos[vidx].url = uploaded.fileUrl.flatMap(URL.init)
        return uploaded.videoId
    }

    func updateFeedVideo(id: String, title: String, description: String?, tagIds: [String]) async -> Bool {
        if let idx = feedVideos.firstIndex(where: { $0.id == id }) {
            feedVideos[idx].title = title
            feedVideos[idx].description = description
        }
        do {
            try await api.editVideoMetadata(
                id: id,
                title: title,
                description: description,
                tagIds: tagIds.isEmpty ? nil : tagIds
            )
            return true
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
            return false
        }
    }

    func deleteVideo(id: String, clientId: String? = nil) async {
        feedVideos.removeAll { $0.id == id }
        if let clientId, let cidx = clients.firstIndex(where: { $0.id == clientId }) {
            clients[cidx].videos.removeAll { $0.id == id }
        }
        do {
            try await api.softDeleteVideo(id: id)
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
        }
    }

    func createWorkoutPlan(clientId: String, name: String) async {
        do {
            let plan = try await api.createWorkoutPlan(traineeId: clientId, name: name)
            guard let idx = clients.firstIndex(where: { $0.id == clientId }) else { return }
            clients[idx].workoutPlans.append(WorkoutPlan(id: plan.id, name: plan.name, exercises: []))
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
        }
    }

    /// PATCHes a workout plan. The backend handles forking automatically:
    /// - draft → updates in place, returns same ID
    /// - published → forks a new draft, returns new ID with versionStatus "draft"
    /// Returns the groupId when a fork occurred so the UI can switch to draft view.
    @discardableResult
    func updateWorkoutPlan(planId: String, clientId: String, name: String, exercises: [Exercise]) async -> String? {
        let payload = exercises.map { ex in
            ExercisePayload(
                id: ex.serverId,
                name: ex.name,
                type: ex.exerciseType.rawValue,
                sets: ex.sets,
                reps: ex.exerciseType == .reps ? ex.reps : nil,
                durationSeconds: ex.exerciseType == .duration ? ex.durationSeconds : nil,
                weightLbs: ex.weightLbs,
                comment: ex.comment.isEmpty ? nil : ex.comment,
                videoIds: ex.videoIds.isEmpty ? nil : ex.videoIds,
                isHidden: ex.isHidden
            )
        }
        do {
            let updated = try await api.updateWorkoutPlan(id: planId, name: name, exercises: payload)
            let forked = updated.id != planId
            if forked {
                // Backend forked a new draft from a published plan; reload to reflect server state.
                await loadClientDetail(clientId)
                return updated.workoutPlanGroupId
            }
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
        }
        return nil
    }

    func publishWorkoutPlan(groupId: String, plan: WorkoutPlan, clientId: String) async {
        let payload = plan.exercises.map { ex in
            ExercisePayload(
                id: ex.serverId,
                name: ex.name,
                type: ex.exerciseType.rawValue,
                sets: ex.sets,
                reps: ex.exerciseType == .reps ? ex.reps : nil,
                durationSeconds: ex.exerciseType == .duration ? ex.durationSeconds : nil,
                weightLbs: ex.weightLbs,
                comment: ex.comment.isEmpty ? nil : ex.comment,
                videoIds: ex.videoIds.isEmpty ? nil : ex.videoIds,
                isHidden: ex.isHidden
            )
        }
        do {
            _ = try await api.publishWorkoutPlan(groupId: groupId, name: plan.name, exercises: payload)
            await loadClientDetail(clientId)
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
        }
    }

    func createDraftPlan(groupId: String, traineeId: String, name: String, clientId: String) async {
        do {
            let plan = try await api.createDraftInGroup(groupId: groupId, traineeId: traineeId, name: name, exercises: [])
            guard let cidx = clients.firstIndex(where: { $0.id == clientId }) else { return }
            clients[cidx].workoutPlans.append(WorkoutPlan(
                id: plan.id, groupId: groupId, name: plan.name,
                versionStatus: "draft", versionNumber: 1, exercises: []
            ))
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
        }
    }

    func updateSessionQuality(clientId: String, workoutId: String, sessionQuality: Int) {
        guard let cidx = clients.firstIndex(where: { $0.id == clientId }),
              let widx = clients[cidx].workouts.firstIndex(where: { $0.id == workoutId })
        else { return }
        clients[cidx].workouts[widx].sessionQuality = sessionQuality
    }

    func setWorkoutTags(clientId: String, workoutId: String, tags: [WorkoutTag]) async {
        do {
            try await api.setWorkoutTags(workoutId: workoutId, tagIds: tags.map(\.id))
            guard let cidx = clients.firstIndex(where: { $0.id == clientId }),
                  let widx = clients[cidx].workouts.firstIndex(where: { $0.id == workoutId })
            else { return }
            clients[cidx].workouts[widx].tags = tags
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
        }
    }

    func deleteClient(id: String) {
        clients.removeAll { $0.id == id }
        Task {
            do {
                try await api.deleteTrainee(id: id)
            } catch {
                self.error = (error as? APIError) ?? .networkError(error)
            }
        }
    }

    // MARK: - Trainer CRUD

    func addTrainer(_ trainer: Trainer) {
        trainers.append(trainer)
        Task {
            do {
                let created = try await api.createTrainer(
                    name: trainer.fullName,
                    email: trainer.email,
                    role: trainer.role.rawValue
                )
                if let idx = trainers.firstIndex(where: { $0.id == trainer.id }) {
                    trainers[idx].id = created.id
                }
            } catch {
                self.error = (error as? APIError) ?? .networkError(error)
            }
        }
    }

    func updateTrainer(_ updated: Trainer) {
        if let idx = trainers.firstIndex(where: { $0.id == updated.id }) {
            trainers[idx] = updated
        }
        Task {
            do {
                let response = try await api.updateTrainer(
                    id: updated.id,
                    name: updated.fullName,
                    email: updated.email,
                    role: updated.role.rawValue
                )
                if let idx = trainers.firstIndex(where: { $0.id == updated.id }) {
                    trainers[idx] = Trainer(response)
                }
            } catch {
                self.error = (error as? APIError) ?? .networkError(error)
            }
        }
    }

    func deleteTrainer(id: String) {
        trainers.removeAll { $0.id == id }
        Task {
            do {
                try await api.deleteTrainer(id: id)
            } catch {
                self.error = (error as? APIError) ?? .networkError(error)
            }
        }
    }

    func clientCount(for trainerId: String) -> Int {
        clients.filter { $0.trainerId == trainerId }.count
    }

    // MARK: - Video Feed

    func loadFeedVideos() async {
        guard !isFeedLoading else { return }
        isFeedLoading = true
        defer { isFeedLoading = false }
        do {
            let items = try await api.fetchVideos(limit: feedPageSize, offset: 0)
            feedVideos = items.map { VideoFeedItem($0, clients: clients) }
            feedHasMore = items.count == feedPageSize
        } catch is CancellationError {
        } catch let apiError as APIError {
            if case .networkError(let e) = apiError, (e as? URLError)?.code == .cancelled { return }
            self.error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }

    func loadMoreFeedVideos() async {
        guard !isFeedLoading && feedHasMore else { return }
        isFeedLoading = true
        defer { isFeedLoading = false }
        do {
            let items = try await api.fetchVideos(limit: feedPageSize, offset: feedVideos.count)
            feedVideos.append(contentsOf: items.map { VideoFeedItem($0, clients: clients) })
            feedHasMore = items.count == feedPageSize
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
        }
    }
}

// MARK: - API → Model conversions

private func mapExerciseDetail(_ ex: ExerciseDetailResponse) -> Exercise {
    Exercise(
        id: ex.id,
        serverId: ex.id,
        name: ex.name,
        exerciseType: ex.type == "duration" ? .duration : .reps,
        sets: ex.sets ?? 1,
        reps: ex.reps,
        durationSeconds: ex.durationSeconds,
        weightLbs: ex.weightLbs,
        comment: ex.comment ?? "",
        videoIds: (ex.videoLinks ?? []).compactMap { $0.video?.id },
        isHidden: ex.isHidden ?? false
    )
}

extension Client {
    init(_ r: TraineeResponse) {
        let parts = r.name.components(separatedBy: " ")
        self.init(
            id: r.id,
            firstName: parts.first ?? r.name,
            lastName: parts.dropFirst().joined(separator: " "),
            email: r.email,
            plan: "Training",
            sessions: r.planCount ?? 0,
            lastSeen: r.lastPlanAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never",
            status: .active,
            trainerId: nil,
            colorIndex: abs(r.id.hashValue) % 5,
            videos: [],
            workouts: [],
            workoutPlans: []
        )
    }
}

extension Trainer {
    init(_ r: TrainerResponse) {
        let parts = r.name.components(separatedBy: " ")
        let role: TrainerRole = {
            guard let roles = r.roles else { return .trainer }
            if roles.contains("admin")           { return .admin }
            if roles.contains("trainer_manager") { return .trainerManager }
            return .trainer
        }()
        self.init(
            id: r.id,
            firstName: parts.first ?? r.name,
            lastName: parts.dropFirst().joined(separator: " "),
            email: r.email,
            role: role,
            sessions: r.videoCount ?? 0,
            colorIndex: abs(r.id.hashValue) % 5
        )
    }
}

extension VideoFeedItem {
    init(_ r: VideoListItemResponse, clients: [Client]) {
        let client = clients.first(where: { $0.id == r.traineeId })
        self.init(
            id: r.id,
            title: r.title ?? "Recording",
            fileURL: r.fileUrl.flatMap(URL.init),
            durationSeconds: r.durationSeconds ?? 0,
            createdAt: r.createdAt,
            uploaderName: r.uploader?.name ?? "Unknown",
            uploaderId: r.uploader?.id ?? "",
            traineeId: r.traineeId,
            traineeName: client?.fullName,
            tags: r.videoTags?.map(\.tag.name) ?? [],
            tagIds: r.videoTags?.map(\.tag.id) ?? [],
            description: r.description
        )
    }
}
