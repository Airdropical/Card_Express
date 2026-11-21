import SwiftUI
// APPLE-DEVELOPER: Für „Mit Apple anmelden“ (braucht den bezahlten Apple-Developer-Account).
// import AuthenticationServices
// import CryptoKit

// Alle Stellen, die erst mit dem bezahlten Apple-Developer-Account funktionieren, sind mit
// „APPLE-DEVELOPER“ markiert und auskommentiert. Bis dahin meldet man sich mit E-Mail und Passwort an.

struct SettingsView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingLogin = false
    @State private var confirmingClear = false
    @State private var confirmingAccountDeletion = false
    @State private var isAuthenticated = LearningAPI.shared.hasSession
    @State private var account: AccountOverview?
    // APPLE-DEVELOPER: @State private var appleNonce = ""
    @State private var isWorking = false
    @State private var accountError: String?
    @State private var remindersEnabled = TestReminders.isEnabled
    @State private var aiEnabled = AIConsent.isGranted
    @State private var askingAIConsent = false
    @State private var remindersDenied = false

    var body: some View {
        NavigationStack {
            Form {
                if isAuthenticated { accountSection } else { signInSection }
                Section(store.t("Anwendung")) {
                    Picker(store.t("Sprache"), selection: Binding(get: { store.language }, set: { store.language = $0 })) { Text(store.t("Deutsch")).tag("Deutsch"); Text(store.t("English")).tag("Englisch") }
                    Picker(store.t("Erscheinungsbild"), selection: Binding(get: { store.appearance }, set: { value in withAnimation(.easeInOut(duration: 0.35)) { store.appearance = value } })) { Text(store.t("Hell")).tag("Hell"); Text(store.t("Dunkel")).tag("Dunkel"); Text(store.t("System")).tag("System") }
                    Stepper(store.tf("Karten pro Sitzung: %d", store.sessionSize), value: Binding(get: { store.sessionSize }, set: { store.sessionSize = $0 }), in: 5...100, step: 5)
                    Toggle(store.t("Zufällige Lernreihenfolge"), isOn: Binding(get: { store.randomOrder }, set: { store.randomOrder = $0 }))
                    Toggle(store.t("KI-Evaluierung vorauswählen"), isOn: Binding(get: { store.aiEvaluation }, set: { store.aiEvaluation = $0 }))
                }
                Section {
                    Toggle(store.t("Test-Erinnerungen"), isOn: Binding(get: { remindersEnabled }, set: { value in Task { await setReminders(value) } }))
                    if remindersDenied {
                        Text(store.t("Mitteilungen sind für diese App ausgeschaltet. Erlaube sie in den iOS-Einstellungen unter „Lernkarten“."))
                            .font(.footnote).foregroundStyle(Palette.red)
                    }
                } footer: {
                    Text(store.t("Du bekommst eine Mitteilung, wenn ein Test zu einem Termin mit Deck bereitsteht oder genug schwere Karten für einen Tagestest da sind."))
                }
                Section(store.t("Rechtliches")) {
                    Link(store.t("Datenschutzerklärung"), destination: AppConfiguration.apiBaseURL.appending(path: "privacy"))
                    Link(store.t("Nutzungsbedingungen"), destination: AppConfiguration.apiBaseURL.appending(path: "terms"))
                    Link(store.t("Impressum"), destination: AppConfiguration.apiBaseURL.appending(path: "imprint"))
                }
                Section {
                    Button(store.t("Daten auf diesem Gerät löschen"), role: .destructive) { confirmingClear = true }
                } header: {
                    Text(store.t("Lokale Daten"))
                } footer: {
                    Text(store.t(isAuthenticated
                        ? "Deine Lerndaten liegen auf diesem Gerät und in deinem Konto. Löschen entfernt sie an beiden Orten."
                        : "Ohne Anmeldung bleiben Decks, Vokabeln und Termine nur auf diesem Gerät."))
                }
            }.navigationTitle(store.t("Einstellungen"))
                .confirmationDialog(store.t("Alle Daten löschen?"), isPresented: $confirmingClear, titleVisibility: .visible) {
                    Button(store.t("Alles unwiderruflich löschen"), role: .destructive) { store.clearAllData() }
                    Button(store.t("Abbrechen"), role: .cancel) {}
                } message: {
                    Text(store.t(isAuthenticated
                        ? "Alle Decks, Karten, Vokabeln, Termine und dein Lernfortschritt werden von diesem Gerät und aus deinem Konto entfernt. Das lässt sich nicht rückgängig machen."
                        : "Alle Decks, Karten, Vokabeln, Termine und dein Lernfortschritt werden von diesem Gerät entfernt. Das lässt sich nicht rückgängig machen."))
                }
                .confirmationDialog(store.t("Konto löschen?"), isPresented: $confirmingAccountDeletion, titleVisibility: .visible) {
                    Button(store.t("Konto unwiderruflich löschen"), role: .destructive) { Task { await deleteAccount() } }
                    Button(store.t("Abbrechen"), role: .cancel) {}
                } message: {
                    Text(store.t("Dein Konto, die in der Cloud gespeicherten Lerndaten und die Nutzungszähler werden vom Server gelöscht. Die Daten auf diesem Gerät bleiben erhalten."))
                }
                .task(id: isAuthenticated) { await loadAccount() }
                .alert(store.t("KI-Funktionen aktivieren?"), isPresented: $askingAIConsent) {
                    Button(store.t("Zustimmen und aktivieren")) { aiEnabled = true; AIConsent.isGranted = true }
                    Button(store.t("Nicht jetzt"), role: .cancel) { aiEnabled = false; AIConsent.isGranted = false }
                } message: {
                    Text(store.t("Wenn du KI-Funktionen nutzt, werden die dafür gewählten Inhalte – Texte, Karten, Fotos, PDFs und der Gesprächsverlauf – über unseren Server an Google (Gemini) übertragen und dort verarbeitet. Sende keine vertraulichen oder fremden personenbezogenen Daten. Du kannst die Zustimmung jederzeit hier widerrufen."))
                }
                .sheet(isPresented: $showingLogin, onDismiss: { signedIn() }) { PilotLoginView() }
        }
        // A sheet has its own presentation host. Propagate the selected scheme
        // here as well so an already-open settings sheet updates immediately.
        .preferredColorScheme(store.appearance == "Hell" ? .light : store.appearance == "Dunkel" ? .dark : nil)
        .animation(.easeInOut(duration: 0.35), value: store.appearance)
    }

    // MARK: Konto

    private var signInSection: some View {
        Section {
            // APPLE-DEVELOPER: Anmeldung mit Apple; ersetzt später den E-Mail-Knopf darunter.
            // SignInWithAppleButton(.signIn) { request in
            //     // Der Server prüft, dass das Token zu genau dieser Anfrage gehört.
            //     appleNonce = UUID().uuidString + UUID().uuidString
            //     request.requestedScopes = [.email]
            //     request.nonce = SHA256.hash(data: Data(appleNonce.utf8)).map { String(format: "%02x", $0) }.joined()
            // } onCompletion: { result in
            //     Task { await finishAppleSignIn(result) }
            // }
            // .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            // .frame(height: 48)
            // .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            // .disabled(isWorking)
            Button(store.t("Anmelden")) { showingLogin = true }.disabled(isWorking)
            if let accountError { Text(accountError).font(.footnote).foregroundStyle(Palette.red) }
        } header: {
            Text(store.t("Konto"))
        } footer: {
            Text(store.t("Mit einem Konto werden deine Lerndaten gesichert und zwischen deinen Geräten abgeglichen. Die KI-Funktionen aktivierst du danach gesondert. Mit der Anmeldung akzeptierst du die Nutzungsbedingungen und die Datenschutzerklärung."))
        }
    }

    private var accountSection: some View {
        Section {
            if let email = account?.email { LabeledContent(store.t("Angemeldet als"), value: email) }
            else { LabeledContent(store.t("Status"), value: store.t("Angemeldet")) }
            Toggle(store.t("KI-Funktionen"), isOn: Binding(get: { aiEnabled }, set: { value in
                // Einschalten nur über die ausdrückliche Zustimmung, Ausschalten sofort.
                if value { askingAIConsent = true } else { aiEnabled = false; AIConsent.isGranted = false }
            }))
            if aiEnabled, let ai = account?.ai {
                LabeledContent(store.t("KI-Anfragen (24 Stunden)"), value: ai.unlimited ? store.t("Unbegrenzt") : "\(ai.usedToday) / \(ai.dailyLimit)")
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.t("Synchronisierung"))
                    Text(syncStatusText).font(.caption).foregroundStyle(syncFailed ? Palette.red : Palette.muted)
                }
                Spacer()
                if store.syncState == .syncing { ProgressView() }
                else { Button(store.t("Jetzt abgleichen")) { Task { await store.sync() } }.buttonStyle(.borderless) }
            }
            if let accountError { Text(accountError).font(.footnote).foregroundStyle(Palette.red) }
            Button(store.t("Abmelden")) { Task { await signOut() } }.disabled(isWorking)
            Button(store.t("Konto löschen"), role: .destructive) { confirmingAccountDeletion = true }.disabled(isWorking)
        } header: {
            Text(store.t("Konto"))
        } footer: {
            Text(store.t("Für KI-Funktionen werden die von dir gewählten Inhalte (Texte, Karten, Fotos, Gesprächsverlauf) über unseren Server an Google Gemini übertragen. Abgleich und Lernen funktionieren auch ohne."))
        }
    }

    private var syncFailed: Bool { if case .failed = store.syncState { true } else { false } }

    private var syncStatusText: String {
        switch store.syncState {
        case .syncing: return store.t("Wird abgeglichen …")
        case .failed(let message): return message
        case .idle:
            guard let date = store.lastSyncedAt else { return store.t("Noch nicht abgeglichen") }
            return store.t("Zuletzt abgeglichen:") + " " + date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    // APPLE-DEVELOPER: Abschluss der Anmeldung mit Apple.
    // @MainActor private func finishAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
    //     accountError = nil
    //     switch result {
    //     case .failure(let error):
    //         // Abbrechen ist kein Fehler.
    //         if (error as? ASAuthorizationError)?.code == .canceled { return }
    //         accountError = store.t("Die Anmeldung mit Apple hat nicht geklappt. Bitte versuche es erneut.")
    //     case .success(let authorization):
    //         guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
    //               let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
    //             accountError = store.t("Die Anmeldung mit Apple hat nicht geklappt. Bitte versuche es erneut.")
    //             return
    //         }
    //         isWorking = true
    //         defer { isWorking = false }
    //         do {
    //             try await LearningAPI.shared.signInWithApple(identityToken: token, nonce: appleNonce, authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) })
    //             signedIn()
    //         } catch {
    //             accountError = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
    //         }
    //     }
    // }

    private func signedIn() {
        isAuthenticated = LearningAPI.shared.hasSession
        guard isAuthenticated else { return }
        // Direkt nach der ersten Anmeldung einmal ausdrücklich fragen.
        if !AIConsent.wasAsked { askingAIConsent = true }
        Task { await store.sync() }
    }

    @MainActor private func setReminders(_ enabled: Bool) async {
        remindersDenied = false
        if enabled, !(await TestReminders.requestPermission()) {
            remindersDenied = true
            remindersEnabled = false
            TestReminders.isEnabled = false
            return
        }
        remindersEnabled = enabled
        TestReminders.isEnabled = enabled
        // APPLE-DEVELOPER: Server-Push. Bis dahin plant die App die Erinnerungen selbst auf dem Gerät.
        // if enabled { TestReminders.registerForPushIfWanted() } else { await TestReminders.unregisterDevice() }
        await TestReminders.reschedule(store: store)
    }

    @MainActor private func loadAccount() async {
        isAuthenticated = LearningAPI.shared.hasSession
        guard isAuthenticated else { account = nil; return }
        account = try? await LearningAPI.shared.accountOverview()
        // APPLE-DEVELOPER: Server-Push.
        // if let account {
        //     // Sendet das Backend Push, plant die App keine eigenen Erinnerungen mehr.
        //     TestReminders.serverSendsPush = account.serverPush ?? false
        //     TestReminders.registerForPushIfWanted()
        // }
        // Eine inzwischen abgelaufene Sitzung meldet der Aufruf selbst ab.
        isAuthenticated = LearningAPI.shared.hasSession
    }

    @MainActor private func signOut() async {
        isWorking = true
        defer { isWorking = false }
        // Offene Änderungen noch hochladen, damit beim nächsten Anmelden nichts fehlt.
        await store.sync()
        await TestReminders.unregisterDevice()
        await LearningAPI.shared.logout()
        store.forgetSyncState()
        account = nil
        accountError = nil
        isAuthenticated = false
    }

    @MainActor private func deleteAccount() async {
        isWorking = true
        accountError = nil
        defer { isWorking = false }
        do {
            try await LearningAPI.shared.deleteAccount()
            store.forgetSyncState()
            account = nil
            isAuthenticated = false
        } catch {
            accountError = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
        }
    }
}

/// Anmeldung mit E-Mail und Passwort; neue Konten brauchen den Einladungscode aus Railway.
/// APPLE-DEVELOPER: Mit dem bezahlten Account wird sie wieder auf Entwicklungs-Builds beschränkt (`#if DEBUG`).
private struct PilotLoginView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var creatingAccount = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Privatpilot-Konto")) {
                    TextField(store.t("E-Mail"), text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(store.t("Passwort"), text: $password).textContentType(.password)
                    if creatingAccount {
                        SecureField(store.t("Einladungscode"), text: $inviteCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text(store.t("Das Passwort muss mindestens 12 Zeichen lang sein. Der Einladungscode ist in Railway gesetzt."))
                            .font(.footnote).foregroundStyle(Palette.muted)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView() } else { Text(store.t(creatingAccount ? "Konto erstellen" : "Anmelden")) }
                        Spacer()
                    }
                }
                .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || (creatingAccount && inviteCode.isEmpty))
                Button(store.t(creatingAccount ? "Ich habe schon ein Konto" : "Konto mit Einladungscode erstellen")) {
                    creatingAccount.toggle()
                    errorMessage = nil
                }
                .disabled(isWorking)
            }
            .navigationTitle(store.t("Privatpilot-Anmeldung"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Abbrechen")) { dismiss() } } }
        }
        .preferredColorScheme(store.appearance == "Hell" ? .light : store.appearance == "Dunkel" ? .dark : nil)
    }

    @MainActor
    private func signIn() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            if creatingAccount {
                try await LearningAPI.shared.register(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, inviteCode: inviteCode)
            } else {
                try await LearningAPI.shared.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            }
            dismiss()
        } catch {
            errorMessage = LearningAPI.shared.userFacingMessage(for: error, language: store.language)
        }
    }
}
