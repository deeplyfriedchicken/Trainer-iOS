import SwiftUI

@main
struct TrainerCRMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .task { await store.checkAuth() }
                .onReceive(NotificationCenter.default.publisher(for: .apiUnauthorized)) { _ in
                    store.signOut()
                }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.isAuthenticated)
    }
}
