import Foundation
import Security

struct AccountSessionResponse: Decodable {
    let accessToken: String
    let email: String
    private enum CodingKeys: String, CodingKey { case accessToken = "access_token", email }
}

struct RemoteProfileResponse: Decodable {
    let profile: UserProfile
    let revision: Int
}

enum AccountAPIError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "Bitte gib eine gültige HTTPS-Adresse für den Server an."
        case .invalidResponse: return "Der Server hat eine ungültige Antwort gesendet."
        case .server(let message): return message
        }
    }
}

struct WordExpressAPIClient {
    let baseURL: URL

    init(serverURL: String) throws {
        let value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host?.lowercased() ?? "")),
              url.host != nil, url.user == nil, url.password == nil else { throw AccountAPIError.invalidServerURL }
        baseURL = url
    }

    func register(email: String, password: String, inviteCode: String) async throws -> AccountSessionResponse {
        try await send(path: "/api/v1/auth/register", method: "POST", body: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password,
            "invite_code": inviteCode
        ], response: AccountSessionResponse.self)
    }

    func login(email: String, password: String) async throws -> AccountSessionResponse {
        try await send(path: "/api/v1/auth/login", method: "POST", body: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password
        ], response: AccountSessionResponse.self)
    }

    func getProfile(token: String) async throws -> RemoteProfileResponse? {
        let request = try makeRequest(path: "/api/v1/profile", method: "GET", token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        if http.statusCode == 404 { return nil }
        try check(http, data: data)
        return try decoder.decode(RemoteProfileResponse.self, from: data)
    }

    func putProfile(_ data: Data, token: String, revision: Int) async throws -> RemoteProfileResponse {
        var request = try makeRequest(path: "/api/v1/profile", method: "PUT", token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(revision)\"", forHTTPHeaderField: "If-Match")
        request.httpBody = data
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        try check(http, data: responseData)
        return try decoder.decode(RemoteProfileResponse.self, from: responseData)
    }

    func deleteAccount(token: String, password: String) async throws {
        var request = try makeRequest(path: "/api/v1/account", method: "DELETE", token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        if !(200...299).contains(http.statusCode) { throw AccountAPIError.server("Konto konnte nicht gelöscht werden (HTTP \(http.statusCode)).") }
    }

    func logout(token: String) async throws {
        let request = try makeRequest(path: "/api/v1/auth/logout", method: "POST", token: token)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        if !(200...299).contains(http.statusCode) { throw AccountAPIError.server("Abmeldung konnte nicht bestätigt werden (HTTP \(http.statusCode)).") }
    }

    private func send<T: Decodable>(path: String, method: String, body: [String: String], response: T.Type) async throws -> T {
        var request = try makeRequest(path: path, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else { throw AccountAPIError.invalidResponse }
        try check(http, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func makeRequest(path: String, method: String, token: String? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw AccountAPIError.invalidServerURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.keyDecodingStrategy = .convertFromSnakeCase
        value.dateDecodingStrategy = .iso8601
        return value
    }

    private func check(_ response: HTTPURLResponse, data: Data) throws {
        guard (200...299).contains(response.statusCode) else {
            let payload = (try? JSONDecoder().decode([String: String].self, from: data))
            throw AccountAPIError.server(payload?["detail"] ?? "Anfrage fehlgeschlagen (HTTP \(response.statusCode)).")
        }
    }
}

enum SessionTokenStore {
    private static let service = "de.wordexpress.account"
    private static let account = "access-token"

    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
