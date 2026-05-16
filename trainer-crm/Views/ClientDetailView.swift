import SwiftUI
import AVKit
import PhotosUI

struct ClientDetailView: View {
    @Environment(AppStore.self) private var store
    @Binding var client: Client
    let onBack: () -> Void

    @State private var activeTab: DetailTab = .overview
    @State private var showRecording = false
    @State private var showAddWorkout = false
    @State private var showEditExercise = false
    @State private var targetWorkoutId: String? = nil
    @State private var draftViewGroups: Set<String> = []   // groupIds showing draft view
    @State private var planToPublish: WorkoutPlan? = nil
    @State private var expandedSecondaryPlanId: String? = nil
    @State private var editingExercise: Exercise? = nil
    @State private var editExName = ""
    @State private var editExType: ExerciseType = .reps
    @State private var editExSets = "3"
    @State private var editExReps = "10"
    @State private var editExDuration = "30"
    @State private var editExNotes = ""
    @State private var editExVideoIds: Set<String> = []
    @State private var editExIsHidden = false
    @State private var newWorkoutName = ""
    @State private var playerItem: AVPlayerItem? = nil
    @State private var playingVideo: ClientVideo? = nil
    @State private var galleryVideos: [ClientVideo] = []
    @State private var showVideoGallery = false
    @State private var exerciseRecordTarget: (workoutId: String, exerciseId: String)? = nil
    @State private var chatId: String? = nil
    @State private var chatMessages: [ChatMessageItem] = []
    @State private var isChatLoading = false
    @State private var isChatRefreshing = false
    @State private var showChatRefreshToast = false
    @State private var messageText = ""
    @FocusState private var isChatFocused: Bool
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedExercisePhotoItem: PhotosPickerItem? = nil
    @State private var isUploadingExerciseVideo = false
    @State private var uploadingVideoLocalId: String? = nil
    @State private var pendingVideoFile: VideoFile? = nil
    @State private var pendingVideoIsExercise = false
    @State private var videoLoadTask: Task<VideoFile?, Never>? = nil
    @State private var isAwaitingFile = false
    @State private var exerciseUploadProgress: Double = 0
    @State private var videoNameInput = ""
    @State private var showVideoNameSheet = false
    @State private var videoToDelete: ClientVideo? = nil
    @State private var selectedClientVideo: ClientVideo? = nil

    private var canDeleteVideos: Bool {
        guard let roles = store.currentUser?.roles else { return false }
        return roles.contains("admin") || roles.contains("trainer_admin")
    }

    private var hasProcessingLinkedVideos: Bool {
        client.workoutPlans.contains { plan in
            plan.exercises.contains { ex in
                ex.videoIds.contains { id in
                    client.videos.first(where: { $0.id == id })?.isProcessing == true
                }
            }
        }
    }

    enum DetailTab: String, CaseIterable {
        case overview, workouts, workoutPlans, videos, chat
        var displayName: String {
            switch self {
            case .overview:     return "Overview"
            case .workouts:     return "Workouts"
            case .workoutPlans: return "Plans"
            case .videos:       return "Videos"
            case .chat:         return "Chat"
            }
        }
    }

    var body: some View {
        ZStack {
            if showRecording || exerciseRecordTarget != nil {
                RecordingView(client: client) { video, clientId, onProgress in
                    if clientId == client.id {
                        client.videos.insert(video, at: 0)
                    }
                    let serverVideoId = try await store.addVideo(clientId: clientId, video: video, onProgress: onProgress)
                    if let target = exerciseRecordTarget,
                       let wi = client.workoutPlans.firstIndex(where: { $0.id == target.workoutId }),
                       let ei = client.workoutPlans[wi].exercises.firstIndex(where: { $0.id == target.exerciseId }) {
                        client.workoutPlans[wi].exercises[ei].videoIds.append(serverVideoId)
                        let w = client.workoutPlans[wi]
                        await store.updateWorkoutPlan(planId: target.workoutId, clientId: clientId,
                                                      name: w.name, exercises: w.exercises)
                    }
                } onExit: {
                    showRecording = false
                    exerciseRecordTarget = nil
                }
                .transition(.opacity)
            } else {
                mainContent
            }

            // Persistent upload snackbars — visible after RecordingView is dismissed.
            // RecordingView shows the same tasks while recording; we only render
            // here when it's not active to avoid double-showing.
            if !showRecording && exerciseRecordTarget == nil && !store.uploadTasks.isEmpty {
                VStack(spacing: 8) {
                    ForEach(store.uploadTasks) { task in
                        UploadSnackbarView(task: task) { id in
                            withAnimation { store.uploadTasks.removeAll { $0.id == id } }
                        }
                    }
                    Spacer()
                }
                .padding(.top, 60)
                .padding(.horizontal, 16)
            }
        }
        .background(Color.appBg.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: showRecording || exerciseRecordTarget != nil)
        .task(id: client.id) {
            await store.loadClientDetail(client.id)
        }
        .task(id: hasProcessingLinkedVideos) {
            guard hasProcessingLinkedVideos else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await store.loadClientDetail(client.id)
            }
        }
        .task(id: activeTab) {
            guard activeTab == .chat else { return }
            if chatId == nil { await loadChat() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await pollChatSilently()
            }
        }
        .sheet(isPresented: $showEditExercise) {
            editExerciseSheet
                .sheet(isPresented: $showVideoNameSheet) { videoNameSheet }
        }
        .sheet(isPresented: $showAddWorkout) { addWorkoutSheet }
        .fullScreenCover(item: $playingVideo) { video in
            VideoPlayerView(video: video, canDelete: canDeleteVideos) {
                videoToDelete = video
            }
        }
        .fullScreenCover(isPresented: $showVideoGallery) {
            VideoGalleryView(videos: galleryVideos)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .videos)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            pendingVideoIsExercise = false
            videoNameInput = Date.now.formatted(.dateTime.month(.abbreviated).day())
            showVideoNameSheet = true
            videoLoadTask = Task {
                defer { selectedPhotoItem = nil }
                return try? await item.loadTransferable(type: VideoFile.self)
            }
        }
        .onChange(of: selectedExercisePhotoItem) { _, item in
            guard let item else { return }
            pendingVideoIsExercise = true
            let datePart = Date.now.formatted(.dateTime.month(.abbreviated).day())
            let exercisePart = editExName.trimmingCharacters(in: .whitespaces)
            videoNameInput = exercisePart.isEmpty ? datePart : "\(exercisePart) \(datePart)"
            showVideoNameSheet = true
            videoLoadTask = Task {
                defer { selectedExercisePhotoItem = nil }
                return try? await item.loadTransferable(type: VideoFile.self)
            }
        }
        .sheet(isPresented: $showVideoNameSheet) { videoNameSheet }
        .sheet(item: $selectedClientVideo) { video in
            let feedItem = VideoFeedItem(
                from: video,
                clientId: client.id,
                clientName: client.fullName,
                uploaderName: store.currentUser?.name ?? "",
                uploaderId: store.currentUser?.id ?? ""
            )
            VideoDetailSheet(
                item: feedItem,
                onDelete: {
                    client.videos.removeAll { $0.id == video.id }
                    await store.deleteVideo(id: video.id, clientId: client.id)
                },
                onSaved: { newTitle, _ in
                    if let idx = client.videos.firstIndex(where: { $0.id == video.id }) {
                        client.videos[idx].title = newTitle
                    }
                }
            )
            .environment(store)
        }
        .alert("Delete Video?", isPresented: Binding(
            get: { videoToDelete != nil },
            set: { if !$0 { videoToDelete = nil } }
        ), presenting: videoToDelete) { v in
            Button("Delete", role: .destructive) {
                let toDelete = v
                videoToDelete = nil
                client.videos.removeAll { $0.id == toDelete.id }
                Task { await store.deleteVideo(id: toDelete.id, clientId: client.id) }
            }
            Button("Cancel", role: .cancel) { videoToDelete = nil }
        } message: { v in
            Text("Remove \"\(v.title)\"? This cannot be undone.")
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            if !(isChatFocused && activeTab == .chat) {
                VStack(spacing: 0) {
                    // Back
                    HStack {
                        Button(action: onBack) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Clients")
                                    .font(.body(14, weight: .semibold))
                            }
                            .foregroundStyle(Color.neonPink)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    // Profile Hero
                    HStack(spacing: 16) {
                        AvatarView(initials: client.initials, colorIndex: client.colorIndex, size: 70, cornerRadius: 22)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(client.fullName)
                                .font(.display(24))
                                .foregroundStyle(.white)
                            Text(client.plan)
                                .font(.body(12))
                                .foregroundStyle(Color.white.opacity(0.4))
                            HStack(spacing: 6) {
                                TagChip(label: client.status.rawValue.capitalized,
                                        color: client.status == .active ? .neonGreen : .neonOrange)
                                TagChip(label: "\(client.sessions) sessions")
                            }
                        }

                        Spacer()

                        Menu {
                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label("From Photos", systemImage: "photo.on.rectangle.angled")
                            }
                            Button {
                                showRecording = true
                            } label: {
                                Label("Record", systemImage: "video.fill")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "video.badge.plus")
                                    .font(.system(size: 14, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.neonCyan.opacity(0.15))
                            .foregroundStyle(Color.neonCyan)
                            .overlay(Capsule().stroke(Color.neonCyan.opacity(0.35), lineWidth: 1))
                            .clipShape(Capsule())
                            .shadow(color: Color.neonCyan.opacity(0.15), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                    // Stats row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            StatPill(value: "\(client.sessions)", label: "Sessions")
                            StatPill(value: "\(client.workoutPlans.count)", label: "Plans")
                            StatPill(value: "\(client.videos.count)", label: "Videos")
                            StatPill(value: client.lastSeen, label: "Last workout")
                            CopyProfileButton(clientId: client.id)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 14)

                    // Tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(DetailTab.allCases, id: \.self) { tab in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
                                } label: {
                                    Text(tab.displayName)
                                        .lineLimit(1)
                                        .font(.body(12, weight: .semibold))
                                        .foregroundStyle(activeTab == tab ? Color.neonPink : Color.white.opacity(0.5))
                                        .padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(activeTab == tab ? Color.neonPink.opacity(0.15) : Color.white.opacity(0.06))
                                        .overlay(Capsule().stroke(
                                            activeTab == tab ? Color.neonPink.opacity(0.30) : Color.white.opacity(0.09),
                                            lineWidth: 1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 12)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Tab Content
            if activeTab == .chat {
                chatContent
            } else {
                ScrollView {
                    switch activeTab {
                    case .overview:     overviewContent
                    case .workouts:     workoutsContent
                    case .workoutPlans: workoutPlansContent
                    case .videos:       videosContent
                    case .chat:         EmptyView()
                    }
                }
                .refreshable { await store.loadClientDetail(client.id, showRefreshToast: true) }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isChatFocused && activeTab == .chat)
    }

    // MARK: - Overview Tab

    private var overviewContent: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Info")

            ForEach([
                ("Plan", client.plan),
                ("Status", client.status.rawValue.capitalized),
                ("Last workout", client.lastSeen),
            ], id: \.0) { row in
                HStack {
                    Text(row.0).font(.mono(11)).foregroundStyle(Color.white.opacity(0.45))
                    Spacer()
                    Text(row.1).font(.body(14, weight: .medium)).foregroundStyle(.white)
                }
                .padding(.horizontal, 20).padding(.vertical, 11)
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).padding(.horizontal, 20)
            }

            SectionHeader(title: "Recent Videos",
                          action: client.videos.isEmpty ? nil : { activeTab = .videos },
                          actionLabel: "See All")

            if client.videos.isEmpty {
                Text("No videos yet · Start recording a session")
                    .font(.body(13))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if let v = client.videos.first {
                VideoThumb(video: v) {
                    playingVideo = v
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Workouts Tab

    private var workoutsContent: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "WORKOUTS · \(client.workouts.count)")

            if client.workouts.isEmpty {
                EmptyStateView(systemImage: "figure.run.circle", title: "No workouts logged yet")
            } else {
                ForEach(client.workouts) { workout in
                    WorkoutSessionCard(
                        workout: workout,
                        onTagsUpdated: { tags in
                            if let wi = client.workouts.firstIndex(where: { $0.id == workout.id }) {
                                client.workouts[wi].tags = tags
                            }
                            Task { await store.setWorkoutTags(clientId: client.id, workoutId: workout.id, tags: tags) }
                        },
                        onSessionQualityChanged: { q in
                            if let wi = client.workouts.firstIndex(where: { $0.id == workout.id }) {
                                client.workouts[wi].sessionQuality = q
                            }
                            Task { await store.updateSessionQuality(clientId: client.id, workoutId: workout.id, sessionQuality: q) }
                        }
                    )
                    .padding(.horizontal, 16).padding(.bottom, 14)
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Workout Plans Tab

    private var planGroups: [(groupId: String?, plans: [WorkoutPlan])] {
        var byGroup: [(String?, [WorkoutPlan])] = []
        var seen = Set<String>()
        var ungrouped: [WorkoutPlan] = []
        for plan in client.workoutPlans {
            if let gid = plan.groupId {
                if !seen.contains(gid) {
                    seen.insert(gid)
                    let members = client.workoutPlans.filter { $0.groupId == gid }
                    byGroup.append((gid, members))
                }
            } else {
                ungrouped.append(plan)
            }
        }
        return byGroup + ungrouped.map { (nil, [$0]) }
    }

    private var workoutPlansContent: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "WORKOUT PLANS · \(planGroups.count)",
                          action: { showAddWorkout = true },
                          actionLabel: "+ New")

            if planGroups.isEmpty {
                EmptyStateView(systemImage: "dumbbell", title: "No workout plans yet",
                               subtitle: "Tap + New to create the first plan")
                    .padding(.horizontal, 16)
            } else {
                ForEach(planGroups, id: \.groupId) { group in
                    planGroupCard(group.plans, groupId: group.groupId)
                        .padding(.horizontal, 16).padding(.bottom, 14)
                }
            }
        }
        .padding(.bottom, 16)
        .sheet(item: $planToPublish) { plan in
            publishConfirmSheet(plan: plan)
        }
    }

    @ViewBuilder
    private func planGroupCard(_ plans: [WorkoutPlan], groupId: String?) -> some View {
        let draft = plans.first(where: { $0.isDraft })
        let published = plans.first(where: { $0.isPublished })
        let showingDraft = groupId.map { draftViewGroups.contains($0) } ?? false
        let activePlan = showingDraft ? (draft ?? published) : (published ?? draft)

        if let activePlan {
        let hasBoth = draft != nil && published != nil
        let isDraft = activePlan.isDraft

        VStack(spacing: 0) {
                // Hero card
                VStack(spacing: 0) {
                    // Header
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            // Status kicker row
                            HStack(spacing: 8) {
                                Text(isDraft ? "DRAFT" : "PUBLISHED")
                                    .font(.mono(9, weight: .bold))
                                    .foregroundStyle(isDraft ? Color.neonOrange : Color.neonGreen)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background((isDraft ? Color.neonOrange : Color.neonGreen).opacity(0.12))
                                    .overlay(Capsule().stroke((isDraft ? Color.neonOrange : Color.neonGreen).opacity(0.35), lineWidth: 1))
                                    .clipShape(Capsule())

                                if hasBoth, let gid = groupId {
                                    // Version toggle
                                    HStack(spacing: 0) {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.18)) { _ = draftViewGroups.remove(gid) }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Circle().fill(Color.neonGreen).frame(width: 5, height: 5)
                                                    .shadow(color: showingDraft ? .clear : Color.neonGreen, radius: 4)
                                                Text("Published").font(.mono(9, weight: .bold))
                                                    .foregroundStyle(!showingDraft ? .white : Color.white.opacity(0.4))
                                            }
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(!showingDraft ? Color.white.opacity(0.08) : .clear)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            withAnimation(.easeInOut(duration: 0.18)) { _ = draftViewGroups.insert(gid) }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Circle().fill(Color.neonOrange).frame(width: 5, height: 5)
                                                    .shadow(color: showingDraft ? Color.neonOrange : .clear, radius: 4)
                                                Text("Draft").font(.mono(9, weight: .bold))
                                                    .foregroundStyle(showingDraft ? .white : Color.white.opacity(0.4))
                                            }
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(showingDraft ? Color.white.opacity(0.08) : .clear)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(2)
                                    .background(Color.black.opacity(0.3) as Color)
                                    .overlay(Capsule().stroke(Color.white.opacity(0.08) as Color, lineWidth: 1))
                                    .clipShape(Capsule())
                                }
                            }

                            Text(activePlan.name)
                                .font(.display(22))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            HStack(spacing: 6) {
                                Text("\(activePlan.exercises.count) exercises")
                                    .font(.mono(10.5))
                                    .foregroundStyle(Color.white.opacity(0.42))
                                if activePlan.versionNumber > 1 {
                                    Circle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 3)
                                    Text("v\(activePlan.versionNumber)")
                                        .font(.mono(10.5))
                                        .foregroundStyle(Color.white.opacity(0.42))
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

                    // Exercises list
                    if !activePlan.exercises.isEmpty {
                        Divider().background(Color.white.opacity(0.07)).padding(.horizontal, 16)
                        ForEach(Array(activePlan.exercises.enumerated()), id: \.element.id) { i, ex in
                            planExerciseRow(index: i, exercise: ex, plan: activePlan)
                        }
                    }

                    // Actions bar
                    HStack(spacing: 8) {
                        if isDraft {
                            Button {
                                planToPublish = activePlan
                            } label: {
                                Label("Publish…", systemImage: "checkmark.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(hex: "052e10"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(LinearGradient(colors: [Color.neonGreen, Color(hex: "22c55e")],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .clipShape(Capsule())
                                    .shadow(color: Color.neonGreen.opacity(0.35), radius: 8, y: 4)
                            }
                            .buttonStyle(.plain)
                        } else if let gid = groupId, draft == nil {
                            Button {
                                Task { await store.createDraftPlan(groupId: gid, traineeId: client.id, name: activePlan.name + " (Draft)", clientId: client.id) }
                            } label: {
                                Label("New Draft", systemImage: "pencil")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.neonOrange)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Color.neonOrange.opacity(0.1))
                                    .overlay(Capsule().stroke(Color.neonOrange.opacity(0.3), lineWidth: 1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            targetWorkoutId = activePlan.id
                            openExerciseForm(nil)
                        } label: {
                            Label("Add Exercise", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.06))
                                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.black.opacity(0.18))
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isDraft
                              ? LinearGradient(colors: [Color.neonOrange.opacity(0.07), Color.white.opacity(0.03)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.04)],
                                               startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(isDraft ? Color.neonOrange.opacity(0.35) : Color.neonGreen.opacity(0.22) as Color, lineWidth: 1))
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    @ViewBuilder
    private func planExerciseRow(index i: Int, exercise ex: Exercise, plan: WorkoutPlan) -> some View {
        let linkedVideos = ex.videoIds.compactMap { id in client.videos.first(where: { $0.id == id }) }
        HStack(spacing: 12) {
            NumberBadge(number: i + 1)

            Button {
                targetWorkoutId = plan.id
                openExerciseForm(ex)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(ex.name).font(.body(14, weight: .semibold)).foregroundStyle(.white)
                        if ex.isHidden {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.neonOrange.opacity(0.7))
                        }
                    }
                    Text(ex.displaySets).font(.mono(11)).foregroundStyle(Color.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !linkedVideos.isEmpty {
                let ready = linkedVideos.filter { !$0.isProcessing }
                let anyProcessing = linkedVideos.contains { $0.isProcessing }
                if anyProcessing {
                    ProgressView().tint(Color.neonCyan).scaleEffect(0.75)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                } else if !ready.isEmpty {
                    Button { galleryVideos = ready; showVideoGallery = true } label: {
                        HStack(spacing: 3) {
                            Image(systemName: ready.count > 1 ? "play.square.stack.fill" : "play.fill")
                                .font(.system(size: ready.count > 1 ? 11 : 9))
                            if ready.count > 1 { Text("\(ready.count)").font(.mono(9)) }
                        }
                        .foregroundStyle(Color.neonCyan)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(Color.neonCyan.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.neonCyan.opacity(0.25), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button { exerciseRecordTarget = (workoutId: plan.id, exerciseId: ex.id) } label: {
                Image(systemName: "video.fill").font(.system(size: 10))
                    .foregroundStyle(Color.neonPink)
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(Color.neonPink.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.neonPink.opacity(0.25), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color.white.opacity(0.03))
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .top)
    }

    @ViewBuilder
    private func publishConfirmSheet(plan: WorkoutPlan) -> some View {
        DarkSheet(title: "Publish this draft?", detents: [.medium]) {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Plan").font(.mono(10)).foregroundStyle(Color.white.opacity(0.4))
                        Spacer()
                        Text(plan.name).font(.body(13, weight: .semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider().background(Color.white.opacity(0.06))
                    HStack {
                        Text("Exercises").font(.mono(10)).foregroundStyle(Color.white.opacity(0.4))
                        Spacer()
                        Text("\(plan.exercises.count)").font(.body(13, weight: .semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider().background(Color.white.opacity(0.06))
                    HStack {
                        Text("Status change").font(.mono(10)).foregroundStyle(Color.white.opacity(0.4))
                        Spacer()
                        HStack(spacing: 6) {
                            Text("Draft").font(.mono(11, weight: .bold)).foregroundStyle(Color.neonOrange)
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4))
                            Text("Published").font(.mono(11, weight: .bold)).foregroundStyle(Color.neonGreen)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .background(Color.black.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)

                Text("Publishing will make this the active plan for the client.")
                    .font(.body(13))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                HStack(spacing: 10) {
                    PillButton(title: "Keep as Draft", style: .secondary, fullWidth: true) {
                        planToPublish = nil
                    }
                    Button {
                        let p = plan
                        planToPublish = nil
                        guard let gid = p.groupId else { return }
                        Task { await store.publishWorkoutPlan(groupId: gid, plan: p, clientId: client.id) }
                    } label: {
                        Text("Publish Now")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "052e10"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(LinearGradient(colors: [Color.neonGreen, Color(hex: "22c55e")],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Capsule())
                            .shadow(color: Color.neonGreen.opacity(0.4), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
    }

    // MARK: - Videos Tab

    private var videosContent: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Session Videos (\(client.videos.count))",
                          action: { showRecording = true },
                          actionLabel: "+ New")

            if client.videos.isEmpty {
                EmptyStateView(
                    systemImage: "video.slash",
                    title: "No recordings yet",
                    subtitle: "Hit \"New\" to start a session",
                    bordered: true
                )
                .padding(.horizontal, 16)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(client.videos) { v in
                        let feedItem = VideoFeedItem(
                            from: v,
                            clientId: client.id,
                            clientName: client.fullName,
                            uploaderName: store.currentUser?.name ?? "",
                            uploaderId: store.currentUser?.id ?? ""
                        )
                        VideoFeedCell(item: feedItem)
                            .onTapGesture { selectedClientVideo = v }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Edit / Add Exercise Sheet

    private func openExerciseForm(_ exercise: Exercise?) {
        editingExercise = exercise
        editExName = exercise?.name ?? ""
        editExType = exercise?.exerciseType ?? .reps
        editExSets = exercise.map { "\($0.sets)" } ?? "3"
        editExReps = exercise?.reps.map(String.init) ?? "10"
        editExDuration = exercise?.durationSeconds.map(String.init) ?? "30"
        editExNotes = exercise?.comment ?? ""
        editExVideoIds = Set(exercise?.videoIds ?? [])
        editExIsHidden = exercise?.isHidden ?? false
        showEditExercise = true
    }

    private func saveExercise() {
        guard let workoutId = targetWorkoutId,
              let wi = client.workoutPlans.firstIndex(where: { $0.id == workoutId }),
              !editExName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let originalIds = Set(editingExercise?.videoIds ?? [])
        let confirmedVideoIds = editExVideoIds.filter { id in
            originalIds.contains(id) || !id.contains("-")
        }
        let updated = Exercise(
            id: editingExercise?.id ?? UUID().uuidString,
            serverId: editingExercise?.serverId,
            name: editExName.trimmingCharacters(in: .whitespaces),
            exerciseType: editExType,
            sets: Int(editExSets) ?? 3,
            reps: editExType == .reps ? (Int(editExReps) ?? 10) : nil,
            durationSeconds: editExType == .duration ? (Int(editExDuration) ?? 30) : nil,
            comment: editExNotes,
            videoIds: Array(confirmedVideoIds),
            isHidden: editExIsHidden
        )

        if let editingId = editingExercise?.id,
           let ei = client.workoutPlans[wi].exercises.firstIndex(where: { $0.id == editingId }) {
            client.workoutPlans[wi].exercises[ei] = updated
        } else {
            client.workoutPlans[wi].exercises.append(updated)
        }

        let workout = client.workoutPlans[wi]
        Task {
            await store.updateWorkoutPlan(
                planId: workoutId,
                clientId: client.id,
                name: workout.name,
                exercises: workout.exercises
            )
        }
        showEditExercise = false
    }

    private var editExerciseSheet: some View {
        DarkSheet(title: editingExercise == nil ? "Add Exercise" : "Edit Exercise", detents: [.large]) {
            VStack(spacing: 16) {
                        FormField(label: "Exercise Name", text: $editExName, placeholder: "e.g. Bench Press", clearable: true)

                        // Type toggle
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TYPE")
                                .font(.mono(11, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.4))
                                .textCase(.uppercase)
                                .tracking(0.8)
                            Picker("Type", selection: $editExType) {
                                ForEach(ExerciseType.allCases, id: \.self) { t in
                                    Text(t.displayName).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal, 20)

                        // Sets
                        FormField(label: "Sets", text: $editExSets, placeholder: "3", keyboardType: .numberPad)

                        // Reps or Duration
                        if editExType == .reps {
                            FormField(label: "Reps", text: $editExReps, placeholder: "10", keyboardType: .numberPad)
                        } else {
                            FormField(label: "Duration (seconds)", text: $editExDuration, placeholder: "30", keyboardType: .numberPad)
                        }

                        FormField(label: "Notes", text: $editExNotes, placeholder: "Optional notes")

                        // Hidden toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HIDDEN FROM CLIENT")
                                    .font(.mono(11, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.4))
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                Text("Client won't see this exercise in their view")
                                    .font(.body(11))
                                    .foregroundStyle(Color.white.opacity(0.25))
                            }
                            Spacer()
                            Toggle("", isOn: $editExIsHidden)
                                .tint(Color.neonOrange)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 20)

                        // Video picker
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("LINKED VIDEOS")
                                    .font(.mono(11, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.4))
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                Spacer()
                                if isUploadingExerciseVideo {
                                    ProgressView()
                                        .tint(.neonCyan)
                                        .scaleEffect(0.75)
                                } else {
                                    PhotosPicker(selection: $selectedExercisePhotoItem, matching: .videos) {
                                        Label("Upload", systemImage: "photo.on.rectangle.angled")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.neonCyan)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)

                            if client.videos.isEmpty && !isUploadingExerciseVideo {
                                Text("No videos yet. Upload one above.")
                                    .font(.body(12))
                                    .foregroundStyle(Color.white.opacity(0.3))
                                    .padding(.horizontal, 20)
                            }

                            ForEach(client.videos) { video in
                                VideoPickerRow(
                                    video: video,
                                    isSelected: editExVideoIds.contains(video.id),
                                    isUploading: video.id == uploadingVideoLocalId,
                                    uploadProgress: video.id == uploadingVideoLocalId ? exerciseUploadProgress : nil,
                                    isProcessing: video.isProcessing && video.id != uploadingVideoLocalId
                                ) {
                                    if editExVideoIds.contains(video.id) { editExVideoIds.remove(video.id) }
                                    else { editExVideoIds.insert(video.id) }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        HStack(spacing: 10) {
                            PillButton(title: "Cancel", style: .secondary, fullWidth: true) {
                                showEditExercise = false
                            }
                            PillButton(
                                title: editingExercise == nil ? "Add Exercise" : "Save Changes",
                                style: .primary,
                                fullWidth: true
                            ) {
                                saveExercise()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Add Workout Sheet

    private var addWorkoutSheet: some View {
        DarkSheet(title: "New Workout Plan") {
            VStack(spacing: 16) {
                FormField(label: "Plan Name", text: $newWorkoutName, placeholder: "e.g. Upper Body A", clearable: true)
                HStack(spacing: 10) {
                    PillButton(title: "Cancel", style: .secondary, fullWidth: true) {
                        showAddWorkout = false
                    }
                    PillButton(title: "Create Plan", style: .primary, fullWidth: true) {
                        guard !newWorkoutName.isEmpty else { return }
                        let name = newWorkoutName
                        newWorkoutName = ""
                        showAddWorkout = false
                        Task { await store.createWorkoutPlan(clientId: client.id, name: name) }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Chat

    private var chatContent: some View {
        VStack(spacing: 0) {
            // Header card
            HStack(spacing: 10) {
                AvatarView(initials: client.initials, colorIndex: client.colorIndex, size: 36, cornerRadius: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.fullName)
                        .font(.display(15))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.neonGreen)
                            .frame(width: 5, height: 5)
                            .shadow(color: Color.neonGreen, radius: 3)
                    }
                }
                Spacer()
                Button {
                    Task { await refreshChat() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isChatRefreshing ? Color.neonCyan : Color.white.opacity(0.5))
                        .rotationEffect(.degrees(isChatRefreshing ? 360 : 0))
                        .animation(
                            isChatRefreshing
                                ? .linear(duration: 0.6).repeatForever(autoreverses: false)
                                : .default,
                            value: isChatRefreshing
                        )
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                            isChatRefreshing ? Color.neonCyan.opacity(0.3) : Color.white.opacity(0.1),
                            lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isChatRefreshing)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, showChatRefreshToast ? 8 : 12)

            if showChatRefreshToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.neonCyan)
                    Text("Chat refreshed")
                        .font(.body(12, weight: .semibold))
                        .foregroundStyle(Color.neonCyan)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.neonCyan.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonCyan.opacity(0.22), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Messages
            if chatId == nil || isChatLoading {
                Spacer()
                ProgressView().tint(Color.neonCyan)
                Spacer()
            } else if chatMessages.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.white.opacity(0.12))
                    Text("No messages yet")
                        .font(.body(13))
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text("Start the conversation below")
                        .font(.body(12))
                        .foregroundStyle(Color.white.opacity(0.2))
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatMessages) { msg in
                                ChatBubbleView(msg: msg, clientColorIndex: client.colorIndex)
                            }
                            Color.clear.frame(height: 1).id("chatBottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: chatMessages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("chatBottom") }
                    }
                    .onAppear { proxy.scrollTo("chatBottom") }
                }
            }

            // Composer
            HStack(spacing: 8) {
                TextField("Message…", text: $messageText)
                    .font(.body(14))
                    .foregroundStyle(.white)
                    .tint(Color.neonPink)
                    .submitLabel(.send)
                    .focused($isChatFocused)
                    .onSubmit { Task { await sendChat() } }

                let hasText = !messageText.trimmingCharacters(in: .whitespaces).isEmpty
                Button { Task { await sendChat() } } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(hasText ? Color(hex: "1a0010") : Color.white.opacity(0.4))
                        .frame(width: 34, height: 34)
                        .background(
                            Group {
                                if hasText {
                                    LinearGradient(
                                        colors: [Color.neonPink, Color(hex: "e855a0")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                } else {
                                    LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)],
                                                   startPoint: .top, endPoint: .bottom)
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: hasText ? Color.neonPink.opacity(0.4) : .clear, radius: 8)
                        .animation(.easeInOut(duration: 0.18), value: hasText)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func pollChatSilently() async {
        guard let id = chatId else { return }
        do {
            let msgs = try await APIClient.shared.fetchChatMessages(chatId: id)
            let incoming = msgs.map { m in
                ChatMessageItem(
                    id: m.id,
                    senderId: m.senderId,
                    senderName: m.sender.name,
                    text: m.content.text,
                    createdAt: m.createdAt,
                    isFromClient: m.senderId == client.id
                )
            }
            let knownIds = Set(chatMessages.map(\.id))
            let newMsgs = incoming.filter { !knownIds.contains($0.id) }
            if !newMsgs.isEmpty { chatMessages.append(contentsOf: newMsgs) }
        } catch {
            // Silent failure — polling errors don't surface to the user
        }
    }

    private func refreshChat() async {
        guard !isChatRefreshing else { return }
        let start = Date()
        withAnimation { isChatRefreshing = true }
        await loadChat()
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 1 { try? await Task.sleep(for: .seconds(1 - elapsed)) }
        withAnimation { isChatRefreshing = false }
        withAnimation { showChatRefreshToast = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { showChatRefreshToast = false }
    }

    private func loadChat() async {
        guard store.currentUser != nil else { return }
        isChatLoading = true
        defer { isChatLoading = false }
        do {
            let session = try await APIClient.shared.fetchOrCreateChat(traineeId: client.id)
            chatId = session.id
            let msgs = try await APIClient.shared.fetchChatMessages(chatId: session.id)
            chatMessages = msgs.map { m in
                ChatMessageItem(
                    id: m.id,
                    senderId: m.senderId,
                    senderName: m.sender.name,
                    text: m.content.text,
                    createdAt: m.createdAt,
                    isFromClient: m.senderId == client.id
                )
            }
        } catch {
            store.error = (error as? APIError) ?? .networkError(error)
        }
    }

    private func sendChat() async {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let chatId else { return }
        messageText = ""
        do {
            let msg = try await APIClient.shared.sendChatMessage(chatId: chatId, text: text)
            chatMessages.append(ChatMessageItem(
                id: msg.id,
                senderId: msg.senderId,
                senderName: msg.sender.name,
                text: msg.content.text,
                createdAt: msg.createdAt,
                isFromClient: msg.senderId == client.id
            ))
        } catch {
            store.error = (error as? APIError) ?? .networkError(error)
        }
    }

    // MARK: - Video Name Sheet

    private var videoNameSheet: some View {
        DarkSheet(title: "Name Your Video", detents: [.height(240)], cancelAction: {
            showVideoNameSheet = false
            pendingVideoFile = nil
            videoLoadTask?.cancel()
            videoLoadTask = nil
        }) {
            VStack(spacing: 24) {
                FormField(label: "Video Name", text: $videoNameInput, placeholder: "", clearable: true)
                Group {
                    if isAwaitingFile {
                        HStack(spacing: 6) {
                            ProgressView().tint(.white).scaleEffect(0.75)
                            Text("Preparing…")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.neonPink.opacity(0.5))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    } else {
                        PillButton(title: "Upload", icon: "arrow.up.circle.fill") {
                            Task { await confirmVideoUpload() }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func confirmVideoUpload() async {
        let resolvedFile: VideoFile?
        if let task = videoLoadTask {
            isAwaitingFile = true
            resolvedFile = await task.value
            isAwaitingFile = false
            videoLoadTask = nil
        } else {
            resolvedFile = pendingVideoFile
        }
        showVideoNameSheet = false
        guard let videoFile = resolvedFile else {
            pendingVideoFile = nil
            return
        }
        defer { pendingVideoFile = nil }
        let title = videoNameInput.trimmingCharacters(in: .whitespaces).isEmpty
            ? Date.now.formatted(.dateTime.month(.abbreviated).day())
            : videoNameInput.trimmingCharacters(in: .whitespaces)
        let video = ClientVideo(
            title: title,
            date: Date.now.formatted(.dateTime.month().day().year()),
            duration: "—",
            url: videoFile.url
        )
        if pendingVideoIsExercise {
            isUploadingExerciseVideo = true
            client.videos.insert(video, at: 0)
            uploadingVideoLocalId = video.id
            exerciseUploadProgress = 0
            defer {
                isUploadingExerciseVideo = false
                uploadingVideoLocalId = nil
                exerciseUploadProgress = 0
            }
            guard let serverVideoId = try? await store.addVideo(clientId: client.id, video: video, onProgress: { p in
                Task { @MainActor in exerciseUploadProgress = p }
            }) else {
                client.videos.removeAll { $0.id == video.id }
                return
            }
            editExVideoIds.insert(serverVideoId)
        } else {
            client.videos.insert(video, at: 0)
            let task = UploadTask(duration: "", videoURL: video.url)
            withAnimation { store.uploadTasks.insert(task, at: 0) }
            do {
                _ = try await store.addVideo(clientId: client.id, video: video) { p in
                    task.progress = p
                }
                task.phase = .done
            } catch {
                task.phase = .failed
            }
        }
    }
}

// MARK: - ChatBubbleView

struct ChatBubbleView: View {
    let msg: ChatMessageItem
    let clientColorIndex: Int

    private var col: AvatarColor { paletteColor(clientColorIndex) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !msg.isFromClient {
                ZStack {
                    Circle()
                        .fill(Color.neonPink.opacity(0.15))
                        .overlay(Circle().stroke(Color.neonPink.opacity(0.4), lineWidth: 1.5))
                    Text(String(msg.senderName.prefix(1)))
                        .font(.display(10))
                        .foregroundStyle(Color.neonPink)
                }
                .frame(width: 24, height: 24)
            } else {
                Spacer(minLength: 0)
            }

            VStack(alignment: msg.isFromClient ? .trailing : .leading, spacing: 3) {
                Text("\(msg.senderName) · \(msg.timeString)")
                    .font(.mono(9))
                    .foregroundStyle(Color.white.opacity(0.3))

                Text(msg.text)
                    .font(.body(13))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(msg.isFromClient ? col.bg : Color.neonPink.opacity(0.10))
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius:     msg.isFromClient ? 14 : 4,
                            bottomLeadingRadius:  14,
                            bottomTrailingRadius: 14,
                            topTrailingRadius:    msg.isFromClient ? 4 : 14
                        )
                        .stroke(msg.isFromClient ? col.border : Color.neonPink.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius:     msg.isFromClient ? 14 : 4,
                            bottomLeadingRadius:  14,
                            bottomTrailingRadius: 14,
                            topTrailingRadius:    msg.isFromClient ? 4 : 14
                        )
                    )
                    .frame(maxWidth: 270, alignment: msg.isFromClient ? .trailing : .leading)
            }
            .frame(maxWidth: .infinity, alignment: msg.isFromClient ? .trailing : .leading)

            if msg.isFromClient {
                ZStack {
                    Circle()
                        .fill(col.bg)
                        .overlay(Circle().stroke(col.border, lineWidth: 1.5))
                    Text(String(msg.senderName.prefix(1)))
                        .font(.display(10))
                        .foregroundStyle(col.text)
                }
                .frame(width: 24, height: 24)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }
}


// MARK: - VideoThumb

struct VideoThumb: View {
    let video: ClientVideo
    var showPlanTag = false
    let onTap: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Color.black
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }

                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)

                // Play button — centered
                ZStack {
                    Circle()
                        .fill(Color.neonCyan.opacity(0.15))
                        .overlay(Circle().stroke(Color.neonCyan.opacity(0.50), lineWidth: 1.5))
                        .shadow(color: Color.neonCyan.opacity(0.25), radius: 10)
                    Image(systemName: video.url != nil ? "play.fill" : "photo.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.neonCyan)
                }
                .frame(width: 44, height: 44)

                // Meta bar — pinned to bottom
                VStack {
                    Spacer()
                    ZStack(alignment: .bottom) {
                        LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                            .frame(height: 60)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.title).font(.body(12, weight: .semibold)).foregroundStyle(.white)
                                Text(video.date).font(.mono(10)).foregroundStyle(Color.white.opacity(0.4))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(video.duration).font(.mono(10)).foregroundStyle(Color.white.opacity(0.6))
                                if showPlanTag {
                                    Text("+ Plan")
                                        .font(.mono(10))
                                        .foregroundStyle(Color.neonPink)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Color.neonPink.opacity(0.10))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.neonPink.opacity(0.20), lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.bottom, 10)
                    }
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .task(id: video.url) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        if let cached = ThumbnailCache.shared.get(video.id) { thumbnail = cached; return }
        guard let url = video.url else { return }
        if let img = await generateThumbnail(from: url, size: CGSize(width: 480, height: 270)) {
            ThumbnailCache.shared.set(img, for: video.id)
            thumbnail = img
        }
    }
}

// MARK: - Video Player

struct VideoPlayerView: View {
    let video: ClientVideo
    var canDelete: Bool = false
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack(alignment: .top) {
            if let url = video.url {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                .buttonStyle(.plain)

                Spacer()

                if canDelete {
                    Button { showDeleteConfirm = true } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.neonRed)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 20)
        }
        .background(.black)
        .alert("Delete Video?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                dismiss()
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \"\(video.title)\"? This cannot be undone.")
        }
    }
}

// MARK: - VideoGalleryView

struct VideoGalleryView: View {
    let videos: [ClientVideo]
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var players: [AVPlayer?] = []

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { i, video in
                    Group {
                        if players.indices.contains(i), let player = players[i] {
                            VideoPlayer(player: player)
                                .onAppear { player.play() }
                                .onDisappear { player.pause() }
                        } else {
                            Color.black.overlay(
                                Image(systemName: "video.slash")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Color.white.opacity(0.3))
                            )
                        }
                    }
                    .ignoresSafeArea()
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: videos.count > 1 ? .always : .never))
            .ignoresSafeArea()

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                .buttonStyle(.plain)

                Spacer()

                if videos.count > 1 {
                    Text("\(page + 1) / \(videos.count)")
                        .font(.mono(12))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
        }
        .onAppear {
            players = videos.map { video -> AVPlayer? in
                guard let url = video.url else { return nil }
                return AVPlayer(url: url)
            }
            players.first??.play()
        }
        .onDisappear {
            players.compactMap { $0 }.forEach { $0.pause() }
        }
    }
}

// MARK: - VideoPickerRow

struct VideoPickerRow: View {
    let video: ClientVideo
    let isSelected: Bool
    var isUploading: Bool = false
    var uploadProgress: Double? = nil
    var isProcessing: Bool = false
    let onToggle: () -> Void

    @State private var thumbnail: UIImage? = nil

    private var thumbBorderColor: Color {
        if isUploading { return Color.neonCyan.opacity(0.25) }
        if isProcessing { return Color.white.opacity(0.08) }
        return isSelected ? Color.neonPink.opacity(0.45) : Color.white.opacity(0.10)
    }

    private var rowBgColor: Color {
        if isUploading { return Color.neonCyan.opacity(0.04) }
        if isProcessing { return Color.white.opacity(0.02) }
        return isSelected ? Color.neonPink.opacity(0.07) : Color.white.opacity(0.04)
    }

    private var rowBorderColor: Color {
        if isUploading { return Color.neonCyan.opacity(0.15) }
        if isProcessing { return Color.white.opacity(0.06) }
        return isSelected ? Color.neonPink.opacity(0.25) : Color.white.opacity(0.08)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isUploading ? Color.neonCyan.opacity(0.08) : Color.white.opacity(0.04))
            if isUploading || isProcessing {
                ProgressView()
                    .tint(isUploading ? Color.neonCyan : Color.white.opacity(0.35))
                    .scaleEffect(0.75)
            } else if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Image(systemName: "video.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.2))
            }
            if isSelected && !isUploading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.neonPink.opacity(isProcessing ? 0.10 : 0.25))
            }
        }
        .frame(width: 76, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(thumbBorderColor, lineWidth: 1))
    }

    @ViewBuilder
    private var trailingView: some View {
        if isUploading {
            if let progress = uploadProgress {
                Text("\(Int(progress * 100))%")
                    .font(.mono(10, weight: .semibold))
                    .foregroundStyle(Color.neonCyan)
                    .frame(width: 36)
            } else {
                ProgressView()
                    .tint(Color.neonCyan)
                    .scaleEffect(0.7)
                    .frame(width: 20)
            }
        } else if isProcessing {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.white.opacity(0.2))
            } else {
                ProgressView()
                    .tint(Color.white.opacity(0.3))
                    .scaleEffect(0.7)
                    .frame(width: 20)
            }
        } else {
            if !video.duration.isEmpty {
                Text(video.duration)
                    .font(.mono(10))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? Color.neonPink : Color.white.opacity(0.25))
        }
    }

    var body: some View {
        Button(action: { if !isUploading && !isProcessing { onToggle() } }) {
            HStack(spacing: 12) {
                thumbnailView

                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.body(13, weight: .semibold))
                        .foregroundStyle(isUploading || isProcessing ? Color.white.opacity(0.4) : .white)
                        .lineLimit(1)
                    Text(isUploading ? "Uploading…" : isProcessing ? "Processing…" : video.date)
                        .font(.mono(10))
                        .foregroundStyle(isUploading ? Color.neonCyan.opacity(0.7) : Color.white.opacity(0.3))
                }

                Spacer()
                trailingView
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(rowBgColor)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(rowBorderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard thumbnail == nil, let url = video.url else { return }
        thumbnail = await generateThumbnail(from: url, size: CGSize(width: 160, height: 90))
    }
}

// MARK: - WorkoutSessionCard

struct WorkoutSessionCard: View {
    let workout: Workout
    var onTagsUpdated: (([WorkoutTag]) -> Void)? = nil
    var onSessionQualityChanged: ((Int) -> Void)? = nil

    @State private var showTagsSheet = false
    @State private var availableTags: [WorkoutTag] = []
    @State private var selectedTagIds: Set<String> = []
    @State private var isLoadingTags = false
    @State private var isExpanded = true

    private var dateString: String {
        guard let d = workout.occurredAt else { return "Unknown date" }
        return d.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var durationString: String {
        guard let s = workout.durationSeconds, s > 0 else { return "" }
        let h = s / 3600; let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func statColor(_ value: Int, inverted: Bool = false) -> Color {
        let hi = inverted ? value <= 3 : value >= 8
        let lo = inverted ? value >= 8 : value <= 3
        if hi { return .neonGreen }
        if lo { return .neonRed }
        return Color(hex: "fbbf24")
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Session Header ──
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name.uppercased())
                        .font(.mono(10, weight: .bold))
                        .foregroundStyle(Color.neonCyan)
                        .tracking(0.1)
                    Text(dateString)
                        .font(.display(20))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        if !durationString.isEmpty {
                            Text(durationString)
                                .font(.mono(10.5))
                                .foregroundStyle(Color.white.opacity(0.45))
                            Circle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 3)
                        }
                        Text("\(workout.exercises.count) exercises")
                            .font(.mono(10.5))
                            .foregroundStyle(Color.white.opacity(0.45))
                        if let pct = workout.adherencePercent, pct > 0 {
                            Circle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 3)
                            Text(String(format: "%.0f%% adherence", pct))
                                .font(.mono(10.5))
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                    }
                }
                Spacer()
                // Trainer / client rating
                if let rating = workout.sessionQuality ?? workout.traineeRating {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(rating)").font(.display(28)).foregroundStyle(.white)
                            Text("/10").font(.body(14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.35))
                        }
                        .lineLimit(1)
                        Text("QUALITY").font(.mono(9, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .tracking(0.1)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            .background(Color.neonCyan.opacity(0.04))

            if isExpanded {
                // ── Pre-session Stats ──
                let hasPreStats = workout.preSessionEnergy != nil || workout.preSessionSoreness != nil || workout.preSessionStress != nil
                if hasPreStats {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(Color.neonCyan).frame(width: 5, height: 5)
                            Text("PRE-SESSION").font(.mono(10, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.4)).tracking(0.1)
                        }
                        HStack(spacing: 8) {
                            if let e = workout.preSessionEnergy {
                                SessionStatBox(label: "Energy", value: e, color: statColor(e))
                            }
                            if let s = workout.preSessionSoreness {
                                SessionStatBox(label: "Soreness", value: s, color: statColor(s, inverted: true))
                            }
                            if let s = workout.preSessionStress {
                                SessionStatBox(label: "Stress", value: s, color: statColor(s, inverted: true))
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .top)
                }

                // ── Post-session Stats ──
                if let postE = workout.postSessionEnergy {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(Color.neonPink).frame(width: 5, height: 5)
                            Text("POST-SESSION").font(.mono(10, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.4)).tracking(0.1)
                        }
                        HStack(spacing: 8) {
                            SessionStatBox(label: "Energy", value: postE, color: statColor(postE))
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .top)
                }

                // ── Exercise Table ──
                if !workout.exercises.isEmpty {
                    VStack(spacing: 0) {
                        // Table header
                        HStack {
                            Text("Exercise").font(.mono(9.5, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.35))
                            Spacer()
                            Text("Sets").font(.mono(9.5, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.35))
                                .frame(width: 70, alignment: .trailing)
                            Text("Weight").font(.mono(9.5, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.35))
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1), alignment: .bottom)

                        ForEach(workout.exercises) { ex in
                            let setsCompleted = ex.setsData.filter { $0.completed }.count
                            let setsExpected = ex.sets
                            let isMiss = setsCompleted < setsExpected
                            let weight = ex.setsData.compactMap { $0.weightLbs }.first

                            HStack {
                                Text(ex.name)
                                    .font(.body(13, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.9))
                                    .lineLimit(1)
                                Spacer()
                                // sets ratio
                                HStack(spacing: 0) {
                                    Text("\(setsCompleted)")
                                        .font(.mono(12.5, weight: .bold))
                                        .foregroundStyle(isMiss ? Color(hex: "fbbf24") : .white)
                                    Text("/\(setsExpected)")
                                        .font(.mono(12.5))
                                        .foregroundStyle(Color.white.opacity(0.4))
                                }
                                .frame(width: 70, alignment: .trailing)
                                // weight
                                weightCell(weight)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .overlay(Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1), alignment: .bottom)
                        }
                    }
                    .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .top)
                }

                // ── Session Quality Rating ──
                if onSessionQualityChanged != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SESSION QUALITY").font(.mono(10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.4)).tracking(0.1)
                        HStack(spacing: 4) {
                            ForEach(1...10, id: \.self) { n in
                                let selected = workout.sessionQuality == n
                                let inRange = (workout.sessionQuality ?? 0) >= n
                                Button { onSessionQualityChanged?(n) } label: {
                                    Text("\(n)")
                                        .font(.display(14, weight: .heavy))
                                        .foregroundStyle(selected ? Color(hex: "1a0010") : (inRange ? Color.neonPink.opacity(0.55) : Color.white.opacity(0.5)))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(
                                            selected
                                            ? LinearGradient(colors: [Color.neonPink, Color(hex: "e855a0")], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : (inRange ? LinearGradient(colors: [Color.neonPink.opacity(0.08), Color.neonPink.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                                               : LinearGradient(colors: [Color.white.opacity(0.03), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                                        )
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .stroke(selected ? .clear : (inRange ? Color.neonPink.opacity(0.18) : Color.white.opacity(0.1)), lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .shadow(color: selected ? Color.neonPink.opacity(0.4) : .clear, radius: 6, y: 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .top)
                }

                // ── Tags row ──
                HStack(spacing: 6) {
                    Image(systemName: "tag").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.3))
                    if workout.tags.isEmpty {
                        Text("No tags").font(.mono(10)).foregroundStyle(Color.white.opacity(0.2))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(workout.tags) { tag in
                                    Text(tag.name).font(.mono(10))
                                        .foregroundStyle(Color.neonCyan.opacity(0.8))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.neonCyan.opacity(0.08))
                                        .overlay(Capsule().stroke(Color.neonCyan.opacity(0.20), lineWidth: 1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    Spacer()
                    if onTagsUpdated != nil {
                        Button { selectedTagIds = Set(workout.tags.map(\.id)); showTagsSheet = true } label: {
                            Text("Edit").font(.mono(10, weight: .semibold)).foregroundStyle(Color.neonCyan)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .top)

                // ── Comment ──
                if let comment = workout.comment, !comment.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.3))
                        Text(comment).font(.body(12)).foregroundStyle(Color.white.opacity(0.5))
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .top)
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $showTagsSheet) { tagsSheet }
    }

    @ViewBuilder
    private func weightCell(_ weight: Double?) -> some View {
        if let w = weight, w > 0 {
            let wStr: String = w.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(w)) lbs"
                : String(format: "%.1f lbs", w)
            Text(wStr)
                .font(.mono(12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
        } else {
            Text("—")
                .font(.mono(12))
                .foregroundStyle(Color.white.opacity(0.2))
        }
    }

    private var tagsSheet: some View {
        DarkSheet(title: "Workout Tags") {
            VStack(spacing: 0) {
                if isLoadingTags {
                    ProgressView().tint(Color.neonCyan).padding(.vertical, 32)
                } else if availableTags.isEmpty {
                    Text("No tags available")
                        .font(.body(13))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(availableTags) { tag in
                                Button {
                                    if selectedTagIds.contains(tag.id) { selectedTagIds.remove(tag.id) }
                                    else { selectedTagIds.insert(tag.id) }
                                } label: {
                                    HStack {
                                        Text(tag.name)
                                            .font(.body(14))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Image(systemName: selectedTagIds.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(selectedTagIds.contains(tag.id) ? Color.neonCyan : Color.white.opacity(0.25))
                                    }
                                    .padding(.horizontal, 20).padding(.vertical, 14)
                                    .background(selectedTagIds.contains(tag.id) ? Color.neonCyan.opacity(0.06) : Color.clear)
                                }
                                .buttonStyle(.plain)
                                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 20)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }

                HStack(spacing: 10) {
                    PillButton(title: "Cancel", style: .secondary, fullWidth: true) { showTagsSheet = false }
                    PillButton(title: "Save Tags", style: .primary, fullWidth: true) {
                        let saved = availableTags.filter { selectedTagIds.contains($0.id) }
                        showTagsSheet = false
                        onTagsUpdated?(saved)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24).padding(.top, 12)
            }
        }
        .task {
            guard availableTags.isEmpty else { return }
            isLoadingTags = true
            defer { isLoadingTags = false }
            availableTags = (try? await APIClient.shared.fetchAvailableWorkoutTags())?
                .map { WorkoutTag(id: $0.id, name: $0.name) } ?? []
        }
    }
}

// MARK: - CopyProfileButton

struct CopyProfileButton: View {
    let clientId: String
    @State private var state: CopyState = .idle

    enum CopyState { case idle, loading, copied, failed }

    var body: some View {
        Button {
            guard state != .loading else { return }
            state = .loading
            Task {
                do {
                    let result = try await APIClient.shared.fetchPortalLink(traineeId: clientId)
                    UIPasteboard.general.string = result.url
                    withAnimation { state = .copied }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { state = .idle }
                } catch {
                    withAnimation { state = .failed }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { state = .idle }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: state == .copied ? "checkmark" : "link")
                    .font(.system(size: 11, weight: .semibold))
                Text(state == .copied ? "Copied!" : state == .failed ? "Failed" : state == .loading ? "Generating…" : "Copy Profile")
                    .font(.mono(11))
            }
            .foregroundStyle(state == .copied ? Color.neonCyan : state == .failed ? Color.neonRed : Color.white.opacity(0.55))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(state == .copied ? Color.neonCyan.opacity(0.12) : Color.white.opacity(0.06))
            .overlay(Capsule().stroke(
                state == .copied ? Color.neonCyan.opacity(0.30) : Color.white.opacity(0.10),
                lineWidth: 1))
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.15), value: state)
        }
        .buttonStyle(.plain)
        .disabled(state == .loading)
    }
}

private struct VideoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { v in
            SentTransferredFile(v.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFile(url: dest)
        }
    }
}
