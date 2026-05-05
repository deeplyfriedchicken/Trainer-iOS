import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedTab: AppTab = .clients
    @State private var toastMessage: String? = nil
    @State private var toastStyle: ToastNotification.Style = .error
    @State private var toastTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBg.ignoresSafeArea()

            // Ambient glow
            GeometryReader { geo in
                ZStack {
                    RadialGradient(colors: [Color.neonPink.opacity(0.08), .clear],
                                   center: .init(x: 0.2, y: 0.1),
                                   startRadius: 0, endRadius: geo.size.width * 0.8)
                    RadialGradient(colors: [Color.neonCyan.opacity(0.07), .clear],
                                   center: .init(x: 0.8, y: 0.9),
                                   startRadius: 0, endRadius: geo.size.width * 0.7)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Tab content
            Group {
                switch selectedTab {
                case .clients:  ClientsView()
                case .videos:   VideosView()
                case .trainers: TrainersView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 84)

            // Custom tab bar
            AppTabBar(selected: $selectedTab)

            // Toast notifications
            VStack(spacing: 0) {
                if let message = toastMessage {
                    ToastNotification(message: message, style: toastStyle) { dismissToast() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(toastMessage != nil)
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: store.error) { _, error in
            guard let error else { return }
            showToast(error.errorDescription ?? "Network error", style: .error)
            store.error = nil
        }
        .onChange(of: store.refreshMessage) { _, msg in
            guard let msg else { return }
            showToast(msg, style: .success)
            store.refreshMessage = nil
        }
    }

    private func showToast(_ message: String, style: ToastNotification.Style) {
        toastTask?.cancel()
        toastStyle = style
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            toastMessage = message
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    private func dismissToast() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            toastMessage = nil
        }
        toastTask?.cancel()
    }
}

// MARK: - Tab Bar

enum AppTab { case clients, videos, trainers }

struct AppTabBar: View {
    @Binding var selected: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
            HStack(spacing: 0) {
                TabBarItem(icon: "person.2.fill",      label: "Clients",  tab: .clients,  selected: $selected)
                TabBarItem(icon: "play.rectangle.fill", label: "Videos",   tab: .videos,   selected: $selected)
                TabBarItem(icon: "star.fill",           label: "Trainers", tab: .trainers, selected: $selected)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .frame(height: 83)
            .background(.ultraThinMaterial)
        }
    }
}

struct TabBarItem: View {
    let icon: String
    let label: String
    let tab: AppTab
    @Binding var selected: AppTab

    private var isActive: Bool { selected == tab }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selected = tab }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.neonPink.opacity(0.15))
                            .frame(width: 36, height: 28)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.neonPink : Color.white.opacity(0.4))
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? Color.neonPink : Color.white.opacity(0.4))
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
