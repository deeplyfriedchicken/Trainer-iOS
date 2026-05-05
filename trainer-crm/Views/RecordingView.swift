import SwiftUI
import Combine
import Photos
@preconcurrency import AVFoundation

// MARK: - Recording View

struct RecordingView: View {
    private let client: Client
    let onVideoSaved: (ClientVideo, String) async throws -> Void
    let onExit: () -> Void

    @Environment(AppStore.self) private var store
    @StateObject private var camera = CameraManager()
    @State private var elapsed = 0
    @State private var isRecording = false
    @State private var snackbars: [UploadTask] = []
    @State private var timer: Timer? = nil
    @State private var videoName = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var activeClient: Client
    @State private var showClientPicker = false

    init(client: Client,
         onVideoSaved: @escaping (ClientVideo, String) async throws -> Void,
         onExit: @escaping () -> Void) {
        self.client = client
        self.onVideoSaved = onVideoSaved
        self.onExit = onExit
        self._activeClient = State(initialValue: client)
    }

    var body: some View {
        ZStack {
            // Camera preview or black fallback
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Grid overlay
            Canvas { ctx, size in
                let step: CGFloat = 60
                var x: CGFloat = 0
                while x < size.width {
                    ctx.stroke(Path { p in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) },
                               with: .color(Color.white.opacity(0.03)), lineWidth: 1)
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    ctx.stroke(Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) },
                               with: .color(Color.white.opacity(0.03)), lineWidth: 1)
                    y += step
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Focus corners
            FocusCorners(active: isRecording)

            // Snackbar stack
            VStack(spacing: 8) {
                ForEach(snackbars) { task in
                    UploadSnackbarView(task: task) { id in
                        withAnimation { snackbars.removeAll { $0.id == id } }
                    }
                }
                Spacer()
            }
            .padding(.top, 70)
            .padding(.horizontal, 16)

            // Tap-to-dismiss overlay when client picker is open
            if showClientPicker {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showClientPicker = false
                        }
                    }
            }

            // HUD
            VStack {
                HStack {
                    // Done button
                    Button(action: onExit) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .medium))
                            Text("Done")
                                .font(.body(12, weight: .medium))
                        }
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 5)
                        .background(.black.opacity(0.35))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Timer
                    Text(formatTime(elapsed))
                        .font(.mono(13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(.black.opacity(0.5))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .clipShape(Capsule())

                    Spacer()

                    // REC indicator
                    if isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.neonRed)
                                .frame(width: 8, height: 8)
                                .shadow(color: .neonRed, radius: 4)
                                .modifier(BlinkModifier())
                            Text("REC")
                                .font(.mono(12, weight: .bold))
                                .foregroundStyle(Color.neonRed)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.neonRed.opacity(0.15))
                        .overlay(Capsule().stroke(Color.neonRed.opacity(0.35), lineWidth: 1))
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 6) {
                            Circle().fill(Color.white.opacity(0.3)).frame(width: 6, height: 6)
                            Text("STOPPED").font(.mono(11)).foregroundStyle(Color.white.opacity(0.5))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                // Controls
                VStack(spacing: 14) {
                    // Client picker dropdown — above the button
                    if showClientPicker {
                        HStack {
                            Spacer()
                            ClientPickerView(
                                clients: store.clients,
                                activeClientId: activeClient.id,
                                onSelect: { c in
                                    activeClient = c
                                    videoName = makeDefaultName(for: c)
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        showClientPicker = false
                                    }
                                }
                            )
                        }
                        .padding(.horizontal, 20)
                        .transition(
                            .scale(scale: 0.9, anchor: .bottomTrailing)
                            .combined(with: .opacity)
                        )
                    }

                    HStack(spacing: 40) {
                        // Flip camera
                        Button { camera.flipCamera() } label: {
                            Image(systemName: "camera.rotate")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.white.opacity(isRecording ? 0.7 : 0.3))
                                .frame(width: 48, height: 48)
                                .background(Color.white.opacity(0.12))
                                .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isRecording)

                        // Record / Stop
                        if isRecording {
                            Button(action: stopRecording) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.12))
                                        .overlay(Circle().stroke(Color.white.opacity(0.60), lineWidth: 3))
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.neonRed)
                                        .shadow(color: Color.neonRed.opacity(0.6), radius: 8)
                                        .frame(width: 28, height: 28)
                                }
                                .frame(width: 72, height: 72)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: startRecording) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.10))
                                        .overlay(Circle().stroke(Color.white.opacity(0.50), lineWidth: 3))
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color.white.opacity(0.85))
                                }
                                .frame(width: 72, height: 72)
                            }
                            .buttonStyle(.plain)
                        }

                        // Client switcher — mirrors flip button
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showClientPicker.toggle()
                            }
                        } label: {
                            let palette = paletteColor(activeClient.colorIndex)
                            Text(activeClient.initials)
                                .font(.display(15, weight: .heavy))
                                .foregroundStyle(showClientPicker ? Color.neonPink : palette.text)
                                .frame(width: 48, height: 48)
                                .background(palette.bg)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(
                                    showClientPicker ? Color.neonPink.opacity(0.4) : Color.white.opacity(0.2),
                                    lineWidth: 1
                                ))
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.2), value: showClientPicker)
                    }

                    // Video name field
                    HStack(spacing: 10) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(isRecording ? 0.2 : 0.45))
                        TextField("Video name", text: $videoName)
                            .font(.body(15))
                            .foregroundStyle(.white)
                            .tint(.neonPink)
                            .focused($nameFieldFocused)
                            .disabled(isRecording)
                            .submitLabel(.done)
                            .onSubmit { nameFieldFocused = false }
                        if !videoName.isEmpty && !isRecording {
                            Button {
                                videoName = ""
                                nameFieldFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                nameFieldFocused ? Color.neonPink.opacity(0.55) : Color.white.opacity(0.13),
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
                    .animation(.easeInOut(duration: 0.15), value: videoName.isEmpty)
                    .opacity(isRecording ? 0.4 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isRecording)
                }
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 12 : 60)
                .animation(.easeOut(duration: 0.25), value: keyboardHeight)
            }
        }
        .onAppear {
            camera.requestPermissionsAndStart()
            videoName = makeDefaultName()
        }
        .onDisappear { camera.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notif in
            guard let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let duration = (notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            withAnimation(.easeOut(duration: duration)) { keyboardHeight = frame.height }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notif in
            let duration = (notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            withAnimation(.easeOut(duration: duration)) { keyboardHeight = 0 }
        }
    }

    // MARK: - Recording logic

    private func startRecording() {
        let nameForThisRecording = videoName
        camera.startRecording { url in
            DispatchQueue.main.async {
                let dur = formatTime(elapsed)
                let now = Date()
                let video = ClientVideo(
                    title: nameForThisRecording,
                    date: now.formatted(.dateTime.month(.abbreviated).day()),
                    duration: dur,
                    url: url,
                    createdAt: now
                )
                let uploadTask = UploadTask(duration: dur, videoURL: url)
                withAnimation { snackbars.insert(uploadTask, at: 0) }
                videoName = makeDefaultName()
                Task {
                    do {
                        try await onVideoSaved(video, activeClient.id)
                        uploadTask.phase = .done
                    } catch {
                        uploadTask.phase = .failed
                    }
                }
            }
        }
        elapsed = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in elapsed += 1 }
    }

    private func stopRecording() {
        timer?.invalidate(); timer = nil
        isRecording = false
        camera.stopRecording()
    }

    private func formatTime(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func makeDefaultName(for c: Client? = nil) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy 'on' hh:mm a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return "Session for \((c ?? activeClient).fullName) at \(f.string(from: Date()))"
    }
}

// MARK: - Focus Corners

struct FocusCorners: View {
    let active: Bool
    private let positions: [(CGFloat, CGFloat, [Edge])] = [
        (0.12, 0.18, [.top, .leading]),
        (0.88, 0.18, [.top, .trailing]),
        (0.12, 0.72, [.bottom, .leading]),
        (0.88, 0.72, [.bottom, .trailing]),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<4, id: \.self) { i in
                let (xRatio, yRatio, edges) = positions[i]
                CornerBracket(edges: edges)
                    .stroke(Color.neonCyan.opacity(active ? 0.6 : 0.2), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .position(x: geo.size.width * xRatio, y: geo.size.height * yRatio)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: active)
        .allowsHitTesting(false)
    }
}

struct CornerBracket: Shape {
    let edges: [Edge]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let len: CGFloat = 16
        if edges.contains(.top) && edges.contains(.leading) {
            p.move(to: .init(x: rect.minX, y: rect.minY + len))
            p.addLine(to: .init(x: rect.minX, y: rect.minY))
            p.addLine(to: .init(x: rect.minX + len, y: rect.minY))
        }
        if edges.contains(.top) && edges.contains(.trailing) {
            p.move(to: .init(x: rect.maxX - len, y: rect.minY))
            p.addLine(to: .init(x: rect.maxX, y: rect.minY))
            p.addLine(to: .init(x: rect.maxX, y: rect.minY + len))
        }
        if edges.contains(.bottom) && edges.contains(.leading) {
            p.move(to: .init(x: rect.minX, y: rect.maxY - len))
            p.addLine(to: .init(x: rect.minX, y: rect.maxY))
            p.addLine(to: .init(x: rect.minX + len, y: rect.maxY))
        }
        if edges.contains(.bottom) && edges.contains(.trailing) {
            p.move(to: .init(x: rect.maxX - len, y: rect.maxY))
            p.addLine(to: .init(x: rect.maxX, y: rect.maxY))
            p.addLine(to: .init(x: rect.maxX, y: rect.maxY - len))
        }
        return p
    }
}

// MARK: - Blink Modifier

struct BlinkModifier: ViewModifier {
    @State private var visible = true
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - Upload Snackbar

@Observable
final class UploadTask: Identifiable {
    enum Phase: Equatable { case uploading, done, failed }
    let id = UUID()
    let duration: String
    let videoURL: URL?
    var phase: Phase = .uploading

    init(duration: String, videoURL: URL?) {
        self.duration = duration
        self.videoURL = videoURL
    }
}

struct UploadSnackbarView: View {
    let task: UploadTask
    let onDismiss: (UUID) -> Void

    @State private var barWidth: CGFloat = 0.15
    @State private var visible = true

    private var isDone: Bool   { task.phase == .done }
    private var isFailed: Bool { task.phase == .failed }

    private var accentColor: Color { isFailed ? .neonRed : isDone ? .neonGreen : .neonCyan }
    private var iconName: String   { isFailed ? "xmark.circle" : isDone ? "checkmark" : "arrow.up.circle" }
    private var labelText: String  { isFailed ? "Upload failed" : isDone ? "Upload complete" : "Uploading…" }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(accentColor.opacity(0.35), lineWidth: 1))
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 32, height: 32)
            .animation(.easeInOut(duration: 0.4), value: task.phase)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(labelText)
                        .font(.body(13, weight: .semibold))
                        .foregroundStyle(isFailed ? Color.neonRed : .white)
                        .animation(.easeInOut, value: task.phase)
                    Spacer()
                    Text(task.duration)
                        .font(.mono(11))
                        .foregroundStyle(isDone ? Color.neonGreen : Color.white.opacity(0.4))
                        .animation(.easeInOut, value: task.phase)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [accentColor, accentColor.opacity(0.5)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * barWidth)
                            .shadow(color: accentColor.opacity(0.4), radius: 4)
                    }
                }
                .frame(height: 3)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(hex: "0c0c1c").opacity(0.88))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accentColor.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.97)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                barWidth = 0.65
            }
        }
        .onChange(of: task.phase) { _, phase in
            switch phase {
            case .done:
                withAnimation(.easeInOut(duration: 0.4)) { barWidth = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { dismiss() }
            case .failed:
                withAnimation(.easeInOut(duration: 0.3)) { barWidth = 0.25 }
            case .uploading:
                break
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.3)) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onDismiss(task.id) }
    }
}

// MARK: - Client Picker

private struct ClientPickerView: View {
    let clients: [Client]
    let activeClientId: String
    let onSelect: (Client) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("SAVE TO CLIENT")
                .font(.mono(10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            ForEach(clients) { c in
                let isActive = c.id == activeClientId
                Button { onSelect(c) } label: {
                    HStack(spacing: 10) {
                        AvatarView(initials: c.initials, colorIndex: c.colorIndex, size: 30, cornerRadius: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.fullName)
                                .font(.body(13, weight: .semibold))
                                .foregroundStyle(isActive ? Color.neonPink : .white)
                            Text(c.plan)
                                .font(.mono(10))
                                .foregroundStyle(Color.white.opacity(0.35))
                        }
                        Spacer()
                        if isActive {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.neonPink)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isActive ? Color.neonPink.opacity(0.08) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "0a0a1c").opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Camera Manager

@MainActor
final class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let objectWillChange = ObservableObjectPublisher()

    // nonisolated(unsafe) lets background queues configure AVFoundation without actor hops;
    // AVCaptureSession is designed to be configured from any thread.
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private var videoOutput = AVCaptureMovieFileOutput()
    private var currentPosition: AVCaptureDevice.Position = .back
    private var onFinished: ((URL) -> Void)?

    func requestPermissionsAndStart() {
        Task {
            let camOK = await AVCaptureDevice.requestAccess(for: .video)
            let micOK = await AVCaptureDevice.requestAccess(for: .audio)
            await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard camOK && micOK else { return }
            await buildSession(position: currentPosition)
        }
    }

    func stop() { session.stopRunning() }

    func flipCamera() {
        currentPosition = currentPosition == .back ? .front : .back
        Task { await buildSession(position: currentPosition) }
    }

    func startRecording(onFinished: @escaping (URL) -> Void) {
        self.onFinished = onFinished
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        videoOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() { videoOutput.stopRecording() }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo url: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        guard error == nil else { return }
        saveToCameraRoll(url)
        Task { @MainActor in self.onFinished?(url) }
    }

    nonisolated private func saveToCameraRoll(_ url: URL) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: - Private

    private func buildSession(position: AVCaptureDevice.Position) async {
        let captureSession = session
        let newOutput = await withCheckedContinuation { (cont: CheckedContinuation<AVCaptureMovieFileOutput, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.beginConfiguration()
                captureSession.inputs.forEach  { captureSession.removeInput($0) }
                captureSession.outputs.forEach { captureSession.removeOutput($0) }

                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                   let input = try? AVCaptureDeviceInput(device: device),
                   captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
                if let mic = AVCaptureDevice.default(for: .audio),
                   let micInput = try? AVCaptureDeviceInput(device: mic),
                   captureSession.canAddInput(micInput) {
                    captureSession.addInput(micInput)
                }
                let out = AVCaptureMovieFileOutput()
                if captureSession.canAddOutput(out) { captureSession.addOutput(out) }
                captureSession.commitConfiguration()
                if !captureSession.isRunning { captureSession.startRunning() }
                cont.resume(returning: out)
            }
        }
        videoOutput = newOutput
    }
}
