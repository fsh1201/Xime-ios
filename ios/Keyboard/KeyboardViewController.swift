import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardViewModel()
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?
    private var baseHeight: CGFloat = 280
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private let candidatePanelHeight: CGFloat = 100

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
            autocapitalization: textDocumentProxy.autocapitalizationType ?? .none,
            keyboardType: textDocumentProxy.keyboardType ?? .default,
            returnKeyType: textDocumentProxy.returnKeyType ?? .default
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
                // unmarkText() 会把 marked text 提交到输入框；清空组合要用空 marked text。
                self.textDocumentProxy.setMarkedText(
                    "",
                    selectedRange: NSRange(location: 0, length: 0)
                )
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

        model.onCandidatePanelChange = { [weak self] in
            self?.updateHeight()
        }
    }

    private func setupHeight() {
        baseHeight = CGFloat(SharedStore.load().keyboardHeight)
        let constraint = view.heightAnchor.constraint(equalToConstant: baseHeight)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        heightConstraint = constraint
    }

    private func updateHeight() {
        let panelHeight = model.isCandidatePanelExpanded ? candidatePanelHeight : 0
        heightConstraint?.constant = baseHeight + panelHeight
    }

    @objc private func settingsChanged() {
        model.reloadSettings()
        baseHeight = CGFloat(SharedStore.load().keyboardHeight)
        updateHeight()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension KeyboardViewController: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
