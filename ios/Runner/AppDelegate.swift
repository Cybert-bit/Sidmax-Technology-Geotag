import Flutter
import UIKit
import GoogleMaps
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyAOVYRIgupAurZup5y1PRh8Ismb1A3lLao")

    if let controller = window?.rootViewController as? FlutterViewController {
      let galleryChannel = FlutterMethodChannel(
        name: "com.example.flutter_application_1/gallery",
        binaryMessenger: controller.binaryMessenger
      )

      galleryChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "saveImageToGallery" {
          guard let args = call.arguments as? [String: Any],
                let filePath = args["filePath"] as? String,
                let image = UIImage(contentsOfFile: filePath) else {
            result(FlutterError(code: "INVALID_PATH", message: "File path or image invalid", details: nil))
            return
          }

          UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
          result("Saved to iOS Photos Library")
        } else if call.method == "openGoogleMaps" {
          guard let args = call.arguments as? [String: Any],
                let lat = args["latitude"] as? Double,
                let lng = args["longitude"] as? Double else {
            result(FlutterError(code: "INVALID_ARGS", message: "Coordinates invalid", details: nil))
            return
          }

          if let googleMapsUrl = URL(string: "comgooglemaps://?q=\(lat),\(lng)&zoom=18"),
             UIApplication.shared.canOpenURL(googleMapsUrl) {
            UIApplication.shared.open(googleMapsUrl, options: [:], completionHandler: nil)
          } else if let appleMapsUrl = URL(string: "http://maps.apple.com/?ll=\(lat),\(lng)&q=Pinned+Location") {
            UIApplication.shared.open(appleMapsUrl, options: [:], completionHandler: nil)
          }
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
