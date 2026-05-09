import UIKit
import UserNotifications
import UserNotificationsUI
import LocalAuthentication

/// Custom notification UI that shows a blurred card-style view.
/// "Tap to reveal" requires Face ID / Touch ID authentication.
class NotificationViewController: UIViewController, UNNotificationContentExtension {

  // MARK: - UI

  private let containerView = UIView()
  private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
  private let lockIcon = UILabel()
  private let titleLabel = UILabel()
  private let bodyLabel = UILabel()
  private let revealButton = UIButton(type: .system)
  private let appIcon = UIImageView()

  private var originalTitle: String?
  private var originalBody: String?
  private var isRevealed = false

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
  }

  // MARK: - UNNotificationContentExtension

  func didReceive(_ notification: UNNotification) {
    let content = notification.request.content

    // Extract original content stored by the service extension
    let userInfo = content.userInfo as? [String: Any]
    originalTitle = userInfo?["peek_shield_original_title"] as? String ?? content.title
    originalBody = userInfo?["peek_shield_original_body"] as? String ?? content.body

    updateUI(revealed: false)
  }

  // MARK: - Actions

  @objc private func revealTapped() {
    guard !isRevealed else { return }

    let context = LAContext()
    var error: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      // Fall back to passcode
      authenticateWithPasscode()
      return
    }

    context.evaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      localizedReason: "Reveal notification content"
    ) { [weak self] success, _ in
      DispatchQueue.main.async {
        if success {
          self?.updateUI(revealed: true)
        }
      }
    }
  }

  private func authenticateWithPasscode() {
    let context = LAContext()
    context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: "Reveal notification content"
    ) { [weak self] success, _ in
      DispatchQueue.main.async {
        if success {
          self?.updateUI(revealed: true)
        }
      }
    }
  }

  // MARK: - UI Updates

  private func updateUI(revealed: Bool) {
    isRevealed = revealed

    UIView.animate(withDuration: 0.3) {
      self.blurView.alpha = revealed ? 0 : 1
      self.lockIcon.alpha = revealed ? 0 : 1
      self.revealButton.alpha = revealed ? 0 : 1
    }

    if revealed {
      titleLabel.text = originalTitle
      bodyLabel.text = originalBody
    } else {
      titleLabel.text = "PeekShield"
      bodyLabel.text = "🔒 New message"
    }
  }

  // MARK: - Setup

  private func setupUI() {
    view.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0)

    // Container
    containerView.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.18, alpha: 1.0)
    containerView.layer.cornerRadius = 16
    containerView.layer.masksToBounds = true
    containerView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(containerView)

    // App icon placeholder
    appIcon.backgroundColor = UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
    appIcon.layer.cornerRadius = 10
    appIcon.layer.masksToBounds = true
    appIcon.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(appIcon)

    // Title
    titleLabel.font = UIFont.boldSystemFont(ofSize: 15)
    titleLabel.textColor = .white
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(titleLabel)

    // Body
    bodyLabel.font = UIFont.systemFont(ofSize: 13)
    bodyLabel.textColor = UIColor(white: 0.7, alpha: 1.0)
    bodyLabel.numberOfLines = 2
    bodyLabel.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(bodyLabel)

    // Blur overlay
    blurView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(blurView)

    // Lock icon
    lockIcon.text = "🔒"
    lockIcon.font = UIFont.systemFont(ofSize: 28)
    lockIcon.textAlignment = .center
    lockIcon.translatesAutoresizingMaskIntoConstraints = false
    blurView.contentView.addSubview(lockIcon)

    // Reveal button
    revealButton.setTitle("Tap to reveal", for: .normal)
    revealButton.setTitleColor(UIColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 1.0), for: .normal)
    revealButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
    revealButton.addTarget(self, action: #selector(revealTapped), for: .touchUpInside)
    revealButton.translatesAutoresizingMaskIntoConstraints = false
    blurView.contentView.addSubview(revealButton)

    setupConstraints()
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      // Container
      containerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
      containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

      // App icon
      appIcon.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
      appIcon.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
      appIcon.widthAnchor.constraint(equalToConstant: 44),
      appIcon.heightAnchor.constraint(equalToConstant: 44),

      // Title
      titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
      titleLabel.leadingAnchor.constraint(equalTo: appIcon.trailingAnchor, constant: 10),
      titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),

      // Body
      bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      bodyLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -14),

      // Blur overlay (covers entire container)
      blurView.topAnchor.constraint(equalTo: containerView.topAnchor),
      blurView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      blurView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      blurView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

      // Lock icon
      lockIcon.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
      lockIcon.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor, constant: -14),

      // Reveal button
      revealButton.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
      revealButton.topAnchor.constraint(equalTo: lockIcon.bottomAnchor, constant: 6),
    ])
  }
}
