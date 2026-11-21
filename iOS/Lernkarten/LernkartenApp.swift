import SwiftUI
import UserNotifications

/// Nimmt die Geräte-Kennung für Push entgegen und zeigt Mitteilungen auch bei geöffneter App.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // APPLE-DEVELOPER: Geräte-Kennung für Server-Push (braucht den bezahlten Apple-Developer-Account).
    // func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    //     let language = UserDefaults.standard.string(forKey: "learncards.language") ?? "Deutsch"
    //     Task { await TestReminders.didReceive(deviceToken: deviceToken, language: language) }
    // }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct LernkartenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = LearningStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            MainTabsView().environment(store)
                .environment(\.locale, Locale(identifier: store.language == "Englisch" ? "en" : "de"))
                .preferredColorScheme(store.appearance == "Hell" ? .light : store.appearance == "Dunkel" ? .dark : nil)
                .animation(.easeInOut(duration: 0.35), value: store.appearance)
                .task { await store.sync() }
                .onChange(of: scenePhase) { _, phase in
                    // Beim Öffnen den Cloud-Stand holen, beim Verlassen offene Änderungen hochladen.
                    if phase == .active { store.refreshDueItems() }
                    if phase == .active || phase == .background { Task { await store.sync() } }
                    // APPLE-DEVELOPER: Server-Push.
                    // if phase == .active { TestReminders.registerForPushIfWanted() }
                    // Beim Verlassen steht fest, was in den nächsten Tagen ansteht.
                    if phase == .background { Task { await TestReminders.reschedule(store: store) } }
                }
                // `presenting`: Die Knöpfe bekommen den Konflikt mitgegeben. Beim Antippen setzt SwiftUI die
                // Bindung zurück, bevor die Aktion läuft – ein Blick in `store.syncConflict` käme dann zu spät.
                .alert(store.t("Unterschiedliche Stände"), isPresented: Binding(get: { store.syncConflict != nil }, set: { if !$0 { store.syncConflict = nil } }), presenting: store.syncConflict) { conflict in
                    Button(store.t("Cloud-Stand übernehmen")) { Task { await store.resolveSyncConflict(conflict, useCloud: true) } }
                    Button(store.t("Stand dieses Geräts hochladen")) { Task { await store.resolveSyncConflict(conflict, useCloud: false) } }
                    Button(store.t("Später entscheiden"), role: .cancel) {}
                } message: { conflict in
                    Text(store.tf("In der Cloud liegen %d Decks und %d Vokabeln, auf diesem Gerät %d Decks und %d Vokabeln. Beide Stände wurden unabhängig voneinander geändert. Der nicht gewählte Stand wird überschrieben.", conflict.remote.decks.count, conflict.remote.vocabulary.count, store.decks.count, store.vocabulary.count))
                }
                .alert(store.t("Gespeicherte Daten nicht lesbar"), isPresented: Binding(get: { store.showsUnreadableDataWarning }, set: { store.showsUnreadableDataWarning = $0 })) {
                    Button(store.t("OK"), role: .cancel) {}
                } message: {
                    Text(store.t("Ein Teil deiner gespeicherten Daten konnte nicht geladen werden. Eine Sicherung der Rohdaten bleibt auf diesem Gerät erhalten."))
                }
        }
    }
}
