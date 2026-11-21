import Foundation

/// Formelsammlung des Mathe-Bereichs: Stufen → Themen → Formeln. Die Themen-IDs nutzt auch das Backend
/// für Stärken und Schwächen; sie dürfen sich deshalb nicht ändern.
enum MathLevel: String, CaseIterable, Identifiable {
    case middle, upper, university
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .middle: return "Mittelstufe"
        case .upper: return "Oberstufe"
        case .university: return "Uni"
        }
    }
}

struct MathFormula: Identifiable, Hashable {
    let name: String
    let formula: String
    let note: String
    var id: String { name + formula }
}

struct MathTopic: Identifiable, Hashable {
    let id: String
    let level: MathLevel
    let name: String
    let symbol: String
    let formulas: [MathFormula]
}

enum MathCatalog {
    static func topics(for level: MathLevel) -> [MathTopic] { all.filter { $0.level == level } }
    static func topic(_ id: String) -> MathTopic? { all.first { $0.id == id } }

    private static func f(_ name: String, _ formula: String, _ note: String = "") -> MathFormula { MathFormula(name: name, formula: formula, note: note) }

    static let all: [MathTopic] = [
        // MARK: Mittelstufe
        MathTopic(id: "fractions", level: .middle, name: "Bruchrechnung", symbol: "divide", formulas: [
            f("Addieren", "a/b + c/d = (a·d + c·b) / (b·d)", "Erst auf einen gemeinsamen Nenner bringen."),
            f("Multiplizieren", "a/b · c/d = (a·c) / (b·d)", "Zähler mal Zähler, Nenner mal Nenner."),
            f("Dividieren", "a/b ÷ c/d = a/b · d/c", "Mit dem Kehrwert multiplizieren."),
            f("Kürzen", "(a·k) / (b·k) = a/b", "Zähler und Nenner durch dieselbe Zahl k ≠ 0 teilen."),
        ]),
        MathTopic(id: "percentages", level: .middle, name: "Prozent- und Zinsrechnung", symbol: "percent", formulas: [
            f("Prozentwert", "W = G · p / 100", "G: Grundwert, p: Prozentsatz."),
            f("Prozentsatz", "p = W / G · 100"),
            f("Grundwert", "G = W · 100 / p"),
            f("Zinsen (ein Jahr)", "Z = K · p / 100", "K: Kapital, p: Zinssatz."),
            f("Zinseszins", "Kₙ = K₀ · (1 + p/100)ⁿ", "n: Anzahl der Jahre."),
        ]),
        MathTopic(id: "linear_equations", level: .middle, name: "Lineare Gleichungen", symbol: "equal", formulas: [
            f("Äquivalenzumformung", "a·x + b = c  ⇒  x = (c − b) / a", "Auf beiden Seiten dasselbe tun; a ≠ 0."),
            f("Gleichungssystem (Einsetzen)", "y = m·x + n in die zweite Gleichung einsetzen"),
            f("Gleichungssystem (Addition)", "Gleichungen so multiplizieren, dass eine Variable beim Addieren wegfällt"),
        ]),
        MathTopic(id: "linear_functions", level: .middle, name: "Lineare Funktionen", symbol: "chart.xyaxis.line", formulas: [
            f("Funktionsgleichung", "f(x) = m·x + b", "m: Steigung, b: y-Achsenabschnitt."),
            f("Steigung", "m = (y₂ − y₁) / (x₂ − x₁)"),
            f("Nullstelle", "x₀ = −b / m", "m ≠ 0."),
            f("Senkrechte Geraden", "m₁ · m₂ = −1"),
        ]),
        MathTopic(id: "quadratic", level: .middle, name: "Quadratische Gleichungen", symbol: "x.squareroot", formulas: [
            f("p-q-Formel", "x² + p·x + q = 0  ⇒  x = −p/2 ± √((p/2)² − q)"),
            f("Mitternachtsformel", "a·x² + b·x + c = 0  ⇒  x = (−b ± √(b² − 4ac)) / (2a)"),
            f("Diskriminante", "D = b² − 4ac", "D > 0: zwei Lösungen, D = 0: eine, D < 0: keine reelle."),
            f("Scheitelpunktform", "f(x) = a·(x − d)² + e", "Scheitelpunkt S(d | e)."),
            f("Binomische Formeln", "(a ± b)² = a² ± 2ab + b²;  (a + b)(a − b) = a² − b²"),
        ]),
        MathTopic(id: "geometry", level: .middle, name: "Pythagoras und Trigonometrie", symbol: "triangle", formulas: [
            f("Satz des Pythagoras", "a² + b² = c²", "c ist die Hypotenuse im rechtwinkligen Dreieck."),
            f("Sinus", "sin α = Gegenkathete / Hypotenuse"),
            f("Kosinus", "cos α = Ankathete / Hypotenuse"),
            f("Tangens", "tan α = Gegenkathete / Ankathete"),
            f("Sinussatz", "a / sin α = b / sin β = c / sin γ"),
            f("Kosinussatz", "c² = a² + b² − 2ab · cos γ"),
        ]),
        MathTopic(id: "areas_volumes", level: .middle, name: "Flächen und Körper", symbol: "cube", formulas: [
            f("Kreis", "A = π·r²;  U = 2·π·r"),
            f("Dreieck", "A = ½ · g · h"),
            f("Trapez", "A = ½ · (a + c) · h"),
            f("Zylinder", "V = π·r²·h;  O = 2πr² + 2πrh"),
            f("Kegel", "V = ⅓ · π·r²·h"),
            f("Kugel", "V = ⁴⁄₃ · π·r³;  O = 4·π·r²"),
        ]),
        MathTopic(id: "powers_roots", level: .middle, name: "Potenzen und Wurzeln", symbol: "textformat.superscript", formulas: [
            f("Gleiche Basis", "aᵐ · aⁿ = aᵐ⁺ⁿ;  aᵐ ÷ aⁿ = aᵐ⁻ⁿ"),
            f("Potenz einer Potenz", "(aᵐ)ⁿ = aᵐ·ⁿ"),
            f("Negativer Exponent", "a⁻ⁿ = 1 / aⁿ"),
            f("Wurzel als Potenz", "ⁿ√a = a^(1/n)"),
            f("Wurzelgesetz", "√(a·b) = √a · √b", "a, b ≥ 0."),
        ]),

        // MARK: Oberstufe
        MathTopic(id: "derivatives", level: .upper, name: "Ableitungen", symbol: "function", formulas: [
            f("Potenzregel", "(xⁿ)′ = n·xⁿ⁻¹"),
            f("Produktregel", "(u·v)′ = u′·v + u·v′"),
            f("Quotientenregel", "(u/v)′ = (u′·v − u·v′) / v²"),
            f("Kettenregel", "(f(g(x)))′ = f′(g(x)) · g′(x)"),
            f("Wichtige Ableitungen", "(eˣ)′ = eˣ;  (ln x)′ = 1/x;  (sin x)′ = cos x;  (cos x)′ = −sin x"),
            f("Extremstellen", "f′(x) = 0 und f″(x) ≠ 0", "f″ < 0: Hochpunkt, f″ > 0: Tiefpunkt."),
            f("Wendestellen", "f″(x) = 0 und f‴(x) ≠ 0"),
        ]),
        MathTopic(id: "integrals", level: .upper, name: "Integrale", symbol: "sum", formulas: [
            f("Stammfunktion von xⁿ", "∫ xⁿ dx = xⁿ⁺¹ / (n + 1) + C", "n ≠ −1."),
            f("Hauptsatz", "∫ₐᵇ f(x) dx = F(b) − F(a)"),
            f("Wichtige Stammfunktionen", "∫ eˣ dx = eˣ + C;  ∫ 1/x dx = ln|x| + C;  ∫ sin x dx = −cos x + C"),
            f("Fläche zwischen Graphen", "A = ∫ₐᵇ |f(x) − g(x)| dx"),
            f("Mittelwert", "m = 1/(b − a) · ∫ₐᵇ f(x) dx"),
        ]),
        MathTopic(id: "exp_log", level: .upper, name: "Exponential und Logarithmus", symbol: "chart.line.uptrend.xyaxis", formulas: [
            f("Wachstum", "f(t) = a · eᵏᵗ", "k > 0: Wachstum, k < 0: Zerfall."),
            f("Logarithmus", "logₐ b = x  ⇔  aˣ = b"),
            f("Logarithmengesetze", "log(u·v) = log u + log v;  log(uʳ) = r · log u"),
            f("Halbwertszeit", "T½ = ln 2 / |k|"),
        ]),
        MathTopic(id: "vectors", level: .upper, name: "Vektoren", symbol: "arrow.up.right", formulas: [
            f("Betrag", "|a⃗| = √(a₁² + a₂² + a₃²)"),
            f("Skalarprodukt", "a⃗ · b⃗ = a₁b₁ + a₂b₂ + a₃b₃", "= 0 heißt: orthogonal."),
            f("Winkel", "cos φ = (a⃗ · b⃗) / (|a⃗| · |b⃗|)"),
            f("Kreuzprodukt", "a⃗ × b⃗ = (a₂b₃ − a₃b₂, a₃b₁ − a₁b₃, a₁b₂ − a₂b₁)"),
        ]),
        MathTopic(id: "lines_planes", level: .upper, name: "Geraden und Ebenen", symbol: "square.on.square.dashed", formulas: [
            f("Gerade", "g: x⃗ = p⃗ + t · u⃗"),
            f("Ebene (Parameterform)", "E: x⃗ = p⃗ + r · u⃗ + s · v⃗"),
            f("Ebene (Koordinatenform)", "E: a·x₁ + b·x₂ + c·x₃ = d", "n⃗ = (a, b, c) ist ein Normalenvektor."),
            f("Abstand Punkt–Ebene", "d = |a·p₁ + b·p₂ + c·p₃ − d| / |n⃗|"),
        ]),
        MathTopic(id: "probability", level: .upper, name: "Wahrscheinlichkeit", symbol: "dice", formulas: [
            f("Laplace", "P(A) = günstige / mögliche Ergebnisse"),
            f("Gegenereignis", "P(Ā) = 1 − P(A)"),
            f("Bedingte Wahrscheinlichkeit", "P(A|B) = P(A ∩ B) / P(B)"),
            f("Erwartungswert", "E(X) = Σ xᵢ · P(X = xᵢ)"),
        ]),
        MathTopic(id: "binomial", level: .upper, name: "Binomialverteilung", symbol: "chart.bar", formulas: [
            f("Bernoulli-Formel", "P(X = k) = (n über k) · pᵏ · (1 − p)ⁿ⁻ᵏ"),
            f("Binomialkoeffizient", "(n über k) = n! / (k! · (n − k)!)"),
            f("Erwartungswert", "μ = n · p"),
            f("Standardabweichung", "σ = √(n · p · (1 − p))"),
        ]),

        // MARK: Uni-Grundlagen
        MathTopic(id: "linear_algebra", level: .university, name: "Lineare Algebra", symbol: "square.grid.3x3", formulas: [
            f("Matrixprodukt", "(A·B)ᵢⱼ = Σₖ aᵢₖ · bₖⱼ"),
            f("Determinante 2×2", "det(A) = a·d − b·c  für A = (a b; c d)"),
            f("Inverse 2×2", "A⁻¹ = 1/det(A) · (d −b; −c a)"),
            f("Eigenwerte", "det(A − λ·I) = 0"),
            f("Lösbarkeit", "A·x = b eindeutig lösbar  ⇔  det(A) ≠ 0"),
        ]),
        MathTopic(id: "sequences_series", level: .university, name: "Folgen und Reihen", symbol: "ellipsis", formulas: [
            f("Geometrische Reihe", "Σₖ₌₀^∞ qᵏ = 1 / (1 − q)", "|q| < 1."),
            f("Arithmetische Summe", "Σₖ₌₁ⁿ k = n·(n + 1) / 2"),
            f("Quotientenkriterium", "lim |aₙ₊₁ / aₙ| < 1  ⇒  Σ aₙ konvergiert"),
            f("Taylorreihe", "f(x) = Σ f⁽ⁿ⁾(a) / n! · (x − a)ⁿ"),
        ]),
        MathTopic(id: "differential_equations", level: .university, name: "Differentialgleichungen", symbol: "waveform.path.ecg", formulas: [
            f("Lineare DGL 1. Ordnung", "y′ = k·y  ⇒  y = C · eᵏˣ"),
            f("Trennung der Variablen", "y′ = f(x)·g(y)  ⇒  ∫ dy/g(y) = ∫ f(x) dx"),
            f("Charakteristische Gleichung", "y″ + a·y′ + b·y = 0  ⇒  λ² + a·λ + b = 0"),
        ]),
        MathTopic(id: "statistics", level: .university, name: "Statistik", symbol: "chart.dots.scatter", formulas: [
            f("Mittelwert", "x̄ = (1/n) · Σ xᵢ"),
            f("Stichprobenvarianz", "s² = 1/(n − 1) · Σ (xᵢ − x̄)²"),
            f("Standardisierung", "z = (x − μ) / σ"),
            f("Korrelation", "r = Σ(xᵢ − x̄)(yᵢ − ȳ) / √(Σ(xᵢ − x̄)² · Σ(yᵢ − ȳ)²)"),
        ]),
        MathTopic(id: "complex_numbers", level: .university, name: "Komplexe Zahlen", symbol: "circle.grid.cross", formulas: [
            f("Imaginäre Einheit", "i² = −1"),
            f("Betrag", "|a + b·i| = √(a² + b²)"),
            f("Euler-Formel", "e^(iφ) = cos φ + i · sin φ"),
            f("Polarform", "z = r · e^(iφ)"),
        ]),
    ]

    /// Zeichen, die im Rechenweg schnell eingefügt werden können.
    static let symbols = ["²", "³", "√", "π", "·", "÷", "±", "≤", "≥", "≠", "≈", "∞", "∫", "Σ", "Δ", "→", "⇒", "(", ")", "^", "ⁿ", "₁", "₂", "α", "β", "λ"]
}
