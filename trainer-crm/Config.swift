import Foundation

enum Config {
    #if DEBUG
    static let apiBaseURL = "https://perform.tbd.fit"
    #else
    static let apiBaseURL = "https://perform.tbd.fit"
    #endif
}
