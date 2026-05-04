import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var isAuthenticating = false
    @State private var errorMessage: String? = nil

    // Must match the base URL used in APIClient
    private let authURL = URL(string: "\(ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:3000")/api/auth/google?mobile=1")!
    private let callbackScheme = "trainer-crm"

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            // Ambient glow
            GeometryReader { geo in
                ZStack {
                    RadialGradient(colors: [Color.neonPink.opacity(0.12), .clear],
                                   center: .init(x: 0.25, y: 0.2),
                                   startRadius: 0, endRadius: geo.size.width * 0.9)
                    RadialGradient(colors: [Color.neonCyan.opacity(0.08), .clear],
                                   center: .init(x: 0.75, y: 0.8),
                                   startRadius: 0, endRadius: geo.size.width * 0.7)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Spacer()

                // Logo / brand
                VStack(spacing: 20) {
                    Image("TBDLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding(24)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 32))
                        .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color.white.opacity(0.08), lineWidth: 1))

                    Text("Coach smarter. Train harder.")
                        .font(.mono(13))
                        .foregroundStyle(Color.white.opacity(0.4))
                }

                Spacer()

                // Sign in button
                VStack(spacing: 16) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.body(13))
                            .foregroundStyle(Color.neonRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Button(action: signIn) {
                        HStack(spacing: 12) {
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 20))
                            }
                            Text(isAuthenticating ? "Signing in…" : "Sign in with Google")
                                .font(.body(16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.neonPink, Color(hex: "e855a0")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color.neonPink.opacity(0.4), radius: 16, y: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAuthenticating)

                    Text("Access is restricted to registered trainers.")
                        .font(.body(12))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
    }

    private func signIn() {
        isAuthenticating = true
        errorMessage = nil

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { callbackURL, error in
            isAuthenticating = false

            if let error {
                if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    errorMessage = "Authentication failed. Please try again."
                }
                return
            }

            guard let url = callbackURL,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let token = components.queryItems?.first(where: { $0.name == "token" })?.value
            else {
                if let errCode = callbackURL
                    .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) })?
                    .queryItems?.first(where: { $0.name == "error" })?.value {
                    errorMessage = authErrorMessage(errCode)
                } else {
                    errorMessage = "Sign-in failed. Please try again."
                }
                return
            }

            KeychainStore.save(token)
            Task { await store.loadInitialData() }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = PresentationContextProvider.shared
        session.start()
    }

    private func authErrorMessage(_ code: String) -> String {
        switch code {
        case "not_found":    return "No account found for this Google email."
        case "unauthorized": return "Your account doesn't have trainer access."
        default:             return "Sign-in failed (\(code)). Please try again."
        }
    }
}

// MARK: - Presentation context

final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationContextProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = windowScenes.first else { fatalError("No UIWindowScene available") }
        return scene.keyWindow ?? UIWindow(windowScene: scene)
    }
}
