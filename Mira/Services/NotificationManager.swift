import Foundation
import MiraBridge
import UserNotifications
import Observation

/// Manages local notifications, badge count, actionable categories, and deep linking.
@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    var unreadCount: Int = 0
    var agentName: String = "Agent"
    /// Set by the app to navigate to a specific item when notification is tapped.
    var pendingDeepLinkItemId: String?

    private static let notifiedIdsKey = "Mira.Notifications.NotifiedIds"

    private var notifiedIds: Set<String> = []
    private var readIds: Set<String> = []
    private var hasPrimedExistingFeedIds = false

    // MARK: - Category identifiers

    static let categoryNeedsInput = "NEEDS_INPUT"
    static let categoryContentReview = "CONTENT_REVIEW"
    static let categoryFeed = "FEED"
    static let categoryDone = "DONE"

    static let actionApprove = "APPROVE"
    static let actionReject = "REJECT"
    static let actionOpen = "OPEN"

    override init() {
        super.init()
        loadPersistedNotificationState()
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        center.delegate = self
        registerCategories()
    }

    // MARK: - Categories

    private func registerCategories() {
        let approveAction = UNNotificationAction(
            identifier: Self.actionApprove,
            title: "Approve",
            options: []
        )
        let rejectAction = UNNotificationAction(
            identifier: Self.actionReject,
            title: "Reject",
            options: [.destructive]
        )
        let openAction = UNNotificationAction(
            identifier: Self.actionOpen,
            title: "Open",
            options: [.foreground]
        )

        let contentReviewCategory = UNNotificationCategory(
            identifier: Self.categoryContentReview,
            actions: [approveAction, rejectAction, openAction],
            intentIdentifiers: []
        )
        let needsInputCategory = UNNotificationCategory(
            identifier: Self.categoryNeedsInput,
            actions: [openAction],
            intentIdentifiers: []
        )
        let feedCategory = UNNotificationCategory(
            identifier: Self.categoryFeed,
            actions: [openAction],
            intentIdentifiers: []
        )
        let doneCategory = UNNotificationCategory(
            identifier: Self.categoryDone,
            actions: [openAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            contentReviewCategory, needsInputCategory, feedCategory, doneCategory
        ])
    }

    // MARK: - Process Changes

    func processChanges(items: [MiraItem]) {
        primeExistingFeedIdsIfNeeded(items)

        var newUnread = 0
        for item in items {
            if readIds.contains(item.id) { continue }
            if item.needsAttention { newUnread += 1 }

            // Needs attention (needs-input)
            if item.needsAttention && markNotified(item.id) {
                sendNeedsInputNotification(item)
            }

            // Task completed (user-initiated tasks only)
            if item.status == .done && item.origin == .user && markNotified("\(item.id)_done") {
                sendDoneNotification(item)
            }

            // New agent-initiated feed items (briefings, sparks, journal)
            if item.type == .feed && item.origin == .agent && markNotified("\(item.id)_feed") {
                sendFeedNotification(item)
            }
        }
        unreadCount = newUnread
        updateBadge()
    }

    func markAsRead(_ itemId: String) {
        readIds.insert(itemId)
        _ = markNotified(itemId)
    }

    private func updateBadge() {
        UNUserNotificationCenter.current().setBadgeCount(unreadCount)
    }

    // MARK: - Send Notifications

    private func sendNeedsInputNotification(_ item: MiraItem) {
        let content = UNMutableNotificationContent()

        // Detect content review items (writing drafts, articles needing approval)
        let isContentReview = item.tags.contains("review") || item.tags.contains("draft")
            || item.tags.contains("publish") || item.tags.contains("substack")

        if isContentReview {
            content.title = "Review: \(item.title)"
            content.body = item.lastMessagePreview
            content.categoryIdentifier = Self.categoryContentReview
        } else {
            switch item.type {
            case .discussion:
                content.title = "\(agentName) wants to chat"
                content.body = item.title
            case .request:
                content.title = "Needs your reply"
                content.body = item.title
            case .feed:
                content.title = agentName
                content.body = item.title
            }
            content.categoryIdentifier = Self.categoryNeedsInput
        }

        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["itemId": item.id]

        let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendDoneNotification(_ item: MiraItem) {
        let content = UNMutableNotificationContent()
        content.title = "Done: \(item.title)"
        content.body = item.lastMessagePreview
        content.sound = .default
        content.categoryIdentifier = Self.categoryDone
        content.userInfo = ["itemId": item.id]

        let request = UNNotificationRequest(identifier: "\(item.id)_done", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendFeedNotification(_ item: MiraItem) {
        let content = UNMutableNotificationContent()

        // Use tags to determine feed subtype
        if item.tags.contains("briefing") || item.tags.contains("explore") {
            content.title = "Briefing"
        } else if item.tags.contains("journal") {
            content.title = "Journal"
        } else if item.tags.contains("spark") {
            content.title = "Spark"
        } else if item.tags.contains("health") && item.tags.contains("alert") {
            content.title = "健康提醒"
            content.interruptionLevel = .timeSensitive
        } else if item.tags.contains("health") && item.tags.contains("insight") {
            content.title = "今日健康洞察"
        } else if item.tags.contains("health") && item.tags.contains("report") {
            content.title = "健康周报"
        } else if item.tags.contains("trading") || item.tags.contains("analyst") {
            content.title = "Trading Signal"
            content.interruptionLevel = .timeSensitive
        } else {
            content.title = agentName
        }

        content.body = item.title
        content.sound = .default
        if content.interruptionLevel != .timeSensitive {
            content.interruptionLevel = .active
        }
        content.categoryIdentifier = Self.categoryFeed
        content.userInfo = ["itemId": item.id]

        let request = UNNotificationRequest(identifier: "\(item.id)_feed", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification tap — deep link to item.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let itemId = userInfo["itemId"] as? String

        switch response.actionIdentifier {
        case Self.actionApprove:
            if let itemId {
                handleApproval(itemId: itemId, approved: true)
            }
        case Self.actionReject:
            if let itemId {
                handleApproval(itemId: itemId, approved: false)
            }
        case Self.actionOpen, UNNotificationDefaultActionIdentifier:
            // Default tap or explicit "Open" — navigate to item
            if let itemId {
                pendingDeepLinkItemId = itemId
            }
        default:
            break
        }

        completionHandler()
    }

    /// Show notification even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // MARK: - Actions

    /// Called when user approves/rejects from notification action.
    /// Writes a command file to the bridge for the agent to pick up.
    var onApproval: ((_ itemId: String, _ approved: Bool) -> Void)?

    private func handleApproval(itemId: String, approved: Bool) {
        onApproval?(itemId, approved)
    }

    private func primeExistingFeedIdsIfNeeded(_ items: [MiraItem]) {
        guard !hasPrimedExistingFeedIds else { return }
        hasPrimedExistingFeedIds = true

        let existingFeedIds = items
            .filter { $0.type == .feed && $0.origin == .agent }
            .map { "\($0.id)_feed" }
        let baselineCount = notifiedIds.count
        notifiedIds.formUnion(existingFeedIds)
        if notifiedIds.count != baselineCount {
            persistNotificationState()
        }
    }

    private func markNotified(_ id: String) -> Bool {
        let inserted = notifiedIds.insert(id).inserted
        if inserted {
            persistNotificationState()
        }
        return inserted
    }

    private func loadPersistedNotificationState() {
        let storedIds = UserDefaults.standard.array(forKey: Self.notifiedIdsKey) as? [String] ?? []
        notifiedIds = Set(storedIds)
    }

    private func persistNotificationState() {
        UserDefaults.standard.set(Array(notifiedIds), forKey: Self.notifiedIdsKey)
    }
}
