import Flutter
import UIKit

public class SwiftSettingsBundlePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "settings_bundle", binaryMessenger: registrar.messenger())
        let instance = SwiftSettingsBundlePlugin()
        let didChangeSettings = FlutterEventChannel(name: "did_change_settings_bundle", binaryMessenger: registrar.messenger())
        didChangeSettings.setStreamHandler(instance)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        registerDefaultsFromSettingsBundle()
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        NotificationCenter.default.addObserver(self, selector: #selector(updateDisplayFromDefaults), name: UserDefaults.didChangeNotification, object: nil)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object: nil)
        eventSink = nil
        return nil
    }
    deinit {
        NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object: nil)
    }

    func registerDefaultsFromSettingsBundle() {
        let settingsName = "Settings"
        let settingsExtension = "bundle"
        let settingsRootPlist = "Root.plist"
        let settingsPreferencesItems = "PreferenceSpecifiers"
        let settingsPreferenceKey = "Key"
        let settingsPreferenceDefaultValue = "DefaultValue"
        guard let settingsBundleURL = Bundle.main.url(forResource: settingsName, withExtension: settingsExtension),
              let settingsData = try? Data(contentsOf: settingsBundleURL.appendingPathComponent(settingsRootPlist)),
              let settingsPlist = try? PropertyListSerialization.propertyList(
                  from: settingsData,
                  options: [],
                  format: nil) as? [String: Any],
              let settingsPreferences = settingsPlist[settingsPreferencesItems] as? [[String: Any]] else {
            return
        }

        var defaultsToRegister = [String: Any]()

        settingsPreferences.forEach { preference in
            if let key = preference[settingsPreferenceKey] as? String {
                defaultsToRegister[key] = preference[settingsPreferenceDefaultValue]
            }
        }

        UserDefaults.standard.register(defaults: defaultsToRegister)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getSettingsBundle" {
            if let args = call.arguments as? Dictionary<String, String>,
               let _key = args["key"] {
                if let data = UserDefaults.standard.value(forKey: _key) {
                    result(normalize(data) ?? NSNull())
                } else {
                    result(FlutterError(code: "-404", message: "Not found", details: nil))
                }
            }
        } else if call.method == "setSettingsBundle" {
            if let args = call.arguments as? Dictionary<String, Any>,
               let _key = args["key"] as? String?, let _value = args["value"] {
                if _key == nil {
                    result(false)
                } else {
                    UserDefaults.standard.set(_value, forKey: _key!)
                    result(true)
                }
            } else {
                result(false)
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    @objc private func updateDisplayFromDefaults() {
        guard let eventSink = eventSink else { return }
        let payload = filteredDefaults()
        if Thread.isMainThread {
            eventSink(payload)
        } else {
            DispatchQueue.main.async { eventSink(payload) }
        }
    }

    private func filteredDefaults() -> [String: Any] {
        let bundlePrefix = (Bundle.main.bundleIdentifier ?? "") + "."
        let raw = UserDefaults.standard.dictionaryRepresentation()
        var sanitized: [String: Any] = [:]

        for (key, value) in raw {
            guard key.hasPrefix(bundlePrefix) || key.hasPrefix("sb_") else { continue }
            if let safe = normalize(value) {
                sanitized[key] = safe
            }
        }
        return sanitized
    }

    private func normalize(_ value: Any) -> Any? {
        switch value {
        case let bool as Bool:
            return bool
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let date as Date:
            return date.timeIntervalSince1970
        case let url as URL:
            return url.absoluteString
        case let data as Data:
            return data.base64EncodedString()
        case let array as [Any]:
            return array.compactMap { normalize($0) }
        case let dict as [String: Any]:
            var normalized: [String: Any] = [:]
            for (k, v) in dict {
                if let safe = normalize(v) {
                    normalized[k] = safe
                }
            }
            return normalized
        case _ as NSNull:
            return NSNull()
        default:
            return nil
        }
    }
}
