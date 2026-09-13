import Foundation

enum CodexDisplay {
    static func reading(_ reading: ProviderUsage, showsSpark: Bool) -> ProviderUsage {
        guard reading.provider == .codex else { return reading }
        var result = reading
        result.windows = reading.windows.filter {
            showsSpark || !(($0.scope ?? "") + $0.id).lowercased().contains("spark")
                && !$0.id.lowercased().contains("bengalfox")
        }.sorted { left, right in
            if (left.scope == nil) != (right.scope == nil) { return left.scope == nil }
            if left.scope == nil, (left.kind == .weekly) != (right.kind == .weekly) {
                return left.kind == .weekly
            }
            return left.id < right.id
        }
        return result
    }
}
