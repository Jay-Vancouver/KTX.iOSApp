import UIKit

/// "Can't connect / Try again" shown over the page when the site cannot be loaded.
final class ErrorView: UIView {

    var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white

        let title = UILabel()
        title.text = String(localized: "error_title")
        title.font = .boldSystemFont(ofSize: 20)
        title.textColor = UIColor(named: "KTXBlue")
        title.textAlignment = .center
        title.numberOfLines = 0

        let message = UILabel()
        message.text = String(localized: "error_message")
        message.font = .systemFont(ofSize: 16)
        message.textColor = .darkGray
        message.textAlignment = .center
        message.numberOfLines = 0

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = String(localized: "retry")
        buttonConfig.baseBackgroundColor = UIColor(named: "KTXBlue")
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        let retry = UIButton(configuration: buttonConfig, primaryAction: UIAction { [weak self] _ in
            self?.onRetry?()
        })

        let stack = UIStackView(arrangedSubviews: [title, message, retry])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(24, after: message)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
