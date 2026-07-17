import SwiftUI
import AVKit
@preconcurrency import AVFoundation

// MARK: - Videos Feed

/// Backing model for a Video Library surface. Search, sort, and grouping are all
/// resolved server-side (backend ADR 0006); this model just holds the current query
/// and the server-ordered rows (with per-row group metadata). One instance per mount,
/// so the global tab and a client-scoped tab stay independent.
@MainActor
@Observable
final class VideoFeedModel {
    enum SortKey: String { case name, trainee, date }
    enum SortDir: String { case asc, desc }
    enum GroupBy: String, Hashable { case none, trainee, month }

    /// nil = global library; non-nil = scoped to a single trainee.
    let traineeId: String?
    var search: String = "" { didSet { if oldValue != search { scheduleSearchReload() } } }
    private(set) var sortKey: SortKey = .date
    private(set) var sortDir: SortDir = .desc
    private(set) var groupBy: GroupBy = .month

    private(set) var rows: [VideoFeedItem] = []
    private(set) var isLoading = false
    private(set) var hasMore = true

    private let pageSize = 20
    private let api = APIClient.shared
    private var searchDebounce: Task<Void, Never>? = nil

    init(traineeId: String?) { self.traineeId = traineeId }

    func setSort(_ key: SortKey) {
        if sortKey == key {
            sortDir = sortDir == .asc ? .desc : .asc
        } else {
            sortKey = key
            sortDir = key == .date ? .desc : .asc
        }
        Task { await reload() }
    }

    func setGroupBy(_ g: GroupBy) {
        guard g != groupBy else { return }
        groupBy = g
        Task { await reload() }
    }

    func loadInitial() async {
        if rows.isEmpty { await reload() }
    }

    private func scheduleSearchReload() {
        searchDebounce?.cancel()
        searchDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await self?.reload()
        }
    }

    private func query(offset: Int) async throws -> [VideoFeedItem] {
        let items = try await api.fetchVideos(
            limit: pageSize,
            offset: offset,
            traineeId: traineeId,
            search: search.isEmpty ? nil : search,
            sort: sortKey.rawValue,
            order: sortDir.rawValue,
            groupBy: groupBy.rawValue
        )
        return items.map(VideoFeedItem.init)
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await query(offset: 0)
            rows = items
            hasMore = items.count == pageSize
        } catch is CancellationError {
        } catch {
            // Keep whatever we have; the surface shows its empty/last-known state.
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await query(offset: rows.count)
            rows.append(contentsOf: items)
            hasMore = items.count == pageSize
        } catch { }
    }

    func remove(id: String) { rows.removeAll { $0.id == id } }

    func applyEdit(id: String, title: String, description: String?) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].title = title
        rows[i].description = description
    }
}

// MARK: - Videos View (reusable)

/// The Video Library table. Reused in two mounts: the global Videos tab (`traineeId`
/// nil) and a trainee's detail (`traineeId` set + `embedded`). The scoped mount drops
/// the Trainee column and the Trainee group option, and merges local in-flight uploads.
struct VideosView: View {
    @Environment(AppStore.self) private var store

    var traineeId: String? = nil
    /// When embedded inside another ScrollView (client detail), render plain content
    /// and skip the standalone header/own ScrollView.
    var embedded: Bool = false
    var searchPlaceholder: String = "Search videos, tags, clients…"
    /// Scoped mount: locally-tracked recordings (uploading/processing or just-ready)
    /// that may not be in the server feed yet.
    var inFlight: [ClientVideo] = []
    var clientName: String? = nil
    var onVideoDeleted: ((String) -> Void)? = nil
    var onVideoRenamed: ((String, String) -> Void)? = nil

    @State private var model: VideoFeedModel
    @State private var selected: VideoFeedItem? = nil

    init(
        traineeId: String? = nil,
        embedded: Bool = false,
        searchPlaceholder: String = "Search videos, tags, clients…",
        inFlight: [ClientVideo] = [],
        clientName: String? = nil,
        onVideoDeleted: ((String) -> Void)? = nil,
        onVideoRenamed: ((String, String) -> Void)? = nil
    ) {
        self.traineeId = traineeId
        self.embedded = embedded
        self.searchPlaceholder = searchPlaceholder
        self.inFlight = inFlight
        self.clientName = clientName
        self.onVideoDeleted = onVideoDeleted
        self.onVideoRenamed = onVideoRenamed
        _model = State(initialValue: VideoFeedModel(traineeId: traineeId))
    }

    private var isGlobal: Bool { traineeId == nil }
    private var groupOptions: [VideoFeedModel.GroupBy] {
        isGlobal ? [.none, .trainee, .month] : [.none, .month]
    }
    private var showTraineeColumn: Bool { isGlobal && model.groupBy != .trainee }

    /// In-flight recordings not yet present in the server feed (dedupe by id).
    private var pendingInFlight: [ClientVideo] {
        inFlight.filter { cv in !model.rows.contains { $0.id == cv.id } }
    }
    private var inFlightToken: [String] { inFlight.map { "\($0.id):\($0.isProcessing)" } }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                ScrollView { content }
                    .refreshable { await model.reload() }
            }
        }
        .task { await model.loadInitial() }
        .onChange(of: inFlightToken) { _, _ in
            Task { await model.reload() }
        }
        .sheet(item: $selected) { item in
            VideoDetailSheet(
                item: item,
                onDelete: {
                    model.remove(id: item.id)
                    onVideoDeleted?(item.id)
                    await store.deleteVideo(id: item.id, clientId: traineeId)
                },
                onSaved: { title, desc in
                    model.applyEdit(id: item.id, title: title, description: desc)
                    onVideoRenamed?(item.id, title)
                }
            )
            .environment(store)
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            if !embedded { header }
            searchBar
            groupControl

            if model.rows.isEmpty && pendingInFlight.isEmpty {
                if model.isLoading {
                    ProgressView().tint(Color.neonCyan).scaleEffect(1.2)
                        .padding(.vertical, 60)
                } else {
                    emptyState
                }
            } else {
                LazyVStack(spacing: 0) {
                    inFlightRows
                    tableHeader
                    feedRows
                    if model.isLoading && !model.rows.isEmpty {
                        ProgressView().tint(Color.neonCyan).padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: Header / search / group

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Videos").font(.display(28)).foregroundStyle(.white)
                Text(model.hasMore ? "\(model.rows.count)+ recordings" : "\(model.rows.count) recordings")
                    .font(.mono(12)).foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.3))
            TextField(searchPlaceholder,
                      text: Binding(get: { model.search }, set: { model.search = $0 }))
                .font(.body(14)).foregroundStyle(.white).tint(Color.neonPink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    private var groupControl: some View {
        HStack(spacing: 8) {
            Text("GROUP")
                .font(.mono(11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.35)).tracking(1)
            HStack(spacing: 0) {
                ForEach(groupOptions, id: \.self) { g in
                    let active = model.groupBy == g
                    Button { model.setGroupBy(g) } label: {
                        Text(groupOptionLabel(g))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(active ? Color.neonPink : Color.white.opacity(0.5))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(active ? Color.neonPink.opacity(0.16) : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private func groupOptionLabel(_ g: VideoFeedModel.GroupBy) -> String {
        switch g {
        case .none: "None"
        case .trainee: "Trainee"
        case .month: "Uploaded On"
        }
    }

    // MARK: Table

    private var tableHeader: some View {
        HStack(spacing: 10) {
            sortHeaderCell(.name, label: "Name", flexible: true)
            if showTraineeColumn {
                sortHeaderCell(.trainee, label: "Trainee", width: 84)
            }
            sortHeaderCell(.date, icon: "square.and.arrow.up", width: 74, trailing: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(hex: "0a0817"))
        .overlay(Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1),
                 alignment: .bottom)
    }

    @ViewBuilder
    private func sortHeaderCell(
        _ key: VideoFeedModel.SortKey,
        label: String? = nil,
        icon: String? = nil,
        width: CGFloat? = nil,
        flexible: Bool = false,
        trailing: Bool = false
    ) -> some View {
        let active = model.sortKey == key
        let tint = active ? Color.neonPink : Color.white.opacity(0.55)
        Button { model.setSort(key) } label: {
            HStack(spacing: 4) {
                if trailing { Spacer(minLength: 0) }
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                } else if let label {
                    Text(label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                if active {
                    Image(systemName: sortDirIcon).font(.system(size: 7))
                }
                if !trailing && !flexible { Spacer(minLength: 0) }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: flexible ? .infinity : nil,
                   alignment: trailing ? .trailing : .leading)
            .frame(width: width)
        }
        .buttonStyle(.plain)
    }

    private var sortDirIcon: String {
        model.sortDir == .asc ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
    }

    @ViewBuilder private var inFlightRows: some View {
        ForEach(pendingInFlight) { cv in
            VideoTableRow(
                id: cv.id, title: cv.title, fileURL: cv.url,
                traineeName: nil, traineeColorIndex: 0,
                dateText: shortDate(cv.createdAt), showTrainee: showTraineeColumn,
                isProcessing: cv.isProcessing
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !cv.isProcessing else { return }
                selected = VideoFeedItem(
                    from: cv,
                    clientId: traineeId ?? "",
                    clientName: clientName ?? "",
                    uploaderName: store.currentUser?.name ?? "",
                    uploaderId: store.currentUser?.id ?? ""
                )
            }
        }
    }

    @ViewBuilder private var feedRows: some View {
        ForEach(Array(model.rows.enumerated()), id: \.element.id) { idx, item in
            if model.groupBy != .none && isGroupStart(idx) {
                groupHeader(item)
            }
            VideoTableRow(
                id: item.id, title: item.title, fileURL: item.fileURL,
                traineeName: item.traineeName, traineeColorIndex: item.traineeColorIndex,
                dateText: rowDate(item), showTrainee: showTraineeColumn
            )
            .background(idx.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onTapGesture { selected = item }
            .onAppear {
                if item.id == model.rows.last?.id {
                    Task { await model.loadMore() }
                }
            }
        }
    }

    private func isGroupStart(_ idx: Int) -> Bool {
        guard idx > 0 else { return true }
        return model.rows[idx].groupKey != model.rows[idx - 1].groupKey
    }

    private func groupHeader(_ item: VideoFeedItem) -> some View {
        HStack(spacing: 9) {
            if model.groupBy == .trainee {
                Circle().fill(paletteColor(item.traineeColorIndex).text)
                    .frame(width: 9, height: 9)
            }
            Text(item.groupLabel ?? "").font(.body(13, weight: .bold)).foregroundStyle(.white)
            if let c = item.groupCount {
                Text("\(c)").font(.mono(11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
        }
        .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 6)
    }

    private func rowDate(_ item: VideoFeedItem) -> String {
        guard let d = item.createdAt else { return "—" }
        return (model.groupBy == .month ? vidShortDateFmt : vidFullDateFmt).string(from: d)
    }

    private func shortDate(_ d: Date?) -> String {
        guard let d else { return "" }
        return (model.groupBy == .month ? vidShortDateFmt : vidFullDateFmt).string(from: d)
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "video.slash",
            title: model.search.isEmpty ? "No videos yet" : "No videos match your search",
            subtitle: model.search.isEmpty
                ? (isGlobal ? "Record a client session to see it here" : "Hit \"New\" to start a session")
                : "Try a different search",
            bordered: true
        )
        .padding(.horizontal, 16).padding(.top, 20)
    }
}

private let vidShortDateFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MM/dd"; return f
}()
private let vidFullDateFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MM/dd/yyyy"; return f
}()

// MARK: - Video Table Row

/// One row in the Video Library table: a thin 9:16 poster, title, optional trainee
/// cell, and a date. Column widths match `VideosView.tableHeader`.
struct VideoTableRow: View {
    let id: String
    let title: String
    let fileURL: URL?
    let traineeName: String?
    let traineeColorIndex: Int
    let dateText: String
    let showTrainee: Bool
    var isProcessing: Bool = false

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                poster
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showTrainee {
                HStack(spacing: 6) {
                    Circle().fill(paletteColor(traineeColorIndex).text)
                        .frame(width: 7, height: 7)
                    Text(traineeName ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(width: 84, alignment: .leading)
            }

            Text(dateText)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .task(id: fileURL) { await loadThumbnail() }
    }

    private var poster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: "0d0710"))
            if let thumb = thumbnail {
                Image(uiImage: thumb).resizable().aspectRatio(contentMode: .fill)
            }
            if isProcessing {
                ProgressView().tint(Color.neonCyan).scaleEffect(0.6)
            } else {
                Circle().fill(.black.opacity(0.35))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 7)).foregroundStyle(.white)
                    )
            }
        }
        .frame(width: 30, height: 53)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func loadThumbnail() async {
        if let cached = ThumbnailCache.shared.get(id) { thumbnail = cached; return }
        guard let url = fileURL else { return }
        if let img = await generateThumbnail(from: url, size: CGSize(width: 120, height: 214)) {
            ThumbnailCache.shared.set(img, for: id)
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
    /// Reflects the title live after an in-sheet edit (the owning list updates
    /// separately via `onSaved`).
    @State private var liveTitle: String = ""

    private var canDelete: Bool {
        guard let roles = store.currentUser?.roles else { return false }
        return roles.contains("admin") || roles.contains("trainer_admin")
    }
    private var displayTitle: String {
        liveTitle.isEmpty ? item.title : liveTitle
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
        .onAppear {
            if liveTitle.isEmpty { liveTitle = item.title }
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
        if success {
            liveTitle = trimmedTitle
            onSaved?(trimmedTitle, desc.isEmpty ? nil : desc)
        }
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

