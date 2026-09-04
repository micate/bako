import Foundation

enum L10n {
    static let bundle = AppResources.bundle
    private static let localizedBundle = bundle(for: Locale.preferredLanguages)

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedBundle.localizedString(
            forKey: key,
            value: nil,
            table: "Localizable"
        )
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    static func bundle(for preferredLanguages: [String]) -> Bundle {
        let supported = bundle.localizations.filter { $0 != "Base" }
        guard
            let localization = Bundle.preferredLocalizations(
                from: supported,
                forPreferences: preferredLanguages
            ).first,
            let stringsURL = bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            ),
            let localizedBundle = Bundle(url: stringsURL.deletingLastPathComponent())
        else {
            return bundle
        }
        return localizedBundle
    }
}
