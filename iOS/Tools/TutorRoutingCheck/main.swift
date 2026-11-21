// Prüft, ob die App Tutor-Nachrichten richtig als Aktion oder Chat erkennt (TutorIntent).
// Aufruf aus dem Ordner iOS:
//   swiftc -o /tmp/tutor_routing Lernkarten/Views/TutorIntent.swift Tools/TutorRoutingCheck/main.swift && /tmp/tutor_routing ../backend/tests/tutor_prompts.json ../backend/tests/tutor_routing_extra.json ../backend/tests/tutor_routing_practice.json
import Foundation

let knownNames = ["Chemie Grundlagen", "Geschichte", "Englisch", "Biologie", "Jura", "Chemie-Klausur"]
var failures = 0, total = 0
for path in CommandLine.arguments.dropFirst() {
    let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
    for function in json["functions"] as! [[String: Any]] {
        let wantsAction = !(function["expect"] as! [String]).contains("chat")
        for prompt in function["prompts"] as! [String] {
            total += 1
            if TutorIntent.isActionRequest(prompt, knownNames: knownNames) != wantsAction {
                failures += 1
                print("✗ \(wantsAction ? "Aktion erwartet" : "Chat erwartet"): \(prompt)")
            }
        }
    }
}
print("\(total - failures)/\(total) richtig erkannt")
exit(failures == 0 ? 0 : 1)
