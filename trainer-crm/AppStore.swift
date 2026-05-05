import Foundation
import Observation
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
        } catch APIError.unauthorized {
            signOut()
        } catch {
            isAuthenticated = true
        }
    }

    func signOut() {
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

    func loadClientDetail(_ clientId: String) async {
        guard let detail = try? await api.fetchTrainee(id: clientId) else { return }
        guard let idx = clients.firstIndex(where: { $0.id == clientId }) else { return }

        clients[idx].workouts = (detail.workoutPlans ?? []).map { plan in
            WorkoutPlan(
                id: plan.id,
                name: plan.name,
                exercises: (plan.exercises ?? []).map { ex in
                    let setsStr = ex.type == "duration"
                        ? "\(ex.sets ?? 1)×\(ex.durationSeconds ?? 0)s"
                        : "\(ex.sets ?? 1)×\(ex.reps ?? 0)"
                    return Exercise(name: ex.name, sets: setsStr, rest: "—")
                }
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
                               url: v.fileUrl.flatMap(URL.init), createdAt: v.createdAt)
        }

        let linkedVideos: [ClientVideo] = (detail.workoutPlans ?? []).flatMap { plan in
            (plan.exercises ?? []).flatMap { ex in
                (ex.videoLinks ?? []).compactMap { link -> ClientVideo? in
                    guard let v = link.video else { return nil }
                    return ClientVideo(id: v.id, title: v.title ?? plan.name,
                                       date: "", duration: "",
                                       url: v.fileUrl.flatMap(URL.init))
                }
            }
        }

        let serverIds = Set(directVideos.map(\.id)).union(linkedVideos.map(\.id))
        let localOnly = clients[idx].videos.filter { !serverIds.contains($0.id) }
        // Direct uploads first (newest), then exercise-linked, then in-progress local
        clients[idx].videos = directVideos + linkedVideos + localOnly
    }

    func addVideo(clientId: String, video: ClientVideo) async throws {
        guard let fileURL = video.url else { return }
        let uploaded = try await api.uploadVideo(
            fileURL: fileURL,
            title: video.title,
            traineeId: clientId
        )
        guard let cidx = clients.firstIndex(where: { $0.id == clientId }),
              let vidx = clients[cidx].videos.firstIndex(where: { $0.id == video.id })
        else { return }
        clients[cidx].videos[vidx].url = uploaded.fileUrl.flatMap(URL.init)
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
        } catch {
            self.error = (error as? APIError) ?? .networkError(error)
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
            workouts: []
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
            tags: r.videoTags?.map(\.tag.name) ?? []
        )
    }
}
