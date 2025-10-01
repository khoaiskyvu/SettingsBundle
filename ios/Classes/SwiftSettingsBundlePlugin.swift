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
        eventSink = nil
        return nil
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
                    result(data)
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
        let data = filteredDefaults()
        eventSink(data)
    }
    
    private func filteredDefaults() -> [String: Any] {
        let raw = UserDefaults.standard.dictionaryRepresentation()
        var sanitized: [String: Any] = [:]
    
        let keys = settingsBundleKeys()
        
        for (key, value) in raw {
            guard keys.contains(key) else { continue }
            sanitized[key] = value
        }
        return sanitized
    }
    
    private func settingsBundleKeys() -> [String] {
            let settingsName = "Settings"
            let settingsExtension = "bundle"
            let settingsRootPlist = "Root.plist"
            let settingsPreferencesItems = "PreferenceSpecifiers"

            guard let settingsBundleURL = Bundle.main.url(forResource: settingsName, withExtension: settingsExtension) else {
                return []
            }

            var seen = Set<String>()

            func collectKeys(from plistURL: URL) {
                guard
                    let data = try? Data(contentsOf: plistURL),
                    let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                    let prefs = plist[settingsPreferencesItems] as? [[String: Any]]
                else { return }

                for pref in prefs {
                    if let key = pref["Key"] as? String, !key.isEmpty {
                        seen.insert(key)
                    }
                    // Nếu có child pane → đệ quy đọc thêm file .plist con
                    if let type = pref["Type"] as? String, type == "PSChildPaneSpecifier" {
                        let fileBase =
                            (pref["File"] as? String) ??
                            (pref["FileName"] as? String) ?? ""   // phòng trường hợp vài template dùng "FileName"
                        if !fileBase.isEmpty {
                            let childName = fileBase.hasSuffix(".plist") ? fileBase : fileBase + ".plist"
                            let childURL = settingsBundleURL.appendingPathComponent(childName)
                            collectKeys(from: childURL)
                        }
                    }
                }
            }

            collectKeys(from: settingsBundleURL.appendingPathComponent(settingsRootPlist))
            return Array(seen)
        }
}
