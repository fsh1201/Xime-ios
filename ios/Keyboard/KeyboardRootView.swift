import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel

    private let spacing: CGFloat = 6

    var body: some View {
        let rows = model.rows

        VStack(spacing: spacing) {
            if model.settings.candidateBarEnabled {
                CandidateBar(model: model)
                    .frame(height: 34)

                if model.isCandidatePanelExpanded {
                    CandidatePanel(model: model)
                        .frame(height: 100)
                }
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
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea())
    }
}

private extension KeyboardViewModel {
    var rows: [[KeyboardKey]] {
        KeyboardLayout.rows(for: layer, shifted: isShifted, showsGlobe: showsGlobe)
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
                    .padding(.horizontal, 8)
            }

            HStack(spacing: 2) {
                ForEach(Array(model.candidates.prefix(5))) { candidate in
                    CandidateChip(candidate: candidate, compact: true) {
                        model.selectCandidate(at: candidate.id)
                    }
                }
            }

            if !model.candidates.isEmpty {
                Button {
                    model.toggleCandidatePanel()
                } label: {
                    Image(systemName: model.isCandidatePanelExpanded ? "chevron.down" : "chevron.up")
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

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 5
    )

    var body: some View {
        VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(model.candidates) { candidate in
                    CandidateChip(candidate: candidate, compact: false) {
                        model.selectCandidate(at: candidate.id)
                    }
                }
            }

            if model.hasPreviousPage || model.hasNextPage {
                HStack(spacing: 12) {
                    Button("上一页") {
                        model.changePage(backward: true)
                    }
                    .disabled(!model.hasPreviousPage)

                    Text("第 \(model.pageNumber + 1) 页")
                        .foregroundStyle(.secondary)

                    Button("下一页") {
                        model.changePage(backward: false)
                    }
                    .disabled(!model.hasNextPage)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.75))
        )
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -30 {
                        model.changePage(backward: false)
                    } else if value.translation.width > 30 {
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
            VStack(spacing: 0) {
                Text(candidate.text)
                    .font(.system(size: compact ? 18 : 17))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let comment = candidate.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 10 : 6)
            .frame(height: compact ? 30 : 32)
            .frame(maxWidth: .infinity)
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

struct KeyButton: View {
    let key: KeyboardKey
    let returnKeyLabel: String
    let onTap: (KeyboardKey) -> Void

    var body: some View {
        if case .none = key.action {
            Color.clear
        } else {
            Button {
                onTap(key)
            } label: {
                label
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeyboardKeyStyle(isSpecial: key.isSpecial))
        }
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage = key.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
        } else {
            Text(displayLabel)
                .font(.system(size: displayLabel.count > 1 ? 13 : 20))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var displayLabel: String {
        switch key.action {
        case .returnKey:
            return returnKeyLabel
        case .character(let character):
            return String(character)
        default:
            return key.label
        }
    }
}

struct KeyboardKeyStyle: ButtonStyle {
    let isSpecial: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSpecial ? Color.secondary : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSpecial ? Color(uiColor: .tertiarySystemFill) : Color(uiColor: .systemBackground))
                    .shadow(
                        color: Color.black.opacity(configuration.isPressed ? 0 : 0.12),
                        radius: 0,
                        x: 0,
                        y: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
