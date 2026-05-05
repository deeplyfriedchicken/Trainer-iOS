import Foundation

enum Config {
    #if DEBUG
    static let apiBaseURL = "https://trainer-crm-six.vercel.app"
    #else
    static let apiBaseURL = "https://trainer-crm-six.vercel.app"
    #endif

    static let clientPortalBaseURL = "https://trainer-crm-six.vercel.app"

    // 64-char hex string — sourced from Secrets.swift (gitignored)
    static let clientTokenSecret = Secrets.clientTokenSecret
}
