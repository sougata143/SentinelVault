import Flutter
import UIKit
import LocalAuthentication
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.example.app/secure_storage", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] (call, result) in
      self?.handleSecureStorage(call: call, result: result)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func handleSecureStorage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isHardwareSecureSupported":
      result(isHardwareSecureSupported())
    case "writeBiometricWrappedVaultKey":
      if let args = call.arguments as? [String: Any],
         let payloadData = args["payload"] as? FlutterStandardTypedData {
        result(writeBiometricWrappedVaultKey(payload: payloadData.data))
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Payload was missing", details: nil))
      }
    case "readBiometricWrappedVaultKey":
      readBiometricWrappedVaultKey(result: result)
    case "deleteBiometricWrappedVaultKey":
      result(deleteBiometricWrappedVaultKey())
    case "wasEnrollmentChanged":
      result(wasEnrollmentChanged())
    case "resetEnrollmentStatus":
      UserDefaults.standard.set(false, forKey: "biometric_enrollment_changed")
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func isHardwareSecureSupported() -> Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    let context = LAContext()
    var error: NSError?
    return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    #endif
  }

  private func writeBiometricWrappedVaultKey(payload: Data) -> Bool {
    guard isHardwareSecureSupported() else { return false }
    
    let tag = "io.sentinelvault.biometric_key"
    
    // Delete any old key first
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: tag
    ]
    SecItemDelete(deleteQuery as CFDictionary)
    
    var error: Unmanaged<CFError>?
    guard let accessControl = SecAccessControlCreateWithFlags(
      kCFAllocatorDefault,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      .biometryCurrentSet,
      &error
    ) else {
      return false
    }
    
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: tag,
      kSecValueData as String: payload,
      kSecAttrAccessControl as String: accessControl
    ]
    
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecSuccess {
      // Save domain state to detect enrollment changes
      let context = LAContext()
      context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
      if let domainState = context.evaluatedPolicyDomainState {
        UserDefaults.standard.set(domainState.base64EncodedString(), forKey: "biometric_domain_state")
      }
      UserDefaults.standard.set(false, forKey: "biometric_enrollment_changed")
      return true
    }
    return false
  }

  private func readBiometricWrappedVaultKey(result: @escaping FlutterResult) {
    let tag = "io.sentinelvault.biometric_key"
    let context = LAContext()
    context.localizedReason = "Unlock your SentinelVault"
    
    if wasEnrollmentChanged() {
      _ = deleteBiometricWrappedVaultKey()
      result(FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", message: "Biometrics enrollment changed", details: nil))
      return
    }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: tag,
      kSecReturnData as String: true,
      kSecUseAuthenticationContext as String: context
    ]
    
    DispatchQueue.global(qos: .userInitiated).async {
      var dataTypeRef: AnyObject?
      let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
      
      DispatchQueue.main.async {
        if status == errSecSuccess, let data = dataTypeRef as? Data {
          result(FlutterStandardTypedData(bytes: data))
        } else if status == errSecItemNotFound {
          result(FlutterError(code: "NOT_FOUND", message: "Key not found", details: nil))
        } else {
          if status == errSecInteractionNotAllowed || status == -25293 {
            UserDefaults.standard.set(true, forKey: "biometric_enrollment_changed")
            _ = self.deleteBiometricWrappedVaultKey()
            result(FlutterError(code: "KEY_PERMANENTLY_INVALIDATED", message: "Biometrics enrollment changed", details: nil))
          } else {
            result(FlutterError(code: "AUTH_FAILED", message: "Authentication failed or cancelled with status: \(status)", details: nil))
          }
        }
      }
    }
  }

  private func deleteBiometricWrappedVaultKey() -> Bool {
    let tag = "io.sentinelvault.biometric_key"
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: tag
    ]
    let status = SecItemDelete(query as CFDictionary)
    
    UserDefaults.standard.removeObject(forKey: "biometric_domain_state")
    return status == errSecSuccess || status == errSecItemNotFound
  }

  private func wasEnrollmentChanged() -> Bool {
    if UserDefaults.standard.bool(forKey: "biometric_enrollment_changed") {
      return true
    }
    
    let context = LAContext()
    context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    guard let domainState = context.evaluatedPolicyDomainState else {
      let savedState = UserDefaults.standard.string(forKey: "biometric_domain_state")
      return savedState != nil
    }
    
    guard let savedState = UserDefaults.standard.string(forKey: "biometric_domain_state") else {
      return false
    }
    
    let currentStateString = domainState.base64EncodedString()
    if savedState != currentStateString {
      UserDefaults.standard.set(true, forKey: "biometric_enrollment_changed")
      return true
    }
    return false
  }
}
