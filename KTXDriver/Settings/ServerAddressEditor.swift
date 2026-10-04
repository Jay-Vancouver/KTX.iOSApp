import UIKit

/// Changing the driver site address (admin only): PIN → address → connection check → save.
/// A chain of UIKit alerts (secure PIN entry, validation that keeps the dialog open).
/// `onSaved` closes the settings screen; the web screen then loads the new address.
final class ServerAddressEditor {

    private let onSaved: () -> Void
    private var keepAlive: ServerAddressEditor? // alive until the dialogs are done

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
    }

    func start() {
        keepAlive = self
        askPin()
    }

    private func done() { keepAlive = nil }

    private func askPin() {
        let alert = UIAlertController(title: String(localized: "settings_pin_title"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode // no password autofill prompts
        }
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel) { [self] _ in done() })
        alert.addAction(UIAlertAction(title: String(localized: "ok"), style: .default) { [self, weak alert] _ in
            if AdminPin.matches(alert?.textFields?.first?.text ?? "") {
                editServer(ServerConfig.startURL.absoluteString, error: nil)
            } else {
                message(String(localized: "settings_pin_wrong")) { self.done() }
            }
        })
        present(alert)
    }

    private func editServer(_ current: String, error: String?) {
        let alert = UIAlertController(title: String(localized: "settings_server"), message: error, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = current
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: String(localized: "settings_save"), style: .default) { [self, weak alert] _ in
            let url = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            if ServerConfig.isValidStartURL(url) {
                checkThenSave(url)
            } else {
                editServer(url, error: String(localized: "settings_server_invalid")) // shown again with the error
            }
        })
        alert.addAction(UIAlertAction(title: String(localized: "settings_reset_default"), style: .default) { [self] _ in
            apply(nil)
        })
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel) { [self] _ in done() })
        present(alert)
    }

    /// Saves when the address answers; otherwise asks first (the server may be down right now).
    private func checkThenSave(_ url: String) {
        let checking = UIAlertController(title: nil, message: String(localized: "settings_server_checking"),
                                         preferredStyle: .alert)
        present(checking)
        Self.isReachable(url) { [self] reachable in
            checking.dismiss(animated: true) { [self] in
                if reachable {
                    apply(url)
                    return
                }
                let alert = UIAlertController(
                    title: nil, message: String(format: String(localized: "settings_server_unreachable"), url),
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel) { [self] _ in
                    editServer(url, error: nil)
                })
                alert.addAction(UIAlertAction(title: String(localized: "settings_save_anyway"), style: .default) { [self] _ in
                    apply(url)
                })
                present(alert)
            }
        }
    }

    /// `url` nil = back to the built-in address.
    private func apply(_ url: String?) {
        let chosen = url.flatMap(URL.init(string:))
        ServerConfig.startURLOverride = chosen == ServerConfig.defaultStartURL ? nil : chosen
        message(String(localized: "settings_server_saved")) { [self] in
            done()
            onSaved()
        }
    }

    /// Any answer 200–499 counts: the server is there, even if this exact page needs a login.
    private static func isReachable(_ url: String, completion: @escaping (Bool) -> Void) {
        guard let target = URL(string: url) else { return completion(false) }
        var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(AppInfo.userAgentToken, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { completion((200...499).contains(code)) }
        }.resume()
    }

    private func message(_ text: String, then: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "ok"), style: .default) { _ in then() })
        present(alert)
    }

    private func present(_ alert: UIAlertController) {
        guard let top = UIApplication.shared.topViewController else { return done() }
        top.present(alert, animated: true)
    }
}
