import Foundation

enum AppConfiguration {
    static let apiBaseURL: URL = {
#if DEBUG
        // Nur in Entwicklungs-Builds: ein lokales Backend, z. B. LERNKARTEN_API_BASE_URL=http://localhost:8080
        if let override = ProcessInfo.processInfo.environment["LERNKARTEN_API_BASE_URL"], let url = URL(string: override) { return url }
#endif
        return URL(string: "https://cardexpress-production.up.railway.app")!
    }()
}
