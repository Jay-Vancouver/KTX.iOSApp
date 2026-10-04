import CryptoKit
import Foundation

/// The administrator PIN that guards the server address. Only its SHA-256 is in the app
/// (KTXAdminPinSHA256, embedded at build time by tools/embed_admin_pin.sh).
enum AdminPin {
    static func matches(_ pin: String) -> Bool {
        guard let expected = Bundle.main.object(forInfoDictionaryKey: "KTXAdminPinSHA256") as? String,
              !expected.isEmpty else { return false }
        let digest = SHA256.hash(data: Data(pin.trimmingCharacters(in: .whitespaces).utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex == expected.lowercased()
    }
}
