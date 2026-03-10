import Foundation
import Shared

// MARK: - NotificationKind

/// Type-safe representation of a notification kind, derived from the
/// raw string returned by the backend. Avoids stringly-typed switch
/// statements scattered across the view layer.
enum NotificationKind: String {
    case friendRequest  = "friend_request"
    case friendAccepted = "friend_accepted"
    case unknown

    init(rawType: String) {
        self = NotificationKind(rawValue: rawType) ?? .unknown
    }
}

// MARK: - NotificationDisplayItem

struct NotificationDisplayItem: Identifiable {
    let id: String
    let kind: NotificationKind
    let actorName: String?
    let isRead: Bool
    let createdAt: String

    var title: String {
        switch kind {
        case .friendRequest:  return "New friend request"
        case .friendAccepted: return "Friend request accepted"
        case .unknown:        return "Notification"
        }
    }

    var body: String {
        let actor = actorName ?? "Someone"
        switch kind {
        case .friendRequest:  return "\(actor) sent you a friend request"
        case .friendAccepted: return "\(actor) accepted your friend request"
        case .unknown:        return "You have a new notification"
        }
    }

    var iconName: String {
        switch kind {
        case .friendRequest:  return "person.badge.plus"
        case .friendAccepted: return "checkmark.circle.fill"
        case .unknown:        return "bell.fill"
        }
    }
}

// MARK: - NotificationsViewModel

@MainActor
final class NotificationsViewModel: ObservableObject {

    @Published var notifications: [NotificationDisplayItem] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var actionError: String? = nil
    @Published var banner: NotificationDisplayItem? = nil

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    // MARK: - Load

    func loadNotifications() {
        isLoading = true
        error = nil

        // Capture the current unread count before the async call so the
        // banner detection compares against the pre-load baseline.
        let previousUnreadCount = unreadCount

        NotificationsBridge.shared.getNotifications(
            onResult: { [weak self] items in
                guard let self else { return }
                self.notifications = items.map { item in
                    // Map the Kotlin NotificationType enum to our Swift kind
                    // using the stable db-value string, not an internal method.
                    let rawType: String
                    switch item.type {
                    case NotificationType.friendRequest:  rawType = "friend_request"
                    case NotificationType.friendAccepted: rawType = "friend_accepted"
                    default:                              rawType = "unknown"
                    }
                    return NotificationDisplayItem(
                        id: item.id,
                        kind: NotificationKind(rawType: rawType),
                        actorName: item.actorName,
                        isRead: item.isRead,
                        createdAt: item.createdAt
                    )
                }
                self.isLoading = false

                // Show a banner only when new unread notifications arrived
                // since the last load. Use the captured baseline, not the
                // current computed value, to avoid a race.
                let newUnreadCount = self.unreadCount
                if newUnreadCount > previousUnreadCount,
                   let first = self.notifications.first(where: { !$0.isRead }) {
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
                self.notifications = self.notifications.map { item in
                    guard item.id == id else { return item }
                    return NotificationDisplayItem(
                        id: item.id, kind: item.kind,
                        actorName: item.actorName, isRead: true,
                        createdAt: item.createdAt
                    )
                }
            },
            onError: { [weak self] _ in
                self?.actionError = "Could not mark notification as read. Please try again."
            }
        )
    }

    func markAllRead() {
        NotificationsBridge.shared.markAllNotificationsRead(
            onSuccess: { [weak self] in
                guard let self else { return }
                self.notifications = self.notifications.map { item in
                    NotificationDisplayItem(
                        id: item.id, kind: item.kind,
                        actorName: item.actorName, isRead: true,
                        createdAt: item.createdAt
                    )
                }
            },
            onError: { [weak self] _ in
                self?.actionError = "Could not mark all notifications as read. Please try again."
            }
        )
    }

    func dismissBanner() {
        banner = nil
    }

    func dismissActionError() {
        actionError = nil
    }
}
