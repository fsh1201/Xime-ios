import Foundation
import SwiftUI
import UIKit

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel

    private let spacing: CGFloat = 6

    var body: some View {
        Group {
            if model.layer == .emoji {
                EmojiPanel(model: model)
            } else if model.settings.candidateBarEnabled && model.isCandidatePanelExpanded {
                CandidatePanel(model: model)
            } else {
                keyboardBody
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea())
    }

    private var keyboardBody: some View {
        let rows = model.rows

        return VStack(spacing: spacing) {
            if model.settings.candidateBarEnabled {
                CandidateBar(model: model)
                    .frame(height: 34)
            }

            ForEach(rows.indices, id: \.self) { index in
                KeyboardRowView(
                    row: rows[index],
                    returnKeyLabel: model.returnKeyLabel,
                    onTap: model.tap
                )
                .equatable()
                .frame(maxHeight: .infinity)
            }
        }
    }
}

private extension KeyboardViewModel {
    var rows: [[KeyboardKey]] {
        KeyboardLayout.rows(for: layer, shifted: isShifted, showsGlobe: showsGlobe)
    }
}

struct EmojiPanel: View {
    @ObservedObject var model: KeyboardViewModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 8
    )

    private let bottomRow = [
        KeyboardKey("emoji-abc", label: "ABC", action: .layer(.letters), width: 1.5, isSpecial: true),
        KeyboardKey("emoji-space", label: "空格", action: .space, width: 4.5),
        KeyboardKey("emoji-delete", systemImage: "delete.left", action: .delete, width: 1.5, isSpecial: true),
        KeyboardKey("emoji-return", label: "换行", action: .returnKey, width: 1.75, isSpecial: true)
    ]

    var body: some View {
        VStack(spacing: 4) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(EmojiCatalog.all, id: \.self) { emoji in
                        Button {
                            model.commitText(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 26))
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            KeyboardRowView(row: bottomRow, returnKeyLabel: model.returnKeyLabel, onTap: model.tap)
                .equatable()
                .frame(height: 40)
        }
    }
}

struct CandidateBar: View {
    @ObservedObject var model: KeyboardViewModel

    var body: some View {
        HStack(spacing: 6) {
            if RimeEngineFactory.isLibrimeAvailable {
                Button {
                    model.toggleSchema()
                } label: {
                    Text(model.isPinyinSchema ? "拼" : "五")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    model.toggleAsciiMode()
                } label: {
                    Text(model.isAsciiMode ? "英" : "中")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if model.candidates.isEmpty && model.composition.isEmpty {
                Text(hint)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            }

            if !model.composition.isEmpty {
                Text(model.composition)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(model.candidates) { candidate in
                        CandidateChip(candidate: candidate, compact: true) {
                            model.selectCandidate(at: candidate.id)
                        }
                    }
                }
            }

            if !model.candidates.isEmpty {
                Button {
                    model.toggleCandidatePanel()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.55))
        )
    }

    private var hint: String {
        if model.isAsciiMode {
            return "英文"
        }
        guard RimeEngineFactory.isLibrimeAvailable else { return "Xime" }
        if !AppGroup.hasContainer {
            return model.engine.isAvailable ? "Xime" : "内置 Rime 初始化失败"
        }
        if !AppGroup.isRimeDeployed {
            return "请先打开 Xime 完成部署"
        }
        if !model.engine.isAvailable {
            return "Rime 初始化失败，已回退直通"
        }
        return "Xime"
    }
}

struct CandidatePanel: View {
    @ObservedObject var model: KeyboardViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("候选")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("第 \(model.pageNumber + 1) 页")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button("收起") {
                    model.toggleCandidatePanel()
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.candidates) { candidate in
                    CandidateChip(candidate: candidate, compact: false) {
                        model.selectCandidate(at: candidate.id)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 20) {
                Button("上一页") {
                    model.changePage(backward: true)
                }
                .disabled(!model.hasPreviousPage)

                Button("下一页") {
                    model.changePage(backward: false)
                }
                .disabled(!model.hasNextPage)
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.85))
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -40 {
                        model.changePage(backward: false)
                    } else if value.translation.width > 40 {
                        model.changePage(backward: true)
                    }
                }
        )
    }
}

struct CandidateChip: View {
    let candidate: RimeCandidate
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: compact ? .center : .leading, spacing: 1) {
                Text(candidate.text)
                    .font(.system(size: compact ? 18 : 17))
                    .lineLimit(compact ? 1 : 2)
                    .fixedSize(horizontal: compact, vertical: false)

                if let comment = candidate.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 10 : 8)
            .padding(.vertical, compact ? 0 : 4)
            .frame(minHeight: compact ? 30 : 32)
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct KeyboardRowView: View, Equatable {
    let row: [KeyboardKey]
    let returnKeyLabel: String
    let onTap: (KeyboardKey) -> Void

    private let spacing: CGFloat = 6

    static func == (lhs: KeyboardRowView, rhs: KeyboardRowView) -> Bool {
        lhs.row == rhs.row && lhs.returnKeyLabel == rhs.returnKeyLabel
    }

    var body: some View {
        GeometryReader { proxy in
            let totalUnits = row.reduce(0.0) { $0 + $1.width }
            let unit = max(
                0,
                (proxy.size.width - spacing * CGFloat(max(0, row.count - 1))) / CGFloat(max(totalUnits, 1))
            )

            HStack(spacing: spacing) {
                ForEach(row) { key in
                    KeyButton(key: key, returnKeyLabel: returnKeyLabel, onTap: onTap)
                        .frame(width: unit * CGFloat(key.width))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct KeyButton: UIViewRepresentable {
    let key: KeyboardKey
    let returnKeyLabel: String
    let onTap: (KeyboardKey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.contentEdgeInsets = .zero
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.6
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.layer.cornerRadius = 7
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.12
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchDown(_:)),
            for: .touchDown
        )
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchEnded(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
        context.coordinator.button = button
        configure(button, coordinator: context.coordinator)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        configure(button, coordinator: context.coordinator)
    }

    private func configure(_ button: UIButton, coordinator: Coordinator) {
        coordinator.key = key
        coordinator.onTap = onTap
        coordinator.returnKeyLabel = returnKeyLabel

        if case .none = key.action {
            button.isUserInteractionEnabled = false
            button.setTitle(nil, for: .normal)
            button.setImage(nil, for: .normal)
            button.backgroundColor = .clear
            button.layer.shadowOpacity = 0
            return
        }

        button.isUserInteractionEnabled = true
        coordinator.applyAppearance(to: button)
    }

    final class Coordinator: NSObject {
        var key: KeyboardKey?
        var onTap: ((KeyboardKey) -> Void)?
        var returnKeyLabel = ""
        weak var button: UIButton?

        private var isPressed = false
        private var delayTimer: Timer?
        private var repeatTimer: Timer?

        @objc func touchDown(_ sender: UIButton) {
            guard let key, let onTap, key.action != .none else { return }
            isPressed = true
            sender.backgroundColor = pressedBackground(for: key)
            onTap(key)

            guard key.action == .delete else { return }
            delayTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                self?.startRepeat()
            }
        }

        @objc func touchEnded(_ sender: UIButton) {
            isPressed = false
            stopRepeat()
            if let key {
                sender.backgroundColor = background(for: key)
            }
        }

        func applyAppearance(to button: UIButton) {
            guard let key else { return }

            button.setImage(nil, for: .normal)
            button.setTitle(nil, for: .normal)
            button.layer.shadowOpacity = 0.12

            if let systemImage = key.systemImage {
                let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
                button.setImage(
                    UIImage(systemName: systemImage, withConfiguration: configuration),
                    for: .normal
                )
                button.tintColor = key.isSpecial ? .secondaryLabel : .label
            } else {
                let label: String
                switch key.action {
                case .returnKey:
                    label = returnKeyLabel
                case .character(let character):
                    label = String(character)
                default:
                    label = key.label
                }
                button.setTitle(label, for: .normal)
                button.setTitleColor(key.isSpecial ? .secondaryLabel : .label, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: label.count > 1 ? 13 : 20)
            }

            if !isPressed {
                button.backgroundColor = background(for: key)
            }

            button.isAccessibilityElement = true
            button.accessibilityLabel = button.title(for: .normal) ?? key.label
            button.accessibilityTraits = [.button, .keyboardKey]
        }

        private func startRepeat() {
            repeatTimer?.invalidate()
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                guard let self, let key = self.key, let onTap = self.onTap else { return }
                onTap(key)
            }
        }

        private func stopRepeat() {
            delayTimer?.invalidate()
            delayTimer = nil
            repeatTimer?.invalidate()
            repeatTimer = nil
        }

        private func background(for key: KeyboardKey) -> UIColor {
            key.isSpecial ? .tertiarySystemFill : .systemBackground
        }

        private func pressedBackground(for key: KeyboardKey) -> UIColor {
            key.isSpecial
                ? UIColor.tertiarySystemFill.withAlphaComponent(0.7)
                : UIColor.systemBackground.withAlphaComponent(0.7)
        }

        deinit {
            stopRepeat()
        }
    }
}
