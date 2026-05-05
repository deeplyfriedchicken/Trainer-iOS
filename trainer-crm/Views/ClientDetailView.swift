import SwiftUI
import AVKit

struct ClientDetailView: View {
    @Environment(AppStore.self) private var store
    @Binding var client: Client
    let onBack: () -> Void

    @State private var activeTab: DetailTab = .overview
    @State private var showRecording = false
    @State private var showAddExercise = false
    @State private var showAddWorkout = false
    @State private var targetWorkoutId: String? = nil
    @State private var newExName = ""
    @State private var newExSets = ""
    @State private var newWorkoutName = ""
    @State private var uploadBanner: ClientVideo? = nil
    @State private var playerItem: AVPlayerItem? = nil
    @State private var playerURL: URL? = nil
    @State private var isRefreshing = false
    @State private var chatId: String? = nil
    @State private var chatMessages: [ChatMessageItem] = []
    @State private var isChatLoading = false
    @State private var messageText = ""

    enum DetailTab: String, CaseIterable { case overview, workouts, videos, chat }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            if showRecording {
                RecordingView(client: client) { video, clientId in
                    if clientId == client.id {
                        client.videos.insert(video, at: 0)
                        uploadBanner = video
                    }
                    try await store.addVideo(clientId: clientId, video: video)
                } onExit: {
                    showRecording = false
                }
                .transition(.opacity)
            } else {
                mainContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showRecording)
        .task(id: client.id) {
            await store.loadClientDetail(client.id)
        }
        .onChange(of: activeTab) { _, newTab in
            if newTab == .chat, chatId == nil {
                Task { await loadChat() }
            }
        }
        .sheet(isPresented: $showAddExercise) { addExerciseSheet }
        .sheet(isPresented: $showAddWorkout) { addWorkoutSheet }
        .fullScreenCover(item: $playerURL) { url in
            VideoPlayerView(url: url)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
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

                PillButton(title: "Record", icon: "video.fill", style: .cyan) {
                    showRecording = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // Stats row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    StatPill(value: "\(client.sessions)", label: "Sessions")
                    StatPill(value: "\(client.workouts.count)", label: "Plans")
                    StatPill(value: "\(client.videos.count)", label: "Videos")
                    StatPill(value: client.lastSeen, label: "Last Seen")
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 14)

            // Tabs
            HStack(spacing: 6) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
                    } label: {
                        Text(tab.rawValue.capitalized)
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
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Tab Content
            if activeTab == .chat {
                chatContent
            } else {
                ScrollView {
                    switch activeTab {
                    case .overview: overviewContent
                    case .workouts: workoutsContent
                    case .videos:   videosContent
                    case .chat:    EmptyView()
                    }
                }
                .refreshable { await store.loadClientDetail(client.id) }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                guard !isRefreshing else { return }
                isRefreshing = true
                Task {
                    await store.loadClientDetail(client.id)
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing ? .linear(duration: 0.7).repeatForever(autoreverses: false) : .default,
                        value: isRefreshing
                    )
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.10))
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Overview Tab

    private var overviewContent: some View {
        VStack(spacing: 0) {
            if let banner = uploadBanner {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.neonGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video uploaded!").font(.body(13, weight: .semibold)).foregroundStyle(Color.neonGreen)
                        Text("\"\(banner.title)\" added to Videos tab")
                            .font(.body(11)).foregroundStyle(Color.white.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.neonGreen.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.neonGreen.opacity(0.22), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16).padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

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
                    if let url = v.url { playerURL = url }
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Workouts Tab

    private var workoutsContent: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Workout Plans (\(client.workouts.count))",
                          action: { showAddWorkout = true },
                          actionLabel: "+ New")

            if client.workouts.isEmpty {
                Text("No workout plans yet")
                    .font(.body(13)).foregroundStyle(Color.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 40)
            } else {
                ForEach(client.workouts) { workout in
                    WorkoutPlanCard(workout: workout) {
                        targetWorkoutId = workout.id
                        showAddExercise = true
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Videos Tab

    private var videosContent: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Session Videos (\(client.videos.count))",
                          action: { showRecording = true },
                          actionLabel: "+ New")

            if client.videos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.white.opacity(0.2))
                    Text("No recordings yet")
                        .font(.body(13)).foregroundStyle(Color.white.opacity(0.3))
                    Text("Hit \"New\" to start a session")
                        .font(.body(12)).foregroundStyle(Color.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(style: StrokeStyle(lineWidth: 1, dash: [6])).foregroundStyle(Color.white.opacity(0.10)))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
            } else {
                ForEach(client.videos) { v in
                    VideoThumb(video: v, showPlanTag: true) {
                        if let url = v.url { playerURL = url }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 10)
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Add Exercise Sheet

    private var addExerciseSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 16) {
                    FormField(label: "Exercise Name", text: $newExName, placeholder: "e.g. Bench Press")
                    FormField(label: "Sets × Reps", text: $newExSets, placeholder: "e.g. 4×8")
                    HStack(spacing: 10) {
                        PillButton(title: "Cancel", style: .secondary, fullWidth: true) {
                            showAddExercise = false
                        }
                        PillButton(title: "Add Exercise", style: .primary, fullWidth: true) {
                            guard !newExName.isEmpty, let wid = targetWorkoutId else { return }
                            if let wi = client.workouts.firstIndex(where: { $0.id == wid }) {
                                client.workouts[wi].exercises.append(
                                    Exercise(name: newExName, sets: newExSets.isEmpty ? "3×10" : newExSets, rest: "60s")
                                )
                                store.updateClient(client)
                            }
                            newExName = ""; newExSets = ""
                            showAddExercise = false
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 24)
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(Color(hex: "0c0c1c"))
    }

    // MARK: - Add Workout Sheet

    private var addWorkoutSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                VStack(spacing: 16) {
                    FormField(label: "Plan Name", text: $newWorkoutName, placeholder: "e.g. Upper Body A")
                    HStack(spacing: 10) {
                        PillButton(title: "Cancel", style: .secondary, fullWidth: true) {
                            showAddWorkout = false
                        }
                        PillButton(title: "Create Plan", style: .primary, fullWidth: true) {
                            guard !newWorkoutName.isEmpty else { return }
                            client.workouts.append(WorkoutPlan(name: newWorkoutName, exercises: []))
                            store.updateClient(client)
                            newWorkoutName = ""
                            showAddWorkout = false
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 24)
            }
            .navigationTitle("New Workout Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(Color(hex: "0c0c1c"))
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
                        Text("Online")
                            .font(.body(11))
                            .foregroundStyle(Color.neonGreen)
                    }
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)

            // Messages
            if chatId == nil {
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

    private func loadChat() async {
        guard let currentUser = store.currentUser else { return }
        isChatLoading = true
        defer { isChatLoading = false }
        do {
            let session = try await APIClient.shared.fetchOrCreateChat(
                traineeId: client.id,
                trainerId: currentUser.id
            )
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

// MARK: - WorkoutPlanCard

struct WorkoutPlanCard: View {
    let workout: WorkoutPlan
    let onAddExercise: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Plan header
            HStack {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.neonPink)
                Text(workout.name)
                    .font(.body(14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                TagChip(label: "\(workout.exercises.count) exercises")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.neonPink.opacity(0.08))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 0, topTrailingRadius: 14)
                    .stroke(Color.neonPink.opacity(0.15), lineWidth: 1)
            )

            // Exercises
            ForEach(Array(workout.exercises.enumerated()), id: \.offset) { i, ex in
                HStack(spacing: 12) {
                    Text("\(i + 1)")
                        .font(.display(13))
                        .foregroundStyle(Color.neonPink)
                        .frame(width: 28, height: 28)
                        .background(Color.neonPink.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.neonPink.opacity(0.20), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(.body(14, weight: .semibold)).foregroundStyle(.white)
                        Text("\(ex.sets) · Rest \(ex.rest)")
                            .font(.mono(11)).foregroundStyle(Color.white.opacity(0.4))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white.opacity(0.04))
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: i == workout.exercises.count - 1 ? 14 : 0,
                        bottomTrailingRadius: i == workout.exercises.count - 1 ? 14 : 0, topTrailingRadius: 0
                    )
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }

            // Add exercise
            Button(action: onAddExercise) {
                Text("+ Add Exercise")
                    .font(.mono(11))
                    .foregroundStyle(Color.neonCyan)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                // Thumbnail or fallback pattern
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            Canvas { ctx, size in
                                let spacing: CGFloat = 14
                                var x: CGFloat = 0
                                while x < size.width + size.height {
                                    ctx.stroke(
                                        Path { p in
                                            p.move(to: CGPoint(x: x, y: 0))
                                            p.addLine(to: CGPoint(x: x - size.height, y: size.height))
                                        },
                                        with: .color(Color.white.opacity(0.015)), lineWidth: 1
                                    )
                                    x += spacing
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        )
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
        .task {
            await generateThumbnail()
        }
    }

    private func generateThumbnail() async {
        guard let url = video.url else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            thumbnail = UIImage(cgImage: cgImage)
        } catch {
            // fall back to pattern background
        }
    }
}

// MARK: - Video Player

struct VideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            .buttonStyle(.plain)
            .padding(.top, 60)
            .padding(.leading, 20)
        }
        .background(.black)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
