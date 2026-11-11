import Foundation
import UserNotifications

@MainActor
protocol OperationNotificationHandler: AnyObject {
    func handleOperationNotification(id: UUID, action: String)
    func notificationPermissionChanged(_ permission: NotificationPermission)
    func notificationDeliveryChanged(_ result: NotificationDelivery, operationID: UUID?)
}

final class OperationNotifications: NSObject, UNUserNotificationCenterDelegate, NotificationGateway {
    static let detailsAction = "MULTISHIFT_DETAILS"
    static let showFinderAction = "MULTISHIFT_SHOW_FINDER"
    static let undoAction = "MULTISHIFT_UNDO"

    weak var handler: OperationNotificationHandler?
    private lazy var center = UNUserNotificationCenter.current()
    private let operationLock = NSLock()
    private var operations: [String: RecentOperation] = [:]

    func install() {
        center.delegate = self
        let details = UNNotificationAction(identifier: Self.detailsAction,
                                           title: localized("Operation details", russian: "Подробнее"),
                                           options: [.foreground])
        let showFinder = UNNotificationAction(identifier: Self.showFinderAction,
                                              title: localized("Show in Finder", russian: "Показать в Finder"),
                                              options: [.foreground])
        let undo = UNNotificationAction(identifier: Self.undoAction,
                                        title: localized("Undo", russian: "Отменить"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "MULTISHIFT_RESULT",
                                   actions: [details, showFinder], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "MULTISHIFT_RESULT_UNDO",
                                   actions: [details, showFinder, undo], intentIdentifiers: [], options: [.customDismissAction])
        ])
        refreshPermission()
    }

    func refreshPermission() {
        permission { [weak self] permission in
            DispatchQueue.main.async { self?.handler?.notificationPermissionChanged(permission) }
        }
    }

    func post(_ operation: RecentOperation) {
        let identifier = operation.id.uuidString
        operationLock.lock()
        operations[identifier] = operation
        operationLock.unlock()
        NotificationDispatcher(gateway: self).send(id: identifier, title: operation.title,
                                                   body: interfaceCopy(operation.detail, preserving: operation.inputNames + operation.outputPaths)) { [weak self] result in
            DispatchQueue.main.async {
                self?.handler?.notificationDeliveryChanged(result, operationID: operation.id)
                self?.refreshPermission()
            }
        }
    }

    func testNotification() {
        let identifier = "test-\(UUID().uuidString)"
        NotificationDispatcher(gateway: self).send(
            id: identifier,
            title: localized("Notification test", russian: "Проверка уведомлений"),
            body: localized("This is a native MultiShift notification.", russian: "Это системное уведомление MultiShift.")) { [weak self] result in
                DispatchQueue.main.async {
                    self?.handler?.notificationDeliveryChanged(result, operationID: nil)
                    self?.refreshPermission()
                }
            }
    }

    func removeDeliveredOperation(_ id: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        operationLock.lock()
        operations.removeValue(forKey: id.uuidString)
        operationLock.unlock()
    }

    func permission(_ completion: @escaping (NotificationPermission) -> Void) {
        center.getNotificationSettings { settings in
            let value: NotificationPermission
            switch settings.authorizationStatus {
            case .authorized: value = .authorized
            case .provisional: value = .provisional
            case .ephemeral: value = .ephemeral
            case .notDetermined: value = .notDetermined
            case .denied: value = .denied
            @unknown default: value = .denied
            }
            completion(value)
        }
    }

    func requestPermission(_ completion: @escaping (Bool, String?) -> Void) {
        center.requestAuthorization(options: [.alert]) { allowed, error in
            completion(allowed, error.map { EngineClient.safeDetail($0.localizedDescription) })
        }
    }

    func submit(id: String, title: String, body: String, completion: @escaping (String?) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title.lowercased()
        content.body = body
        content.threadIdentifier = "com.multiswitcher.multishift.operations"
        operationLock.lock()
        let operation = operations[id]
        operationLock.unlock()
        if let operation {
            content.categoryIdentifier = operation.canUndo ? "MULTISHIFT_RESULT_UNDO" : "MULTISHIFT_RESULT"
            content.userInfo = ["operationID": operation.id.uuidString]
        } else {
            content.categoryIdentifier = "MULTISHIFT_RESULT"
            content.userInfo = ["testNotification": true]
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { error in
            completion(error.map { EngineClient.safeDetail($0.localizedDescription) })
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        center.getNotificationSettings { settings in
            // Ask macOS to place it in Notification Center. A configured banner is also
            // requested; Focus, mirroring and other system policies remain authoritative.
            completionHandler(settings.alertStyle == .none ? [.list] : [.banner, .list])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let rawID = response.notification.request.content.userInfo["operationID"] as? String,
              let id = UUID(uuidString: rawID) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handler?.handleOperationNotification(id: id, action: response.actionIdentifier)
        }
    }

    private func localized(_ english: String, russian: String) -> String {
        (UserDefaults(suiteName: "com.multiswitcher.multishift")?.string(forKey: "language") == "ru"
            ? russian : english).lowercased()
    }
}
