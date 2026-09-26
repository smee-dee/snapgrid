import Foundation

/// Rules for the setup assistant.
public enum Setup {
    /// Where the shortcuts come from.
    public enum Source: Hashable { case keep, iCloud, divvy, example }

    /// The option selected at first: existing settings win, then iCloud Drive, then Divvy.
    public static func preferredSource(hasCurrent: Bool, hasCloud: Bool, hasDivvy: Bool) -> Source {
        if hasCurrent { return .keep }
        if hasCloud { return .iCloud }
        if hasDivvy { return .divvy }
        return .example
    }

    /// The last page's text; `config` is nil when the written config doesn't load.
    public static func summary(for config: Config?) -> String {
        guard let config else { return "Your config has an error. Open Settings to fix it." }
        var text = "\(config.shortcuts.count) shortcuts are ready."
        let local = config.localShortcuts.count
        if let leader = config.settings.leader, local > 0 {
            text += " For the \(local) that work after the leader key, press \(leader.symbols), then the key."
        }
        return text
    }
}
