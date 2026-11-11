import Foundation
import Darwin

public struct StagedInput {
    public let index: Int
    public let sourceURL: URL
    public let stagedURL: URL
}

public struct StagedJob {
    public let id: UUID
    public let rootURL: URL
    public let inputs: [StagedInput]
}

public enum FileJobError: Error, LocalizedError {
    case accessDenied(index: Int)
    case missingInput(index: Int)
    case invalidOutput
    case unsupportedInput(index: Int)

    public var errorDescription: String? {
        switch self {
        case .accessDenied: return "MultiShift cannot read this file. Choose it again in the file picker."
        case .missingInput: return "The source file could not be found."
        case .invalidOutput: return "The processing engine returned an invalid output path."
        case .unsupportedInput: return "Choose a file rather than a folder."
        }
    }
}

public struct FilePublishFailure: Error {
    public let published: [URL]
    public let remaining: [String]
    public let underlying: Error
}

/// Copies selected inputs to a private job directory and publishes completed outputs atomically.
public final class FileJobCoordinator {
    public let jobsURL: URL
    private let fileManager: FileManager
    private let fileCopier: (URL, URL) throws -> Void

    public init(jobsURL: URL? = nil, fileManager: FileManager = .default,
                fileCopier: ((URL, URL) throws -> Void)? = nil) {
        self.fileManager = fileManager
        self.fileCopier = fileCopier ?? { try fileManager.copyItem(at: $0, to: $1) }
        self.jobsURL = jobsURL ?? MultiAuditEnvironment.root?.appendingPathComponent("jobs", isDirectory: true) ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MultiShift/Jobs", isDirectory: true)
    }

    public func cleanAbandonedJobs() {
        guard let jobs = try? fileManager.contentsOfDirectory(at: jobsURL, includingPropertiesForKeys: nil) else { return }
        for job in jobs { try? fileManager.removeItem(at: job) }
    }

    public func stage(_ sourceURLs: [URL], id: UUID) throws -> StagedJob {
        let root = jobsURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var inputs: [StagedInput] = []
        do {
            for (index, url) in sourceURLs.enumerated() {
                let started = url.startAccessingSecurityScopedResource()
                defer { if started { url.stopAccessingSecurityScopedResource() } }
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    throw FileJobError.unsupportedInput(index: index)
                }
                let inputDirectory = root.appendingPathComponent("inputs/\(index)", isDirectory: true)
                try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
                let staged = inputDirectory.appendingPathComponent(url.lastPathComponent)
                do { try fileCopier(url, staged) }
                catch {
                    let nsError = error as NSError
                    if [Int(EPERM), Int(EACCES), 13, 257].contains(nsError.code) {
                        throw FileJobError.accessDenied(index: index)
                    }
                    if nsError.code == Int(ENOENT) || nsError.code == 2 || nsError.code == 260 {
                        throw FileJobError.missingInput(index: index)
                    }
                    throw error
                }
                inputs.append(StagedInput(index: index, sourceURL: url, stagedURL: staged))
            }
            return StagedJob(id: id, rootURL: root, inputs: inputs)
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    /// Publishes only engine-reported outputs. Existing files are never replaced.
    public func publish(_ outputPaths: [String], from job: StagedJob,
                        alternateDestination: URL? = nil) throws -> [URL] {
        let scopedSources = job.inputs.map { ($0.sourceURL, $0.sourceURL.startAccessingSecurityScopedResource()) }
        let destinationScope = alternateDestination?.startAccessingSecurityScopedResource() ?? false
        defer {
            if destinationScope { alternateDestination?.stopAccessingSecurityScopedResource() }
            for (url, started) in scopedSources where started { url.stopAccessingSecurityScopedResource() }
        }
        var published: [URL] = []
        for (position, rawPath) in outputPaths.enumerated() {
            do {
            let output = URL(fileURLWithPath: rawPath).standardizedFileURL
            guard let input = job.inputs.first(where: { output.path.hasPrefix($0.stagedURL.deletingLastPathComponent().path + "/") }),
                  output.path.hasPrefix(job.rootURL.standardizedFileURL.path + "/"),
                  fileManager.fileExists(atPath: output.path) else { throw FileJobError.invalidOutput }
            var relative = output.path.replacingOccurrences(
                of: input.stagedURL.deletingLastPathComponent().standardizedFileURL.path + "/", with: "")
            if alternateDestination != nil, relative.hasPrefix("MultiShift/") {
                relative = String(relative.dropFirst("MultiShift/".count))
            }
            var destination = (alternateDestination ?? input.sourceURL.deletingLastPathComponent())
                .appendingPathComponent(relative)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            destination = Self.uniqueURL(destination, fileManager: fileManager)
            let temporary = destination.deletingLastPathComponent()
                .appendingPathComponent(".multishift-\(UUID().uuidString).partial")
            do {
                try fileManager.copyItem(at: output, to: temporary)
                try fileManager.moveItem(at: temporary, to: destination)
                published.append(destination)
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
            } catch {
                throw FilePublishFailure(published: published,
                                         remaining: Array(outputPaths[position...]), underlying: error)
            }
        }
        return published
    }

    public func remove(_ job: StagedJob) { try? fileManager.removeItem(at: job.rootURL) }

    public static func uniqueURL(_ url: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        var number = 1
        while true {
            let name = url.pathExtension.isEmpty
                ? "\(url.lastPathComponent) (\(number))"
                : "\(url.deletingPathExtension().lastPathComponent) (\(number)).\(url.pathExtension)"
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
}


/// Persist the chosen folder's identity rather than relying on a displayed path.
public enum OutputFolderPreference {
    public static let bookmarkKey = "output.custom.bookmark"
    public static let pathKey = "output.custom.path"
    public static func store(_ url: URL, defaults: UserDefaults) throws {
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
        defaults.set(url.path, forKey: pathKey)
    }
    public static func resolve(defaults: UserDefaults) throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else { throw CocoaError(.fileNoSuchFile) }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileNoSuchFile) }
        if stale { try store(url, defaults: defaults) }
        return url
    }
}
