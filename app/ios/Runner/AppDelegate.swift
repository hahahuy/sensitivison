import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  private let screenChannelName = "com.peekshield/screen"
  private var screenEventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController

    // ── MethodChannel ── isCapturing (one-shot query) ─────────────────────
    let methodChannel = FlutterMethodChannel(
      name: screenChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "isCapturing" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(UIScreen.main.isCaptured)
    }

    // ── EventChannel ── streaming UIScreen.isCapturedDidChangeNotification ─
    let eventChannel = FlutterEventChannel(
      name: "\(screenChannelName)/events",
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel.setStreamHandler(ScreenCaptureStreamHandler())

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - ScreenCaptureStreamHandler

private class ScreenCaptureStreamHandler: NSObject, FlutterStreamHandler {

  private var observer: NSObjectProtocol?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    // Immediately emit current state
    events(UIScreen.main.isCaptured)

    // Subscribe to future changes
    observer = NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      events(UIScreen.main.isCaptured)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
    return nil
  }
}
