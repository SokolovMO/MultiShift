import Foundation

public enum UpdateChannel: String, Sendable {
    case stable, beta

    /// A pilot install follows beta until the user explicitly selects a channel.
    /// A saved selection survives updates, including beta -> stable distribution.
    public static func initial(saved: String?, distribution: String?) -> UpdateChannel {
        if let saved, let channel = UpdateChannel(rawValue: saved) { return channel }
        if let distribution, let channel = UpdateChannel(rawValue: distribution) { return channel }
        return .stable
    }
}
