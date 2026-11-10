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
            }

            ForEach(rows.indices, id: \.self) { index in
                KeyboardRowView(row: rows[index], model: model)
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
        HStack(spacing: 4) {
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

            if model.hasPreviousPage {
                pageButton(systemImage: "chevron.left") {
                    model.changePage(backward: true)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(model.candidates) { candidate in
                        Button {
                            model.selectCandidate(at: candidate.id)
                        } label: {
                            VStack(spacing: 0) {
                                Text(candidate.text)
                                    .font(.system(size: 18))
                                if let comment = candidate.comment, !comment.isEmpty {
                                    Text(comment)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if model.hasNextPage {
                pageButton(systemImage: "chevron.right") {
                    model.changePage(backward: false)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.55))
        )
    }

    private func pageButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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

struct KeyboardRowView: View {
    let row: [KeyboardKey]
    @ObservedObject var model: KeyboardViewModel

    private let spacing: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let totalUnits = row.reduce(0.0) { $0 + $1.width }
            let unit = max(
                0,
                (proxy.size.width - spacing * CGFloat(max(0, row.count - 1))) / CGFloat(max(totalUnits, 1))
            )

            HStack(spacing: spacing) {
                ForEach(row) { key in
                    KeyButton(key: key, model: model)
                        .frame(width: unit * CGFloat(key.width))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct KeyButton: View {
    let key: KeyboardKey
    @ObservedObject var model: KeyboardViewModel

    var body: some View {
        if case .none = key.action {
            Color.clear
        } else {
            Button {
                model.tap(key)
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
            return model.returnKeyLabel
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
