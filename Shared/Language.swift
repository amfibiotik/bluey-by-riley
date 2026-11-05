import Foundation

/// The language Bluey speaks and shows its interface in.
///
/// Default: Ukrainian when the device's first preferred language is Ukrainian, otherwise English.
/// The Mac menu (Language / Мова) can override it. The phone follows the iPhone's own language setting.
public enum BlueyLanguage: String, CaseIterable {
    case english = "en"
    case ukrainian = "uk"

    private static let key = "bluey.language"

    /// What the user picked by hand; nil means "follow the system".
    public static var chosen: BlueyLanguage? {
        get { UserDefaults.standard.string(forKey: key).flatMap(BlueyLanguage.init(rawValue:)) }
        set {
            if let newValue { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    public static var system: BlueyLanguage {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("uk") ? .ukrainian : .english
    }

    public static var current: BlueyLanguage { chosen ?? system }

    public var isUkrainian: Bool { self == .ukrainian }

    /// Name shown in the language menu.
    public var title: String { self == .ukrainian ? "Українська" : "English" }

    /// A line appended to every model prompt so replies come back in this language.
    /// Empty for English, because the original prompts are already English.
    public var modelDirective: String {
        guard isUkrainian else { return "" }
        return """
        Language: always reply in natural, correct Ukrainian (українською), even if the user, the screen or \
        the task text is in another language. Keep your dry, quick-witted tone, but use Ukrainian phrasing \
        and humour, not a word-for-word translation of British jokes. Use informal "ти", never "ви". \
        Tool names, JSON keys and fixed enum values stay exactly as specified in English.
        """
    }

    /// Hint for speech recognition (ISO 639-1). nil lets the model auto-detect.
    public var speechCode: String? { isUkrainian ? "uk" : nil }
}

/// Picks the Ukrainian text when the current language is Ukrainian, otherwise the English one.
/// Keeping both strings side by side makes a missing translation easy to spot in review.
public func tr(_ english: String, _ ukrainian: String) -> String {
    BlueyLanguage.current.isUkrainian ? ukrainian : english
}
