import Foundation

/// Resolves `{{variable}}` placeholders in snippet content at expansion time.
enum SnippetVariables {
    /// The variables users can put in a snippet, with a short description for the
    /// editor's help text.
    static let reference: [(token: String, description: String)] = [
        ("{{date}}", "Current date"),
        ("{{time}}", "Current time"),
        ("{{datetime}}", "Current date & time"),
        ("{{username}}", "Your full name"),
        ("{{user}}", "Your account name"),
        ("{{uuid}}", "A random UUID"),
    ]

    /// Replaces every known token in `template`. Unknown `{{...}}` tokens are left
    /// untouched. Matching is case-insensitive.
    static func expand(_ template: String, now: Date = .now) -> String {
        let substitutions: [String: String] = [
            "{{date}}": now.formatted(date: .abbreviated, time: .omitted),
            "{{time}}": now.formatted(date: .omitted, time: .shortened),
            "{{datetime}}": now.formatted(date: .abbreviated, time: .shortened),
            "{{username}}": NSFullUserName(),
            "{{user}}": NSUserName(),
            "{{uuid}}": UUID().uuidString,
        ]
        var result = template
        for (token, value) in substitutions {
            result = result.replacingOccurrences(
                of: token,
                with: value,
                options: .caseInsensitive
            )
        }
        return result
    }
}
