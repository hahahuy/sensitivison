import UserNotifications

/// Intercepts push notifications and replaces sensitive content when
/// the screen is being captured or privacy mode is enabled via App Group.
class NotificationService: UNNotificationServiceExtension {

  private let appGroupID = "group.com.peekshield.shared"
  private let privacyModeKey = "peek_shield_notification_privacy"

  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

    guard let content = bestAttemptContent else {
      contentHandler(request.content)
      return
    }

    // Check privacy mode from shared UserDefaults (App Group)
    let privacyEnabled = isPrivacyEnabled()

    if privacyEnabled {
      // Preserve original content for the content extension
      var userInfo = content.userInfo as? [String: Any] ?? [:]
      userInfo["peek_shield_original_title"] = content.title
      userInfo["peek_shield_original_body"] = content.body
      content.userInfo = userInfo as [AnyHashable: Any]

      // Replace with generic text
      content.title = "PeekShield"
      content.body = "🔒 New message"
      content.subtitle = ""

      // Signal the content extension to show blurred UI
      content.categoryIdentifier = "PEEK_SHIELD_PRIVATE"
    }

    contentHandler(content)
  }

  override func serviceExtensionTimeWillExpire() {
    // Called just before the extension is terminated by the system.
    // Deliver whatever content we have so far.
    if let contentHandler = contentHandler,
       let bestAttemptContent = bestAttemptContent {
      contentHandler(bestAttemptContent)
    }
  }

  // MARK: - Helpers

  private func isPrivacyEnabled() -> Bool {
    guard let defaults = UserDefaults(suiteName: appGroupID) else {
      return false
    }
    // Privacy is on by default if the key has never been set
    if defaults.object(forKey: privacyModeKey) == nil {
      return true
    }
    return defaults.bool(forKey: privacyModeKey)
  }
}
