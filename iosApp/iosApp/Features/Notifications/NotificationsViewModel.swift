import Foundation
import Shared

// MARK: - NotificationDisplayItem

struct NotificationDisplayItem: Identifiable {
    let id: String
    let type: String          // "friend_request" | "friend_accepted"
    let actorName: String?
    let isRead: Bool
    let createdAt: String

    var title: String {
        switch type {
        case "friend_request":  return "New friend request"
        case "friend_accepted": return "Friend request accepted"
        default:                return "Notification"
        }
    }

    var body: String {
        let actor = actorName ?? "Someone"
        switch type {
        case "friend_request":  return "\(actor) sent you a friend request"
        case "friend_accepted": return "\(actor) accepted your friend request"
        default:                return "You have a new notification"
        }
    }

    var iconName: String {
        switch type {
        case "friend_request":  return "person.badge.plus"
        case "friend_accepted": return "checkmark.circle.fill"
        default:                return "bell.fill"
        }
    }
}

// MARK: - NotificationsViewModel

@MainActor
final class NotificationsViewModel: ObservableObject {

    @Published var notifications: [NotificationDisplayItem] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var banner: NotificationDisplayItem? = nil

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    // MARK: - Load

    func loadNotifications() {
        isLoading = true
        error = nil

        NotificationsBridge.shared.getNotifications(
            onResult: { [weak self] items in
                guard let self else { return }
                let previous = self.unreadCount
                self.notifications = items.map {
                    NotificationDisplayItem(
                        id: $0.id,
                        type: $0.type.toDbValue(),
                        actorName: $0.actorName,
                        isRead: $0.isRead,
                        createdAt: $0.createdAt
                    )
                }
                self.isLoading = false
                // Show banner if a new unread notification arrived
                let newUnread = self.unreadCount
                if newUnread > previous, let first = self.notifications.first(where: { !$0.isRead }) {
                    self.banner = first
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                self.error = err
                self.isLoading = false
            }
        )
    }

    // MARK: - Mark read

    func markRead(_ id: String) {
        NotificationsBridge.shared.markNotificationRead(
            notificationId: id,
            onSuccess: { [weak self] in
                guard let self else { return }
                self.notifications = self.notifications.map {
                    $0.id == id
                        ? NotificationDisplayItem(id: $0.id, type: $0.type,
                                                   actorName: $0.actorName, isRead: true,
                                                   createdAt: $0.createdAt)
                        : $0
                }
            },
            onError: { _ in }
        )
    }

    func markAllRead() {
        NotificationsBridge.shared.markAllNotificationsRead(
            onSuccess: { [weak self] in
                guard let self else { return }
                self.notifications = self.notifications.map {
                    NotificationDisplayItem(id: $0.id, type: $0.type,
                                             actorName: $0.actorName, isRead: true,
                                             createdAt: $0.createdAt)
                }
            },
            onError: { _ in }
        )
    }

    func dismissBanner() {
        banner = nil
    }
}
