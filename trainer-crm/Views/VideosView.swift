import SwiftUI
import AVKit
@preconcurrency import AVFoundation

// MARK: - Videos Feed

struct VideosView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: VideoFeedItem? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
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
                    LazyVGrid(columns: columns, spacing: 2) {
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash")
                .font(.system(size: 40))
                .foregroundStyle(Color.white.opacity(0.15))
            Text("No videos yet")
                .font(.display(22))
                .foregroundStyle(Color.white.opacity(0.4))
            Text("Record a client session to see it here")
                .font(.body(13))
                .foregroundStyle(Color.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Video Feed Cell

struct VideoFeedCell: View {
    let item: VideoFeedItem
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
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
                                        with: .color(Color.white.opacity(0.015)),
                                        lineWidth: 1
                                    )
                                    x += spacing
                                }
                            }
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Image(systemName: "play.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.white.opacity(0.75))
                .shadow(color: .black.opacity(0.6), radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.black.opacity(0.88), .clear],
                startPoint: .bottom, endPoint: .top
            )
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body(11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if !item.duration.isEmpty {
                        Text(item.duration)
                            .font(.mono(9))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Spacer()
                    if let initials = item.traineeInitials {
                        AvatarView(initials: initials, colorIndex: item.traineeColorIndex,
                                   size: 20, cornerRadius: 6)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .aspectRatio(9/16, contentMode: .fit)
        .clipped()
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard let url = item.fileURL else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 300, height: 533)
        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            thumbnail = UIImage(cgImage: cgImage)
        } catch {}
    }
}

// MARK: - Video Detail Sheet

struct VideoDetailSheet: View {
    let item: VideoFeedItem
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil
    @State private var showDeleteConfirm = false

    private var canDelete: Bool {
        guard let roles = store.currentUser?.roles else { return false }
        return roles.contains("admin") || roles.contains("trainer_admin")
    }

    var body: some View {
        ZStack {
            Color(hex: "0c0c1c").ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 36, height: 4)
                    if canDelete {
                        HStack {
                            Spacer()
                            Button { showDeleteConfirm = true } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.neonRed)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Player
                        ZStack {
                            Color.black.aspectRatio(16/9, contentMode: .fit)
                            if let p = player {
                                VideoPlayer(player: p)
                                    .aspectRatio(16/9, contentMode: .fit)
                            } else {
                                Color.black
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .overlay(ProgressView().tint(Color.neonCyan))
                            }
                        }

                        // Title
                        Text(item.title)
                            .font(.display(20))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 10)

                        // Meta pills
                        HStack(spacing: 8) {
                            if !item.dateString.isEmpty {
                                TagChip(label: item.dateString, color: Color.white.opacity(0.5))
                            }
                            if !item.duration.isEmpty {
                                TagChip(label: item.duration, color: .neonCyan)
                            }
                            ForEach(item.tags, id: \.self) { tag in
                                TagChip(label: tag, color: .neonPink)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                        divider

                        // Recorded by
                        infoRow(
                            label: "RECORDED BY",
                            name: item.uploaderName,
                            initials: item.uploaderInitials,
                            colorIndex: item.uploaderColorIndex,
                            placeholder: nil
                        )

                        divider

                        // Client
                        infoRow(
                            label: "CLIENT",
                            name: item.traineeName ?? "Unassigned",
                            initials: item.traineeInitials ?? "",
                            colorIndex: item.traineeColorIndex,
                            placeholder: item.traineeInitials == nil ? "person.fill" : nil
                        )
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            if let url = item.fileURL {
                let p = AVPlayer(url: url)
                p.play()
                player = p
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .alert("Delete Video?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.deleteVideo(id: item.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \"\(item.title)\"? This cannot be undone.")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private func infoRow(
        label: String,
        name: String,
        initials: String,
        colorIndex: Int,
        placeholder: String?
    ) -> some View {
        HStack(spacing: 14) {
            if let icon = placeholder {
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1))
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                .frame(width: 46, height: 46)
            } else {
                AvatarView(initials: initials, colorIndex: colorIndex, size: 46, cornerRadius: 15)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.mono(10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .tracking(1)
                Text(name)
                    .font(.body(15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
