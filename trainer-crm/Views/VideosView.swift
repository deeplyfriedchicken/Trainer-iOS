import SwiftUI
import AVKit
@preconcurrency import AVFoundation

// MARK: - Videos Feed

struct VideosView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: VideoFeedItem? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Videos")
                        .font(.display(28))
                        .foregroundStyle(.white)
                    Text("\(store.feedVideos.count) recordings")
                        .font(.mono(12))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if store.isFeedLoading && store.feedVideos.isEmpty {
                Spacer()
                ProgressView().tint(Color.neonCyan).scaleEffect(1.3)
                Spacer()
            } else if store.feedVideos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(store.feedVideos) { item in
                            VideoFeedCell(item: item)
                                .onTapGesture { selected = item }
                                .onAppear {
                                    if item.id == store.feedVideos.last?.id {
                                        Task { await store.loadMoreFeedVideos() }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                    if store.isFeedLoading {
                        ProgressView().tint(Color.neonCyan).padding(.vertical, 16)
                    }
                }
                .refreshable { await Task { await store.loadFeedVideos() }.value }
            }
        }
        .task {
            if store.feedVideos.isEmpty {
                await store.loadFeedVideos()
            }
        }
        .sheet(item: $selected) { item in
            VideoDetailSheet(item: item)
                .environment(store)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "video.slash",
            title: "No videos yet",
            subtitle: "Record a client session to see it here"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Video Feed Cell

struct VideoFeedCell: View {
    let item: VideoFeedItem
    @State private var thumbnail: UIImage? = nil

    private var uploaderColor: AvatarColor { paletteColor(item.uploaderColorIndex) }
    private var traineeColor: AvatarColor { paletteColor(item.traineeColorIndex) }

    private var traineeShortName: String {
        guard let name = item.traineeName else { return "" }
        let parts = name.components(separatedBy: " ")
        guard let first = parts.first, !first.isEmpty else { return name }
        if let last = parts.dropFirst().first, !last.isEmpty {
            return "\(first) \(last.prefix(1))."
        }
        return first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black

            // Thumbnail: scaledToFit so non-matching ratios letterbox naturally
            if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Bottom gradient for text readability
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.85), location: 0),
                    .init(color: .black.opacity(0.10), location: 0.45),
                    .init(color: .clear, location: 0.70),
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            // Centered play button
            Circle()
                .fill(.black.opacity(0.45))
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer: title + duration only
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.body(13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                if !item.duration.isEmpty {
                    HStack {
                        Spacer()
                        Text(item.duration)
                            .font(.mono(10))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        // Client name chip — top left
        .overlay(alignment: .topLeading) {
            if item.traineeName != nil {
                HStack(spacing: 5) {
                    Circle()
                        .fill(traineeColor.bg)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Text(item.traineeInitials ?? "")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(traineeColor.text)
                        )
                        .overlay(Circle().stroke(traineeColor.border, lineWidth: 1))
                    Text(traineeShortName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(traineeColor.border, lineWidth: 1))
                .padding(8)
            }
        }
        // Trainer initials — top right
        .overlay(alignment: .topTrailing) {
            Text(item.uploaderInitials)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(uploaderColor.text)
                .frame(width: 22, height: 22)
                .background(uploaderColor.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(uploaderColor.border, lineWidth: 1)
                )
                .padding(8)
        }
        .aspectRatio(9/16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .task(id: item.fileURL) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        if let cached = ThumbnailCache.shared.get(item.id) { thumbnail = cached; return }
        guard let url = item.fileURL else { return }
        if let img = await generateThumbnail(from: url, size: CGSize(width: 480, height: 960)) {
            ThumbnailCache.shared.set(img, for: item.id)
            thumbnail = img
        }
    }
}

// MARK: - Video Detail Sheet

struct VideoDetailSheet: View {
    let item: VideoFeedItem
    /// Custom delete handler — if nil, uses store.deleteVideo + dismiss
    var onDelete: (() async -> Void)? = nil
    /// Called after a successful save with (newTitle, newDescription)
    var onSaved: ((String, String?) -> Void)? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer? = nil
    @State private var isPlaying = false
    @State private var thumbnail: UIImage? = nil
    @State private var editing = false
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var editTagsText = ""
    @State private var showDeleteConfirm = false
    @State private var toast: VidToast? = nil
    @State private var isSaving = false

    private var canDelete: Bool {
        guard let roles = store.currentUser?.roles else { return false }
        return roles.contains("admin") || roles.contains("trainer_admin")
    }
    private var displayTitle: String {
        store.feedVideos.first(where: { $0.id == item.id })?.title ?? item.title
    }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(spacing: 0) {
                actionBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        videoStage
                        titleSection
                        if !editing {
                            pillsRow
                            tagsSection
                            if let desc = item.description, !desc.isEmpty {
                                descriptionCard(desc)
                            }
                            metaCard
                            personCard
                        }
                    }
                    .padding(.bottom, 40)
                }
            }

            if showDeleteConfirm { deleteModal }
            if let t = toast { toastView(t) }
        }
        .task(id: item.fileURL) {
            if let cached = ThumbnailCache.shared.get(item.id) { thumbnail = cached; return }
            guard let url = item.fileURL else { return }
            if let img = await generateThumbnail(from: url, size: CGSize(width: 480, height: 960)) {
                ThumbnailCache.shared.set(img, for: item.id)
                thumbnail = img
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: Action Bar
    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                if editing { editing = false } else { dismiss() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(editing ? "Cancel" : "Videos")
                        .font(.body(14, weight: .semibold))
                }
                .foregroundStyle(Color.neonPink)
            }
            .buttonStyle(.plain)

            Spacer()

            if editing {
                if isSaving {
                    ProgressView().tint(Color.neonPink).scaleEffect(0.8)
                } else {
                    Button {
                        Task { await saveEdit() }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "1a0010"))
                            .frame(width: 36, height: 36)
                            .background(
                                LinearGradient(colors: [.neonPink, Color(hex: "e855a0")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 6) {
                    IconButton(systemImage: "pencil") {
                        editTitle = displayTitle
                        editDescription = item.description ?? ""
                        editTagsText = item.tags.joined(separator: ", ")
                        editing = true
                    }
                    if canDelete || onDelete != nil {
                        IconButton(systemImage: "trash",
                                   tint: Color.neonRed,
                                   bg: Color.neonRed.opacity(0.10),
                                   border: Color.neonRed.opacity(0.30)) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // MARK: Save
    private func saveEdit() async {
        let trimmedTitle = editTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        let desc = editDescription.trimmingCharacters(in: .whitespaces)
        let editedNames = Set(editTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        let tagIds = zip(item.tags, item.tagIds).compactMap { name, id in
            editedNames.contains(name) ? id : nil
        }

        isSaving = true
        let success = await store.updateFeedVideo(
            id: item.id,
            title: trimmedTitle,
            description: desc.isEmpty ? nil : desc,
            tagIds: tagIds
        )
        if success { onSaved?(trimmedTitle, desc.isEmpty ? nil : desc) }
        isSaving = false
        editing = success ? false : editing
        toast = VidToast(message: success ? "Video details updated" : "Update failed", success: success)
    }

    // MARK: Video Stage
    private var videoStage: some View {
        ZStack {
            Color.black

            if isPlaying, let p = player {
                VideoPlayer(player: p)
            } else {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Circle()
                    .fill(.black.opacity(0.4))
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    )
                    .onTapGesture {
                        guard let url = item.fileURL else { return }
                        let p = AVPlayer(url: url)
                        p.play()
                        player = p
                        isPlaying = true
                    }
            }

            VStack {
                HStack {
                    if !item.duration.isEmpty {
                        Text("● REC · \(item.duration)")
                            .font(.mono(10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .tracking(0.8)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    if !item.duration.isEmpty {
                        Text(item.duration)
                            .font(.mono(11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(12)
        }
        .aspectRatio(9/16, contentMode: .fit)
        .frame(maxHeight: 380)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: Title / Edit
    @ViewBuilder
    private var titleSection: some View {
        if editing {
            VStack(spacing: 14) {
                FormField(label: "Title", text: $editTitle, placeholder: "Video title")
                FormField(label: "Description", text: $editDescription, placeholder: "Add a description…", multiline: true)
                FormField(label: "Tags", text: $editTagsText, placeholder: "e.g. squat, form check, upper body")
                Text("Separate tags with commas")
                    .font(.mono(10))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .padding(.horizontal, 20)
                    .padding(.top, -8)
            }
            .padding(.bottom, 20)
        } else {
            Text(displayTitle)
                .font(.display(26))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    // MARK: Pills
    private var pillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !item.dateString.isEmpty {
                    VidPill(label: item.dateString, icon: "clock", style: .cyan)
                }
                if !item.duration.isEmpty {
                    VidPill(label: item.duration, icon: "timer", style: .neutral)
                }
                if let name = item.traineeName {
                    VidPill(label: name, style: .dot(color: paletteColor(item.traineeColorIndex).text))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    // MARK: Tags
    @ViewBuilder
    private var tagsSection: some View {
        if !item.tags.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("TAGS")
                    .font(.mono(10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .tracking(0.8)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.tags, id: \.self) { tag in
                            VidPill(label: tag, icon: "tag", style: .neutral)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: Description Card
    private func descriptionCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DESCRIPTION")
                .font(.mono(10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.4))
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
            Text(text)
                .font(.body(13))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Meta Card
    private var metaCard: some View {
        VStack(spacing: 0) {
            vidMetaRow(label: "FILE",
                       value: item.fileURL?.lastPathComponent ?? "—",
                       mono: true)
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).padding(.horizontal, 16)
            vidMetaRow(label: "DURATION",
                       value: item.duration.isEmpty ? "—" : item.duration,
                       mono: true)
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Person Card
    private var personCard: some View {
        VStack(spacing: 0) {
            vidPersonRow(label: "UPLOADED BY",
                         name: item.uploaderName,
                         initials: item.uploaderInitials,
                         colorIndex: item.uploaderColorIndex,
                         trailing: item.dateString.isEmpty ? nil : item.dateString)
            if let name = item.traineeName {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).padding(.horizontal, 16)
                vidPersonRow(label: "CLIENT",
                             name: name,
                             initials: item.traineeInitials ?? "",
                             colorIndex: item.traineeColorIndex,
                             trailing: nil)
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }

    // MARK: Delete Modal
    private var deleteModal: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { showDeleteConfirm = false } }

            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.neonRed.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.neonRed.opacity(0.3), lineWidth: 1))
                    Image(systemName: "trash")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.neonRed)
                }
                .frame(width: 52, height: 52)

                Text("Delete this video?")
                    .font(.display(22))
                    .foregroundStyle(.white)

                Text("**\"\(displayTitle)\"** will be permanently removed. This can't be undone.")
                    .font(.body(13))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button {
                        withAnimation { showDeleteConfirm = false }
                    } label: {
                        Text("Cancel")
                            .font(.body(14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDeleteConfirm = false
                        Task {
                            if let handler = onDelete {
                                await handler()
                            } else {
                                await store.deleteVideo(id: item.id)
                            }
                            dismiss()
                        }
                    } label: {
                        Text("Delete")
                            .font(.body(14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(colors: [Color(hex: "f87171"), Color(hex: "ef4444")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: Color(hex: "f87171").opacity(0.35), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "14122c").opacity(0.97))
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.neonRed.opacity(0.25), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.6), radius: 40)
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showDeleteConfirm)
    }

    // MARK: Toast
    private func toastView(_ t: VidToast) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(t.success ? Color.neonGreen.opacity(0.15) : Color.neonRed.opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(t.success ? Color.neonGreen.opacity(0.35) : Color.neonRed.opacity(0.35), lineWidth: 1))
                    Image(systemName: t.success ? "checkmark" : "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(t.success ? Color.neonGreen : Color.neonRed)
                }
                .frame(width: 32, height: 32)
                Text(t.message)
                    .font(.body(13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "14122c").opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(t.success ? Color.neonGreen.opacity(0.3) : Color.neonRed.opacity(0.35), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation { toast = nil }
            }
        }
    }

    // MARK: Row helpers
    private func vidMetaRow(label: String, value: String, mono: Bool) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.mono(10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.4))
                .tracking(0.8)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(mono ? .mono(11) : .body(13, weight: .medium))
                .foregroundStyle(mono ? Color.white.opacity(0.7) : .white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func vidPersonRow(label: String, name: String, initials: String, colorIndex: Int, trailing: String?) -> some View {
        HStack(spacing: 10) {
            AvatarView(initials: initials, colorIndex: colorIndex, size: 36, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.mono(9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .tracking(0.8)
                Text(name)
                    .font(.body(14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            if let t = trailing {
                Text(t)
                    .font(.mono(10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .tracking(0.6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Shared helpers

struct VidToast: Identifiable {
    let id = UUID()
    let message: String
    let success: Bool
}

