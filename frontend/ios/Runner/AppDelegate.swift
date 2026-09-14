import Flutter
import FirebaseAuth
import FirebaseCore
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if let firebaseApp = FirebaseApp.app() {
      if Auth.auth().canHandle(url) {
        return true
      }

      // Firebase may already have consumed the callback through swizzling.
      // Never forward that same callback to Flutter's page navigation.
      let callbackScheme = "app-" + firebaseApp.options.googleAppID
        .replacingOccurrences(of: ":", with: "-")
      if url.scheme == callbackScheme && url.host == "firebaseauth" {
        return true
      }
    }
    return super.application(application, open: url, options: options)
  }
}
