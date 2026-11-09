import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardViewModel()
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    override func viewDidLoad() {
        super.viewDidLoad()

        SharedStore.startObserving()
        setupHostingController()
        bindModel()
        setupHeight()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: AppGroup.settingsChangedNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        model.updateContext(
            autocapitalization: textDocumentProxy.autocapitalizationType,
            keyboardType: textDocumentProxy.keyboardType,
            returnKeyType: textDocumentProxy.returnKeyType
        )
        model.setShowsGlobe(needsInputModeSwitchKey)
        updateHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)

        // 当宿主清空输入框时，同步放弃当前组合。
        if textDocumentProxy.documentContextBeforeInput?.isEmpty ?? true {
            model.resetComposition()
        }
    }

    private func setupHostingController() {
        let root = KeyboardRootView(model: model)
        let hosting = UIHostingController(rootView: root)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear

        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting
    }

    private func bindModel() {
        model.onCommit = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
        }

        model.onDelete = { [weak self] in
            self?.textDocumentProxy.deleteBackward()
        }

        model.onCompositionChange = { [weak self] text in
            guard let self else { return }
            if text.isEmpty {
                self.textDocumentProxy.unmarkText()
            } else {
                self.textDocumentProxy.setMarkedText(
                    text,
                    selectedRange: NSRange(location: text.utf16.count, length: 0)
                )
            }
        }

        model.onFeedback = { [weak self] in
            guard let self, self.model.settings.hapticsEnabled else { return }
            self.feedbackGenerator.impactOccurred()
            UIDevice.current.playInputClick()
        }

        model.onGlobe = { [weak self] in
            self?.advanceToNextInputMode()
        }
    }

    private func setupHeight() {
        let constraint = view.heightAnchor.constraint(
            equalToConstant: CGFloat(SharedStore.load().keyboardHeight)
        )
        constraint.priority = .defaultHigh
        constraint.isActive = true
        heightConstraint = constraint
    }

    private func updateHeight() {
        heightConstraint?.constant = CGFloat(SharedStore.load().keyboardHeight)
    }

    @objc private func settingsChanged() {
        model.reloadSettings()
        updateHeight()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension KeyboardViewController: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
