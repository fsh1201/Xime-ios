import Foundation
import SwiftUI
import UIKit

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel

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

        return VStack(spacing: 0) {
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

                if !model.isAsciiMode {
                    Button {
                        model.toggleSingleCharMode()
                    } label: {
                        Text("单")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        model.isSingleCharMode
                                            ? Color.accentColor.opacity(0.25)
                                            : Color(uiColor: .tertiarySystemFill)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.isSingleCharMode ? Color.primary : Color.secondary)
                }
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
                Text(model.isSingleCharMode ? "单字" : "候选")
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

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(model.candidates) { candidate in
                        CandidateChip(candidate: candidate, compact: false) {
                            model.selectCandidate(at: candidate.id)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

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

    static func == (lhs: KeyboardRowView, rhs: KeyboardRowView) -> Bool {
        lhs.row == rhs.row && lhs.returnKeyLabel == rhs.returnKeyLabel
    }

    var body: some View {
        GeometryReader { proxy in
            let totalUnits = row.reduce(0.0) { $0 + $1.width }
            let unit = max(0, proxy.size.width / CGFloat(max(totalUnits, 1)))

            HStack(spacing: 0) {
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

    func makeUIView(context: Context) -> KeyControl {
        let control = KeyControl()
        control.onTap = onTap
        control.configure(key: key, returnKeyLabel: returnKeyLabel)
        return control
    }

    func updateUIView(_ control: KeyControl, context: Context) {
        control.onTap = onTap
        control.configure(key: key, returnKeyLabel: returnKeyLabel)
    }
}

/// 命中区域覆盖整个网格单元，视觉背景内缩 3pt，避免按键之间出现触摸死区。
final class KeyControl: UIControl {
    var onTap: ((KeyboardKey) -> Void)?

    private let backgroundView = UIView()
    private let label = UILabel()
    private let imageView = UIImageView()
    private var key: KeyboardKey?
    private var delayTimer: Timer?
    private var repeatTimer: Timer?

    private let visualInset: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isExclusiveTouch = false

        backgroundView.isUserInteractionEnabled = false
        backgroundView.layer.cornerRadius = 7
        backgroundView.layer.shadowColor = UIColor.black.cgColor
        backgroundView.layer.shadowOpacity = 0.12
        backgroundView.layer.shadowRadius = 0
        backgroundView.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(backgroundView)

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.lineBreakMode = .byTruncatingTail
        backgroundView.addSubview(label)

        imageView.contentMode = .scaleAspectFit
        backgroundView.addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds.insetBy(dx: visualInset, dy: visualInset)
        label.frame = backgroundView.bounds
        imageView.frame = backgroundView.bounds.insetBy(dx: 8, dy: 8)
    }

    func configure(key: KeyboardKey, returnKeyLabel: String) {
        self.key = key

        guard key.action != .none else {
            backgroundView.isHidden = true
            label.text = nil
            imageView.image = nil
            isAccessibilityElement = false
            return
        }

        backgroundView.isHidden = false
        backgroundView.alpha = 1
        backgroundView.backgroundColor = key.isSpecial ? .tertiarySystemFill : .systemBackground

        if let systemImage = key.systemImage {
            label.text = nil
            label.isHidden = true
            imageView.isHidden = false
            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            imageView.image = UIImage(systemName: systemImage, withConfiguration: configuration)
            imageView.tintColor = key.isSpecial ? .secondaryLabel : .label
            accessibilityLabel = key.label
        } else {
            imageView.isHidden = true
            label.isHidden = false

            let text: String
            switch key.action {
            case .returnKey:
                text = returnKeyLabel
            case .character(let character):
                text = String(character)
            default:
                text = key.label
            }

            label.text = text
            label.textColor = key.isSpecial ? .secondaryLabel : .label
            label.font = .systemFont(ofSize: text.count > 1 ? 13 : 20)
            accessibilityLabel = text
        }

        isAccessibilityElement = true
        accessibilityTraits = [.button, .keyboardKey]
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard let key, key.action != .none, let onTap else { return false }

        backgroundView.alpha = 0.65
        onTap(key)

        if key.action == .delete {
            delayTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                self?.startRepeat()
            }
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        endPress()
    }

    override func cancelTracking(with event: UIEvent?) {
        endPress()
    }

    override func accessibilityActivate() -> Bool {
        guard let key, key.action != .none, let onTap else { return false }
        onTap(key)
        return true
    }

    private func endPress() {
        backgroundView.alpha = 1
        delayTimer?.invalidate()
        delayTimer = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func startRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            guard let self, let key = self.key, let onTap = self.onTap else { return }
            onTap(key)
        }
    }

    deinit {
        delayTimer?.invalidate()
        repeatTimer?.invalidate()
    }
}
