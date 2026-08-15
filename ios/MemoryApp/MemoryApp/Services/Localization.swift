import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chineseSimplified = "zh-Hans"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    static func normalized(_ rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .english
    }
}
