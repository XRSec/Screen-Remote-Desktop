import Foundation

enum ManagedAppFiltering {
    static func filter(
        _ apps: [ManagedAndroidApp],
        systemState: Bool?,
        enabledState: Bool?,
        searchTerms: [String]
    ) -> [ManagedAndroidApp] {
        apps.filter { app in
            if let systemState, app.isSystem != systemState { return false }
            if let enabledState, app.isEnabled != enabledState { return false }
            return searchTerms.allSatisfy { term in
                app.name.localizedCaseInsensitiveContains(term)
                    || app.packageName.localizedCaseInsensitiveContains(term)
            }
        }
    }
}