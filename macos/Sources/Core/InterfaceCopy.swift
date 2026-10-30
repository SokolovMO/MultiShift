import Foundation

/// Lowercase owned copy while preserving exact user-supplied names and paths.
public func interfaceCopy(_ value: String, preserving userValues: [String] = []) -> String {
    var result = value
    var replacements: [(String, String)] = []
    for (index, original) in Set(userValues.filter { !$0.isEmpty }).sorted(by: { $0.count > $1.count }).enumerated() {
        let token = "\u{E000}\(index)\u{E001}"
        if result.contains(original) {
            result = result.replacingOccurrences(of: original, with: token)
            replacements.append((token, original))
        }
    }
    result = result.lowercased()
    for (token, original) in replacements { result = result.replacingOccurrences(of: token, with: original) }
    return result
}

