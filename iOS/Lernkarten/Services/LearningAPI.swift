import Foundation
import Security

enum LearningAPIError: LocalizedError {
    case message(String)
    /// Antwort des Backends mit Fehlerstatus. `authenticated` unterscheidet eine abgelaufene
    /// Sitzung (401 bei einer KI-Anfrage) von falschen Zugangsdaten (401 beim Anmelden).
    case http(status: Int, detail: String, authenticated: Bool)
    case notSignedIn
    /// Angemeldet, aber der Weitergabe von Inhalten an den KI-Anbieter wurde nicht zugestimmt.
    case aiConsentMissing
    case tokenNotSaved

    var errorDescription: String? {
        switch self {
        case let .message(text): text
        case let .http(_, detail, _): detail
        case .notSignedIn: "Nicht angemeldet."
        case .aiConsentMissing: "KI-Funktionen sind nicht aktiviert."
        case .tokenNotSaved: "Die Anmeldung konnte nicht gespeichert werden."
        }
    }
}

final class LearningAPI {
    static let shared = LearningAPI()
    private let tokenService = "de.codex.lernkarten.pilot"
    /// Zwischenspeicher, damit nicht jede Anfrage und jede Statusabfrage den Schlüsselbund liest.
    private var cachedToken: String?
    private var tokenLoaded = false
    private let tokenLock = NSLock()
    private init() {}

    func userFacingMessage(for error: Error, language: String) -> String {
        let english = language == "Englisch"
        if let apiError = error as? LearningAPIError {
            switch apiError {
            case .notSignedIn:
                return english ? "Sign in under Settings to use the AI features." : "Melde dich in den Einstellungen an, um die KI-Funktionen zu nutzen."
            case .aiConsentMissing:
                return english ? "Turn on the AI features under Settings to use them." : "Aktiviere die KI-Funktionen in den Einstellungen, um sie zu nutzen."
            case .tokenNotSaved:
                return english ? "The sign-in couldn't be stored on this device. Please try again." : "Die Anmeldung konnte auf diesem Gerät nicht gespeichert werden. Bitte versuche es erneut."
            case let .http(status, detail, authenticated):
                if let text = Self.message(status: status, detail: detail.lowercased(), authenticated: authenticated, english: english) { return text }
            case .message:
                break
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return english ? "The service is unavailable right now. Please try again later." : "Der Dienst ist gerade nicht verfügbar. Bitte versuche es später erneut."
            case .timedOut:
                return english ? "The service is taking longer than expected. Please try again later." : "Der Dienst braucht gerade zu lange. Bitte versuche es später erneut."
            case .cancelled:
                return english ? "The request was canceled." : "Die Anfrage wurde abgebrochen."
            default:
                return english ? "The learning service couldn't be reached. Please try again." : "Der Lerndienst konnte nicht erreicht werden. Bitte versuche es erneut."
            }
        }
        let detail = (error as? LearningAPIError)?.errorDescription ?? error.localizedDescription
        let value = detail.lowercased()
        if value.contains("zu viele seiten") {
            return english ? "The PDF has more than 250 pages. Use a shorter document." : "Das PDF hat mehr als 250 Seiten. Verwende ein kürzeres Dokument."
        }
        if value.contains("text im pdf") {
            return english ? "The PDF contains too much text. Use a shorter document." : "Das PDF enthält zu viel Text. Verwende ein kürzeres Dokument."
        }
        if value.contains("kein auswählbarer text") {
            return english ? "This PDF has no selectable text. Use the photo import for scanned pages." : "Dieses PDF enthält keinen auswählbaren Text. Nutze für gescannte Seiten den Foto-Import."
        }
        if value.contains("20 mb") {
            return english ? "The PDF exceeds the 20 MB size limit. Choose a smaller file." : "Das PDF überschreitet das Größenlimit von 20 MB. Wähle eine kleinere Datei."
        }
        if value.contains("413") || value.contains("too large") || value.contains("zu groß") {
            return english ? "The file is too large. Choose a smaller file and try again." : "Die Datei ist zu groß. Wähle eine kleinere Datei und versuche es erneut."
        }
        if value.contains("pdf") || value.contains("datei") || value.contains("file") {
            return english ? "The selected file couldn't be read. Choose a valid PDF or image and try again." : "Die ausgewählte Datei konnte nicht gelesen werden. Wähle ein gültiges PDF oder Bild und versuche es erneut."
        }
        if value.contains("401") || value.contains("unauthorized") {
            return english ? "Sign-in failed. Check your email and password, then try again." : "Die Anmeldung ist fehlgeschlagen. Prüfe E-Mail-Adresse und Passwort und versuche es erneut."
        }
        if value.contains("403") || value.contains("forbidden") {
            return english ? "This action isn't allowed for this account." : "Diese Aktion ist für dieses Konto nicht freigegeben."
        }
        if value.contains("429") || value.contains("limit reached") || value.contains("budget reached") {
            return english ? "The AI request limit has been reached. Please try again later." : "Das KI-Anfragelimit ist erreicht. Bitte versuche es später erneut."
        }
        if value.contains("not configured") || value.contains("api key") {
            return english ? "The AI service isn't configured yet. Contact the app administrator." : "Der KI-Dienst ist noch nicht eingerichtet. Bitte wende dich an den App-Administrator."
        }
        if value.contains("500") || value.contains("502") || value.contains("503") || value.contains("504") || value.contains("temporarily unavailable") || value.contains("could not be reached") {
            return english ? "The service is unavailable right now. Please try again later." : "Der Dienst ist gerade nicht verfügbar. Bitte versuche es später erneut."
        }
        if error is DecodingError {
            return english ? "The server returned an unreadable response. Please try again later." : "Der Server hat eine nicht lesbare Antwort gesendet. Bitte versuche es später erneut."
        }
        return english ? "That didn't work right now. Please try again later." : "Das hat gerade nicht geklappt. Bitte versuche es später erneut."
    }

    private static func message(status: Int, detail: String, authenticated: Bool, english: Bool) -> String? {
        switch status {
        case 401:
            return authenticated
                ? (english ? "Your session has expired. Sign in again under Settings." : "Deine Sitzung ist abgelaufen. Melde dich in den Einstellungen erneut an.")
                : (english ? "Sign-in failed. Check your email and password, then try again." : "Die Anmeldung ist fehlgeschlagen. Prüfe E-Mail-Adresse und Passwort und versuche es erneut.")
        case 403:
            return detail.contains("invitation")
                ? (english ? "The invitation code is not valid." : "Der Einladungscode ist nicht gültig.")
                : (english ? "This action isn't allowed for this account." : "Diese Aktion ist für dieses Konto nicht freigegeben.")
        case 409 where authenticated:
            return english ? "Your data was changed on another device. Please sync again." : "Deine Daten wurden auf einem anderen Gerät geändert. Bitte synchronisiere erneut."
        case 409:
            return english ? "An account with this email already exists." : "Für diese E-Mail-Adresse gibt es bereits ein Konto."
        case 413:
            return english ? "The file is too large. Choose a smaller file and try again." : "Die Datei ist zu groß. Wähle eine kleinere Datei und versuche es erneut."
        case 422:
            return english ? "The input wasn't accepted. It may be too long or incomplete." : "Die Eingabe wurde nicht angenommen. Sie ist möglicherweise zu lang oder unvollständig."
        case 429:
            if detail.contains("capacity") { return english ? "The AI is at capacity for today. Try again tomorrow." : "Die KI ist für heute ausgelastet. Versuche es morgen erneut." }
            if detail.contains("daily") { return english ? "Today's AI request limit has been reached. Try again tomorrow." : "Das heutige KI-Anfragelimit ist erreicht. Versuche es morgen erneut." }
            if detail.contains("budget") || detail.contains("pilot") { return english ? "The AI budget for this account is used up." : "Das KI-Budget für dieses Konto ist aufgebraucht." }
            return english ? "Too many requests. Wait a moment and try again." : "Zu viele Anfragen. Warte einen Moment und versuche es erneut."
        case 502 where detail.contains("cut off"):
            return english ? "The AI answer was too long. Ask for fewer cards or entries." : "Die KI-Antwort war zu lang. Fordere weniger Karten oder Einträge an."
        case 502 where detail.contains("did not create"):
            return english ? "The AI didn't create all requested cards. Please try again." : "Die KI hat nicht alle gewünschten Karten erstellt. Bitte versuche es erneut."
        case 503 where detail.contains("api_key") || detail.contains("not configured"):
            return english ? "The AI service isn't configured yet. Contact the app administrator." : "Der KI-Dienst ist noch nicht eingerichtet. Bitte wende dich an den App-Administrator."
        case 500...599:
            return english ? "The service is unavailable right now. Please try again later." : "Der Dienst ist gerade nicht verfügbar. Bitte versuche es später erneut."
        default:
            return nil
        }
    }

    var hasSession: Bool { loadToken() != nil }

    /// KI-Funktionen brauchen ein Konto und die ausdrückliche Zustimmung, Inhalte an den KI-Anbieter zu senden.
    var canUseAI: Bool { hasSession && AIConsent.isGranted }

    private func requireAI() throws {
        guard hasSession else { throw LearningAPIError.notSignedIn }
        guard AIConsent.isGranted else { throw LearningAPIError.aiConsentMissing }
    }

    private func post<T: Decodable, Body: Encodable>(_ route: String, body: Body, authenticated: Bool = true) async throws -> T {
        let data = try await send("POST", route, body: try JSONEncoder().encode(body), authenticated: authenticated)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Eine Anfrage an das Backend. Liefert den Antwortkörper oder wirft bei jedem Fehlerstatus.
    private func send(_ method: String, _ route: String, body: Data? = nil, headers: [String: String] = [:], authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: AppConfiguration.apiBaseURL.appending(path: route))
        request.httpMethod = method
        request.timeoutInterval = 90
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if authenticated {
            // Ohne Sitzung gar nicht erst senden: Das Backend würde ohnehin mit 401 antworten.
            guard let token = loadToken() else { throw LearningAPIError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LearningAPIError.message("Keine gültige Antwort vom KI-Backend.") }
        guard (200..<300).contains(http.statusCode) else {
#if DEBUG
            print("[LearningAPI] \(route) failed: HTTP \(http.statusCode)")
#endif
            // Abgelaufene oder widerrufene Sitzung: Token verwerfen, damit die App nicht „angemeldet“ bleibt.
            if http.statusCode == 401, authenticated { deleteToken() }
            let payload = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw LearningAPIError.http(status: http.statusCode, detail: payload?.detail ?? payload?.error ?? "", authenticated: authenticated)
        }
        return data
    }

    // MARK: Konto

    /// Tauscht die Apple-Anmeldung gegen eine Sitzung beim Backend.
    func signInWithApple(identityToken: String, nonce: String, authorizationCode: String?) async throws {
        struct Body: Encodable { let identityToken: String; let nonce: String; let authorizationCode: String? }
        struct Response: Decodable { let access_token: String }
        let response: Response = try await post("api/v1/auth/apple", body: Body(identityToken: identityToken, nonce: nonce, authorizationCode: authorizationCode), authenticated: false)
        try saveToken(response.access_token)
    }

    func accountOverview() async throws -> AccountOverview {
        try JSONDecoder().decode(AccountOverview.self, from: try await send("GET", "api/v1/account"))
    }

    /// Löscht Konto, Cloud-Daten und Nutzungszähler auf dem Server und beendet die Sitzung.
    func deleteAccount() async throws {
        _ = try await send("DELETE", "api/v1/account")
        deleteToken()
    }

    // MARK: Mathe

    func mathProfile() async throws -> MathProfile {
        try JSONDecoder().decode(MathProfile.self, from: try await send("GET", "api/v1/math/profile"))
    }

    /// Eine neue Aufgabe. Ohne `difficulty` wählt das Backend sie passend zu den bisherigen Ergebnissen.
    func mathTask(topic: MathTopic, difficulty: Int?, language: String, recentQuestions: [String]) async throws -> MathTask {
        try requireAI()
        struct Body: Encodable { let level: String; let topic: String; let topicName: String; let difficulty: Int?; let language: String; let recentQuestions: [String] }
        return try await post("api/v1/math/task", body: Body(level: topic.level.rawValue, topic: topic.id, topicName: topic.name, difficulty: difficulty, language: language, recentQuestions: Array(recentQuestions.suffix(5))))
    }

    func mathCheck(topic: MathTopic, task: MathTask, steps: [String], answer: String, language: String) async throws -> MathCheckResult {
        try requireAI()
        struct Body: Encodable { let level: String; let topic: String; let topicName: String; let difficulty: Int; let question: String; let referenceSteps: [String]; let referenceAnswer: String; let steps: [String]; let answer: String; let language: String }
        return try await post("api/v1/math/check", body: Body(level: topic.level.rawValue, topic: topic.id, topicName: topic.name, difficulty: task.difficulty, question: task.question, referenceSteps: task.solutionSteps, referenceAnswer: task.finalAnswer, steps: steps, answer: answer, language: language))
    }

    // MARK: Tests und Mitteilungen

    /// Der eigene Kalendertag des Geräts als JJJJ-MM-TT.
    static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Lässt den Tutor einen Test schreiben. Das Backend prüft zuerst, ob er fällig ist und genug Material da ist,
    /// und liefert denselben Test für den Rest des Tages aus dem Speicher.
    func dailyTest(for offer: DailyTestOffer) async throws -> [CardDraft] {
        try requireAI()
        struct Card: Encodable { let question: String; let answer: String; let lapses: Int; let hardCount: Int; let lastRating: String? }
        struct Body: Encodable { let kind: String; let reference: String; let localDay: String; let examDay: String?; let title: String; let cards: [Card] }
        struct Response: Decodable { let questions: [CardDraft] }
        let cards = offer.cards.prefix(400).map { Card(question: String($0.question.prefix(600)), answer: String($0.answer.prefix(1200)), lapses: $0.lapses ?? 0, hardCount: $0.hardCount ?? 0, lastRating: $0.lastRating?.rawValue) }
        let body = Body(kind: offer.kind.rawValue, reference: offer.reference, localDay: Self.dayString(Date()), examDay: offer.examDate.map(Self.dayString), title: String(offer.title.prefix(120)), cards: Array(cards))
        let response: Response = try await post("api/v1/tests", body: body)
        return response.questions
    }

    func registerDevice(token: String, sandbox: Bool, language: String) async throws {
        struct Body: Encodable { let token: String; let environment: String; let language: String }
        _ = try await send("PUT", "api/v1/devices", body: try JSONEncoder().encode(Body(token: token, environment: sandbox ? "sandbox" : "production", language: language)))
    }

    func removeDevice(token: String) async {
        struct Body: Encodable { let token: String }
        _ = try? await send("DELETE", "api/v1/devices", body: try? JSONEncoder().encode(Body(token: token)))
    }

    // MARK: Synchronisierung

    /// Der Cloud-Stand mit seiner Revision; `snapshot` ist nil, solange noch kein Gerät hochgeladen hat.
    func fetchSnapshot() async throws -> (snapshot: CloudSnapshot?, revision: Int) {
        struct Response: Decodable { let profile: CloudSnapshot?; let revision: Int }
        let response = try JSONDecoder().decode(Response.self, from: try await send("GET", "api/v1/profile"))
        return (response.profile, response.revision)
    }

    /// Lädt den Stand hoch, sofern die Cloud noch auf `revision` steht (sonst Status 409). Liefert die neue Revision.
    func pushSnapshot(_ snapshot: CloudSnapshot, revision: Int) async throws -> Int {
        struct Body: Encodable { let profile: CloudSnapshot }
        struct Response: Decodable { let revision: Int }
        let data = try await send("PUT", "api/v1/profile", body: try JSONEncoder().encode(Body(profile: snapshot)), headers: ["If-Match": "\"\(revision)\""])
        return try JSONDecoder().decode(Response.self, from: data).revision
    }

    func login(email: String, password: String) async throws {
        struct Body: Encodable { let email: String; let password: String }
        struct Response: Decodable { let access_token: String }
        let response: Response = try await post("api/v1/auth/login", body: Body(email: email, password: password), authenticated: false)
        try saveToken(response.access_token)
    }

    func register(email: String, password: String, inviteCode: String) async throws {
        struct Body: Encodable {
            let email: String
            let password: String
            let invite_code: String
        }
        struct Response: Decodable { let access_token: String }
        let response: Response = try await post("api/v1/auth/register", body: Body(email: email, password: password, invite_code: inviteCode), authenticated: false)
        try saveToken(response.access_token)
    }

    func logout() async {
        struct Empty: Encodable {}
        struct Result: Decodable { let ok: Bool }
        if hasSession { let _: Result? = try? await post("api/v1/auth/logout", body: Empty()) }
        deleteToken()
    }

    private func loadToken() -> String? {
        tokenLock.lock(); defer { tokenLock.unlock() }
#if DEBUG
        // Nur in Entwicklungs-Builds: eine vorgegebene Sitzung für automatisierte Tests gegen ein lokales Backend.
        if !tokenLoaded, let token = ProcessInfo.processInfo.environment["LERNKARTEN_TEST_TOKEN"], !token.isEmpty {
            cachedToken = token
            tokenLoaded = true
        }
#endif
        if tokenLoaded { return cachedToken }
        cachedToken = readTokenFromKeychain()
        tokenLoaded = true
        return cachedToken
    }

    private func readTokenFromKeychain() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: tokenService, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    private func saveToken(_ token: String) throws {
        deleteToken()
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: tokenService, kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LearningAPIError.tokenNotSaved }
        tokenLock.lock(); cachedToken = token; tokenLoaded = true; tokenLock.unlock()
    }

    private func deleteToken() {
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: tokenService]
        SecItemDelete(item as CFDictionary)
        tokenLock.lock(); cachedToken = nil; tokenLoaded = true; tokenLock.unlock()
    }

    func generate(text: String?, image: Data?, mimeType: String, language: String, style: String, instructions: String) async throws -> GeneratedCards {
        try requireAI()
        let body = GenerateBody(text: text, imageBase64: image?.base64EncodedString(), mimeType: mimeType, language: language, style: style, instructions: instructions)
        return try await post("api/generate-cards", body: body)
    }

    func evaluate(question: String, expected: String, answer: String, language: String, mode: String) async throws -> Evaluation {
        try requireAI()
        return try await post("api/evaluate", body: EvaluateBody(question: question, expected: expected, answer: answer, language: language, mode: mode))
    }

    func tutor(question: String, answer: String, message: String, history: [TutorMessage], language: String, mode: String = "chat", sourceLanguage: String = "German", targetLanguage: String = "English", attachment: TutorAttachmentPayload? = nil) async throws -> TutorReply {
        try requireAI()
        let serializedHistory = history.suffix(10).map {
            TutorHistoryBody(role: $0.role, text: String($0.text.prefix(1000)))
        }
        let body = TutorBody(question: question, answer: answer, message: message, history: serializedHistory, language: language, mode: mode, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, imageBase64: attachment?.imageBase64, mimeType: attachment?.imageBase64 == nil ? nil : "image/jpeg", documentText: attachment?.documentText, documentName: attachment?.documentText == nil ? nil : attachment?.name)
#if DEBUG
        let historyCharacters = serializedHistory.reduce(0) { $0 + $1.text.count }
        let requestBytes = (try? JSONEncoder().encode(body).count) ?? 0
        print("[LearningAPI] tutor mode=\(mode) context_chars=\(answer.count) history_messages=\(serializedHistory.count) history_chars=\(historyCharacters) latest_chars=\(message.count) request_bytes=\(requestBytes)")
#endif
        return try await post("api/tutor", body: body)
    }

    func planTutorActions(message: String, decks: [String], language: String, mode: String, sourceLanguage: String, targetLanguage: String, vocabularyFolders: [String], calendarEntries: [String] = [], excludeTerms: [String] = [], termSubjects: [String] = [], attachment: TutorAttachmentPayload? = nil) async throws -> TutorAgentPlan {
        try requireAI()
        struct Body: Encodable {
            let message: String
            let decks: [String]
            let language: String
            let mode: String
            let sourceLanguage: String
            let targetLanguage: String
            let vocabularyFolders: [String]
            let calendarEntries: [String]
            let today: String
            let excludeTerms: [String]
            let termSubjects: [String]
            // Optionale Felder werden nur gesendet, wenn etwas angehängt ist.
            let imageBase64: String?
            let mimeType: String?
            let documentText: String?
            let documentName: String?
        }
        return try await post("api/agent-plan", body: Body(message: message, decks: decks, language: language, mode: mode, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, vocabularyFolders: vocabularyFolders, calendarEntries: Array(calendarEntries.prefix(100)), today: Self.dayString(Date()), excludeTerms: Array(excludeTerms.prefix(1000)), termSubjects: Array(termSubjects.prefix(100)), imageBase64: attachment?.imageBase64, mimeType: attachment?.imageBase64 == nil ? nil : "image/jpeg", documentText: attachment?.documentText, documentName: attachment?.documentText == nil ? nil : attachment?.name))
    }

    func summarize(cards: [Flashcard], language: String) async throws -> DeckSummary {
        try requireAI()
        return try await post("api/summary", body: SummaryBody(cards: cards.map { SummaryCard(question: $0.question, answer: $0.answer) }, language: language))
    }
}

private struct ErrorBody: Decodable { var error: String?; var detail: String? }
private struct GenerateBody: Encodable { var text: String?; var imageBase64: String?; var mimeType: String; var language: String; var style: String; var instructions: String }
private struct SummaryBody: Encodable { var cards: [SummaryCard]; var language: String }
private struct SummaryCard: Encodable { var question: String; var answer: String }
private struct EvaluateBody: Encodable { var question: String; var expected: String; var answer: String; var language: String; var mode: String }
private struct TutorHistoryBody: Encodable { var role: String; var text: String }
private struct TutorBody: Encodable { var question: String; var answer: String; var message: String; var history: [TutorHistoryBody]; var language: String; var mode: String; var sourceLanguage: String; var targetLanguage: String; var imageBase64: String?; var mimeType: String?; var documentText: String?; var documentName: String? }
/// Material, das im Tutor an eine Nachricht angehängt ist: ein JPEG-Bild oder der Text eines PDFs.
struct TutorAttachmentPayload: Sendable { var name: String; var imageBase64: String? = nil; var documentText: String? = nil }
/// Die Zustimmung, für KI-Funktionen Inhalte an den KI-Anbieter (Google Gemini) zu übertragen. Pro Gerät gespeichert.
enum AIConsent {
    private static let grantedKey = "learncards.aiConsent.granted"
    private static let askedKey = "learncards.aiConsent.asked"

    static var isGranted: Bool {
        get { UserDefaults.standard.bool(forKey: grantedKey) }
        set { UserDefaults.standard.set(newValue, forKey: grantedKey); UserDefaults.standard.set(true, forKey: askedKey) }
    }

    /// false, solange der Nutzer noch nie gefragt wurde.
    static var wasAsked: Bool { UserDefaults.standard.bool(forKey: askedKey) }
}

struct MathTopicStanding: Decodable, Equatable {
    var attempts: Int
    var mastery: Double?
    /// strength, weakness, practising oder new
    var status: String
    var nextDifficulty: Int
}
struct MathProfile: Decodable { var topics: [String: MathTopicStanding] }
struct MathTask: Decodable, Equatable { var question: String; var hint: String; var solutionSteps: [String]; var finalAnswer: String; var difficulty: Int }
struct MathCheckResult: Decodable { var correct: Bool; var score: Double; var feedback: String; var firstErrorStep: Int; var topic: MathTopicStanding }

struct AccountOverview: Decodable {
    struct AI: Decodable { var usedToday: Int; var dailyLimit: Int; var unlimited: Bool }
    var email: String?
    var ai: AI
    /// „free“ oder später „plus“.
    var plan: String?
    /// true: Das Backend sendet die Test-Erinnerungen als Push; die App plant dann keine eigenen.
    var serverPush: Bool?
}
struct TutorReply: Decodable { var reply: String }
struct DeckSummary: Decodable { var summary: String }
