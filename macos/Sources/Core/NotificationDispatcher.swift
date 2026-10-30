import Foundation

public enum NotificationPermission: Equatable {
    case authorized, provisional, ephemeral, notDetermined, denied
}

public enum NotificationDelivery: Equatable {
    case transmitted, permissionRequired, denied, failed(String)
}

/// Platform-independent decision layer. Presentation settings such as banner style are left to macOS.
public protocol NotificationGateway {
    func permission(_ completion: @escaping (NotificationPermission) -> Void)
    func requestPermission(_ completion: @escaping (Bool, String?) -> Void)
    func submit(id: String, title: String, body: String, completion: @escaping (String?) -> Void)
}

public struct NotificationDispatcher {
    private let gateway: NotificationGateway
    public init(gateway: NotificationGateway) { self.gateway = gateway }

    public func send(id: String, title: String, body: String,
                     completion: @escaping (NotificationDelivery) -> Void) {
        gateway.permission { permission in
            switch permission {
            case .authorized, .provisional, .ephemeral:
                gateway.submit(id: id, title: title, body: body) { error in
                    completion(error.map(NotificationDelivery.failed) ?? .transmitted)
                }
            case .notDetermined:
                gateway.requestPermission { allowed, error in
                    guard allowed else {
                        completion(error.map(NotificationDelivery.failed) ?? .denied)
                        return
                    }
                    gateway.submit(id: id, title: title, body: body) { submitError in
                        completion(submitError.map(NotificationDelivery.failed) ?? .transmitted)
                    }
                }
            case .denied:
                completion(.denied)
            }
        }
    }
}

/// Quick and foreground work stays in the existing operation history/details.
public enum OperationFeedbackPolicy {
    public static func shouldNotify(elapsed: TimeInterval, applicationActive: Bool) -> Bool {
        elapsed >= 5 && !applicationActive
    }
}
