import Foundation

public enum OutputOpenResult: Equatable {
    case opened, missing, failed
}

/// History records success at creation time; the saved path may disappear later.
public enum OutputOpening {
    public static func open(path: String, launch: (URL) -> Bool) -> OutputOpenResult {
        do { _ = try FileManager.default.attributesOfItem(atPath: path) }
        catch {
            let error = error as NSError
            let missing = (error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code))
                || (error.domain == NSPOSIXErrorDomain && error.code == 2)
            return missing ? .missing : .failed
        }
        return launch(URL(fileURLWithPath: path)) ? .opened : .failed
    }
}
