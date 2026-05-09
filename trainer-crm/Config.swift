import Foundation

enum Config {
    #if DEBUG
    static let apiBaseURL = "https://trainer-crm-six.vercel.app"
    #else
    static let apiBaseURL = "https://trainer-crm-six.vercel.app"
    #endif
}
