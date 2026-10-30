import Foundation
@main struct RootProbe {
    static func main() { print(MultiAuditEnvironment.root?.path ?? "production-default") }
}
