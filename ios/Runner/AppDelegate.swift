import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "net.roamkit.mobile/euicc",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      if call.method != "openSetupLink" {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let raw = (args?["url"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !raw.isEmpty, let url = URL(string: raw) else {
        result("Missing activation code.")
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened ? nil : "Could not open iOS eSIM setup.")
      }
    }
  }
}
