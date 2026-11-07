import Foundation
import Combine

struct UserProfile: Codable {
    var schemaVersion = "1.0"
    var profileId: String
    var createdAt: Date
    var updatedAt: Date
    var displayName: String? = nil
    var settings: ProfileSettings
    var folders: [WordFolder] = []
    var wordStates: [ProfileWordState] = []
    var activityDays: [ActivityDay] = []
    var statsSnapshot: ProfileStats

    static func fresh() -> UserProfile {
        let now = Date()
        return UserProfile(
            profileId: UUID().uuidString.lowercased(),
            createdAt: now,
            updatedAt: now,
            settings: ProfileSettings(),
            statsSnapshot: ProfileStats(calculatedAt: now)
        )
    }
}

struct ProfileSettings: Codable {
    var uiLanguage = "de"
    var learningLanguages = ["en"]
    var defaultExplanationLanguage = "de"
    var dailyStreakGoal = 5
    var timeZone = TimeZone.current.identifier
}

struct WordFolder: Codable, Identifiable, Hashable {
    var folderId: String
    var name: String
    var parentFolderId: String?
    var createdAt: Date
    var sortOrder: Int

    var id: String { folderId }

    private enum CodingKeys: String, CodingKey {
        case folderId, name, parentFolderId, createdAt, sortOrder
    }

    init(folderId: String, name: String, parentFolderId: String?, createdAt: Date, sortOrder: Int) {
        self.folderId = folderId
        self.name = name
        self.parentFolderId = parentFolderId
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderId = try container.decode(String.self, forKey: .folderId)
        name = try container.decode(String.self, forKey: .name)
        parentFolderId = try container.decodeIfPresent(String.self, forKey: .parentFolderId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folderId, forKey: .folderId)
        try container.encode(name, forKey: .name)
        try container.encode(parentFolderId, forKey: .parentFolderId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

struct ProfileWordState: Codable, Identifiable {
    var lemmaId: String
    var senseId: String
    var favorite = false
    var savedAt: Date? = nil
    var savedInFolderIds: [String] = []
    var quiz: QuizMetadata = QuizMetadata()
    var progress: WordProgress = WordProgress()

    var id: String { senseId }
    var isSaved: Bool { savedAt != nil || !savedInFolderIds.isEmpty }
}

struct QuizMetadata: Codable {
    var enabled = false
    var categories: [String] = []
    var difficulty: Int? = 3
}

struct WordProgress: Codable {
    var correct = 0
    var incorrect = 0
    var attempts = 0
    var lastPracticedAt: Date? = nil
    var dueAt: Date? = nil
    var box = 0
}

struct ActivityDay: Codable, Identifiable {
    var date: String
    var practiceCount: Int
    var correctCount: Int
    var incorrectCount: Int
    var uniqueSenseIds: [String]

    var id: String { date }
}

struct ProfileStats: Codable {
    var calculatedAt: Date
    var savedLemmaCount = 0
    var savedSenseCount = 0
    var favoriteLemmaCount = 0
    var favoriteSenseCount = 0
    var quizLemmaCount = 0
    var quizSenseCount = 0
    var currentStreakDays = 0
    var longestStreakDays = 0
    var totalActiveDays = 0
    var uniqueSensesPracticed = 0
    var totalPracticeCount = 0
    var totalCorrectCount = 0
    var totalIncorrectCount = 0
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: UserProfile
    @Published private(set) var accountEmail: String?
    @Published private(set) var syncStatus = "Nur lokal auf diesem Gerät"
    @Published private(set) var isSyncing = false
    @Published var apiServerURL: String

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var accessToken: String? = SessionTokenStore.read()
    private var remoteRevision: Int?
    private var syncTask: Task<Void, Never>?
    private var suppressRemoteSync = false

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WordExpress", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("profile.json")
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        apiServerURL = UserDefaults.standard.string(forKey: "wordExpressAPIURL") ?? "http://127.0.0.1:8080"
        accountEmail = UserDefaults.standard.string(forKey: "wordExpressAccountEmail")
        if let data = try? Data(contentsOf: fileURL), let saved = try? decoder.decode(UserProfile.self, from: data) {
            profile = saved
        } else {
            profile = .fresh()
        }
        refreshStats()
        persistLocalOnly()
        if accessToken != nil {
            Task { await synchronize(preferLocalIfNewer: true) }
        }
    }

    func setAPIServerURL(_ value: String) {
        apiServerURL = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        UserDefaults.standard.set(apiServerURL, forKey: "wordExpressAPIURL")
        if accessToken != nil { Task { await synchronize(preferLocalIfNewer: true) } }
    }

    func registerAccount(email: String, password: String, inviteCode: String) async throws {
        let client = try WordExpressAPIClient(serverURL: apiServerURL)
        let session = try await client.register(email: email, password: password, inviteCode: inviteCode)
        store(session)
        remoteRevision = 0
        do {
            try await uploadLocalProfile(using: client, token: session.accessToken, revision: 0)
        } catch {
            syncStatus = "Konto angelegt; Synchronisierung wartet auf Verbindung."
            throw error
        }
    }

    func login(email: String, password: String) async throws {
        let client = try WordExpressAPIClient(serverURL: apiServerURL)
        let session = try await client.login(email: email, password: password)
        store(session)
        await synchronize(preferLocalIfNewer: false)
    }

    func signOut() {
        let oldToken = accessToken
        syncTask?.cancel()
        clearLocalSession()
        if let oldToken, let client = try? WordExpressAPIClient(serverURL: apiServerURL) {
            Task { try? await client.logout(token: oldToken) }
        }
    }

    func deleteAccount(password: String) async throws {
        guard let accessToken else { return }
        let client = try WordExpressAPIClient(serverURL: apiServerURL)
        try await client.deleteAccount(token: accessToken, password: password)
        syncTask?.cancel()
        clearLocalSession()
        profile = .fresh()
        try? FileManager.default.removeItem(at: fileURL)
        persistLocalOnly()
    }

    func synchronizeNow() async {
        await synchronize(preferLocalIfNewer: true)
    }

    private func store(_ session: AccountSessionResponse) {
        accessToken = session.accessToken
        accountEmail = session.email
        SessionTokenStore.write(session.accessToken)
        UserDefaults.standard.set(session.email, forKey: "wordExpressAccountEmail")
    }

    private func clearLocalSession() {
        accessToken = nil
        remoteRevision = nil
        accountEmail = nil
        SessionTokenStore.write(nil)
        UserDefaults.standard.removeObject(forKey: "wordExpressAccountEmail")
        syncStatus = "Nur lokal auf diesem Gerät"
    }

    private func synchronize(preferLocalIfNewer: Bool) async {
        guard let token = accessToken else { return }
        do {
            let client = try WordExpressAPIClient(serverURL: apiServerURL)
            isSyncing = true
            syncStatus = "Synchronisierung läuft …"
            let startingLocalUpdate = profile.updatedAt
            if let remote = try await client.getProfile(token: token) {
                remoteRevision = remote.revision
                let localChangedDuringRequest = profile.updatedAt > startingLocalUpdate
                if localChangedDuringRequest {
                    scheduleRemoteSync()
                } else if preferLocalIfNewer && profile.updatedAt > remote.profile.updatedAt {
                    try await uploadLocalProfile(using: client, token: token, revision: remote.revision)
                } else {
                    applyRemoteProfile(remote.profile)
                    syncStatus = "Mit der Cloud synchronisiert"
                }
            } else {
                remoteRevision = 0
                try await uploadLocalProfile(using: client, token: token, revision: 0)
            }
            isSyncing = false
        } catch {
            isSyncing = false
            syncStatus = "Lokal gespeichert · Cloud-Sync fehlgeschlagen"
        }
    }

    private func uploadLocalProfile(using client: WordExpressAPIClient, token: String, revision: Int) async throws {
        profile.updatedAt = Date()
        refreshStats()
        let snapshot = profile
        let data = try encoder.encode(snapshot)
        let response = try await client.putProfile(data, token: token, revision: revision)
        remoteRevision = response.revision
        if profile.updatedAt == snapshot.updatedAt {
            profile.updatedAt = response.profile.updatedAt
            refreshStats()
            persistLocalOnly()
        }
        syncStatus = "Mit der Cloud synchronisiert"
    }

    private func applyRemoteProfile(_ remote: UserProfile) {
        suppressRemoteSync = true
        profile = remote
        refreshStats()
        persistLocalOnly()
        suppressRemoteSync = false
    }

    private func scheduleRemoteSync() {
        guard accessToken != nil, !suppressRemoteSync else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await synchronize(preferLocalIfNewer: true)
        }
    }

    func wordState(for senseId: String, lemmaId: String) -> ProfileWordState {
        profile.wordStates.first(where: { $0.senseId == senseId }) ?? ProfileWordState(lemmaId: lemmaId, senseId: senseId)
    }

    func toggleFavorite(senseId: String, lemmaId: String) {
        updateWord(senseId: senseId, lemmaId: lemmaId) { $0.favorite.toggle() }
    }

    func toggleQuiz(senseId: String, lemmaId: String) {
        updateWord(senseId: senseId, lemmaId: lemmaId) { $0.quiz.enabled.toggle() }
    }

    func setDifficulty(_ difficulty: Int, senseId: String, lemmaId: String) {
        updateWord(senseId: senseId, lemmaId: lemmaId) { $0.quiz.difficulty = difficulty }
    }

    func setCategories(_ categories: [String], senseId: String, lemmaId: String) {
        updateWord(senseId: senseId, lemmaId: lemmaId) { $0.quiz.categories = Array(Set(categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted() }
    }

    func updateLanguageSettings(learning: Language, explanation: Language) {
        profile.settings.learningLanguages = Array(Set(profile.settings.learningLanguages + [learning.rawValue])).sorted()
        profile.settings.defaultExplanationLanguage = explanation.rawValue
        persist()
    }

    func toggleFolder(_ folder: WordFolder, senseId: String, lemmaId: String) {
        updateWord(senseId: senseId, lemmaId: lemmaId) { state in
            if state.savedInFolderIds.contains(folder.folderId) {
                state.savedInFolderIds.removeAll { $0 == folder.folderId }
            } else {
                state.savedInFolderIds.append(folder.folderId)
            }
            state.savedAt = state.savedInFolderIds.isEmpty ? nil : (state.savedAt ?? Date())
        }
    }

    func createFolder(name: String, parentId: String?) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        profile.folders.append(WordFolder(
            folderId: UUID().uuidString.lowercased(),
            name: cleanName,
            parentFolderId: parentId,
            createdAt: Date(),
            sortOrder: profile.folders.filter { $0.parentFolderId == parentId }.count
        ))
        persist()
    }

    func recordPractice(senseId: String, lemmaId: String, correct: Bool) {
        updateWord(senseId: senseId, lemmaId: lemmaId) { state in
            state.progress.attempts += 1
            state.progress.lastPracticedAt = Date()
            if correct {
                state.progress.correct += 1
                state.progress.box = min(5, state.progress.box + 1)
                let intervals = [1, 3, 7, 14, 30]
                let interval = intervals[max(0, min(4, state.progress.box - 1))]
                state.progress.dueAt = Calendar.current.date(byAdding: .day, value: interval, to: Date())
            } else {
                state.progress.incorrect += 1
                state.progress.box = 1
                state.progress.dueAt = Date()
            }
        }
        let today = localDateString(Date())
        if let index = profile.activityDays.firstIndex(where: { $0.date == today }) {
            profile.activityDays[index].practiceCount += 1
            if correct { profile.activityDays[index].correctCount += 1 } else { profile.activityDays[index].incorrectCount += 1 }
            if !profile.activityDays[index].uniqueSenseIds.contains(senseId) { profile.activityDays[index].uniqueSenseIds.append(senseId) }
        } else {
            profile.activityDays.append(ActivityDay(date: today, practiceCount: 1, correctCount: correct ? 1 : 0, incorrectCount: correct ? 0 : 1, uniqueSenseIds: [senseId]))
        }
        persist()
    }

    func quizCandidates(from content: ContentStore) -> [(LemmaEntry, Sense)] {
        let enabled = Set(profile.wordStates.filter { $0.quiz.enabled }.map(\.senseId))
        return content.entries.flatMap { entry in entry.senses.filter { enabled.contains($0.id) }.map { (entry, $0) } }
    }

    private func updateWord(senseId: String, lemmaId: String, change: (inout ProfileWordState) -> Void) {
        let index: Int
        if let existing = profile.wordStates.firstIndex(where: { $0.senseId == senseId }) {
            index = existing
        } else {
            profile.wordStates.append(ProfileWordState(lemmaId: lemmaId, senseId: senseId))
            index = profile.wordStates.count - 1
        }
        change(&profile.wordStates[index])
        persist()
    }

    private func persist() {
        profile.updatedAt = Date()
        refreshStats()
        persistLocalOnly()
        scheduleRemoteSync()
    }

    private func persistLocalOnly() {
        do {
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Could not save profile: \(error.localizedDescription)")
        }
    }

    private func refreshStats() {
        let saved = profile.wordStates.filter(\.isSaved)
        let favorites = profile.wordStates.filter(\.favorite)
        let quiz = profile.wordStates.filter { $0.quiz.enabled }
        let days = profile.activityDays
        let streakDays = Set(days.filter { $0.practiceCount >= profile.settings.dailyStreakGoal }.map(\.date))
        profile.statsSnapshot = ProfileStats(
            calculatedAt: Date(),
            savedLemmaCount: Set(saved.map(\.lemmaId)).count,
            savedSenseCount: saved.count,
            favoriteLemmaCount: Set(favorites.map(\.lemmaId)).count,
            favoriteSenseCount: favorites.count,
            quizLemmaCount: Set(quiz.map(\.lemmaId)).count,
            quizSenseCount: quiz.count,
            currentStreakDays: streakEndingAtTodayOrYesterday(streakDays),
            longestStreakDays: longestStreak(in: streakDays),
            totalActiveDays: days.count,
            uniqueSensesPracticed: Set(days.flatMap(\.uniqueSenseIds)).count,
            totalPracticeCount: days.reduce(0) { $0 + $1.practiceCount },
            totalCorrectCount: days.reduce(0) { $0 + $1.correctCount },
            totalIncorrectCount: days.reduce(0) { $0 + $1.incorrectCount }
        )
    }

    private func streakEndingAtTodayOrYesterday(_ active: Set<String>) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: profile.settings.timeZone) ?? .current
        let today = calendar.startOfDay(for: Date())
        let todayString = localDateString(today, timeZone: calendar.timeZone)
        let startingDay = active.contains(todayString) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var result = 0
        var cursor = startingDay
        while active.contains(localDateString(cursor, timeZone: calendar.timeZone)) {
            result += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return result
    }

    private func longestStreak(in active: Set<String>) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: profile.settings.timeZone) ?? .current
        let dates = active.compactMap { dateFromString($0) }.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for date in dates {
            if let previous, calendar.dateComponents([.day], from: previous, to: date).day == 1 { run += 1 }
            else { run = 1 }
            best = max(best, run)
            previous = date
        }
        return best
    }

    private func localDateString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dateFromString(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: profile.settings.timeZone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
