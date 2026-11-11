import Combine
import Foundation
import UIKit

@MainActor
final class KeyboardViewModel: ObservableObject {
    @Published private(set) var composition: String = ""
    @Published private(set) var candidates: [RimeCandidate] = []
    @Published private(set) var pageNumber = 0
    @Published private(set) var hasPreviousPage = false
    @Published private(set) var hasNextPage = false
    @Published private(set) var isCandidatePanelExpanded = false
    @Published private(set) var isPinyinSchema = true
    @Published private(set) var isAsciiMode = false
    @Published private(set) var isSingleCharMode = false
    @Published private(set) var isShifted = false
    @Published private(set) var layer: KeyboardLayer = .letters
    @Published private(set) var showsGlobe = true
    @Published var returnKeyLabel = "换行"

    let engine: RimeEngine
    @Published private(set) var settings = SharedStore.load()

    var onCommit: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onCompositionChange: ((String) -> Void)?
    var onFeedback: (() -> Void)?
    var onGlobe: (() -> Void)?
    var onCandidatePanelChange: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var candidateRefresh: DispatchWorkItem?
    private var inputGeneration = 0

    init(engine: RimeEngine = RimeEngineFactory.make()) {
        self.engine = engine
        isPinyinSchema = RimePreferences.selectedSchema != RimePreferences.wubi
        isAsciiMode = RimePreferences.isAsciiMode
        if isAsciiMode {
            engine.setOption("ascii_mode", value: true)
        }

        NotificationCenter.default.publisher(for: AppGroup.settingsChangedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.settings = SharedStore.load()
            }
            .store(in: &cancellables)
    }

    func tap(_ key: KeyboardKey) {
        guard key.action != .none else { return }

        switch key.action {
        case .character(let character):
            if isAsciiMode {
                onCommit?(String(character))
            } else {
                // 先更新显示，再让 Rime 在下一个 runloop 处理，避免文字上屏被引擎阻塞。
                composition += String(character)
                onCompositionChange?(composition)
                scheduleProcess(.character(character))
            }
            if isShifted {
                isShifted = false
            }

        case .shift:
            isShifted.toggle()

        case .delete:
            cancelCandidateRefresh()
            if composition.isEmpty {
                onDelete?()
            } else {
                composition.removeLast()
                onCompositionChange?(composition)
                scheduleProcess(.backspace)
            }

        case .space:
            if isAsciiMode || composition.isEmpty {
                onCommit?(" ")
            } else {
                scheduleProcess(.space)
            }

        case .returnKey:
            finishAndInsertNewline()

        case .globe:
            onGlobe?()

        case .layer(let newLayer):
            layer = newLayer
            isShifted = false
            resetComposition()

        case .text(let text):
            onCommit?(text)

        case .none:
            break
        }

        DispatchQueue.main.async { [weak self] in
            self?.onFeedback?()
        }
    }

    func commitText(_ text: String) {
        onCommit?(text)
        DispatchQueue.main.async { [weak self] in
            self?.onFeedback?()
        }
    }

    func selectCandidate(at index: Int) {
        cancelCandidateRefresh()
        let generation = inputGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.inputGeneration == generation else { return }
            let output = self.isSingleCharMode
                ? self.engine.selectCandidateGlobal(at: index)
                : self.engine.selectCandidate(at: index)
            self.apply(output)
        }
        notifyFeedback()
    }

    func changePage(backward: Bool) {
        guard !candidates.isEmpty else { return }
        cancelCandidateRefresh()
        let generation = inputGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.inputGeneration == generation else { return }
            self.apply(self.engine.changePage(backward: backward))
        }
        notifyFeedback()
    }

    func toggleCandidatePanel() {
        guard !candidates.isEmpty else { return }
        setCandidatePanelExpanded(!isCandidatePanelExpanded)
    }

    func toggleSchema() {
        let newSchema = isPinyinSchema ? RimePreferences.wubi : RimePreferences.pinyin
        RimePreferences.setSchema(newSchema)
        engine.selectSchema(newSchema)
        isPinyinSchema.toggle()
        resetComposition()
    }

    func toggleAsciiMode() {
        isAsciiMode.toggle()
        RimePreferences.setAsciiMode(isAsciiMode)
        engine.setOption("ascii_mode", value: isAsciiMode)
        if isAsciiMode {
            isSingleCharMode = false
        }
        resetComposition()
    }

    func toggleSingleCharMode() {
        isSingleCharMode.toggle()
        cancelCandidateRefresh()
        candidates = []
        pageNumber = 0
        hasPreviousPage = false
        hasNextPage = false

        if isSingleCharMode {
            refreshSingleCharCandidates()
        } else if !composition.isEmpty {
            scheduleCandidateRefresh()
        }
    }

    private func setCandidatePanelExpanded(_ expanded: Bool) {
        guard isCandidatePanelExpanded != expanded else { return }
        isCandidatePanelExpanded = expanded
        onCandidatePanelChange?()
    }

    func updateContext(
        autocapitalization: UITextAutocapitalizationType,
        keyboardType: UIKeyboardType,
        returnKeyType: UIReturnKeyType
    ) {
        switch keyboardType {
        case .numberPad, .phonePad, .decimalPad:
            layer = .numbers
        default:
            layer = .letters
        }

        isShifted = autocapitalization == .sentences || autocapitalization == .words

        switch returnKeyType {
        case .go:
            returnKeyLabel = "前往"
        case .search:
            returnKeyLabel = "搜索"
        case .send:
            returnKeyLabel = "发送"
        case .next:
            returnKeyLabel = "下一项"
        case .done:
            returnKeyLabel = "完成"
        case .join:
            returnKeyLabel = "加入"
        case .route:
            returnKeyLabel = "路线"
        case .emergencyCall:
            returnKeyLabel = "紧急呼叫"
        case .continue:
            returnKeyLabel = "继续"
        default:
            returnKeyLabel = "换行"
        }
    }

    func setShowsGlobe(_ shows: Bool) {
        showsGlobe = shows
    }

    func reloadSettings() {
        settings = SharedStore.load()
    }

    func resetComposition() {
        inputGeneration += 1
        cancelCandidateRefresh()
        engine.reset()
        composition = ""
        candidates = []
        pageNumber = 0
        hasPreviousPage = false
        hasNextPage = false
        setCandidatePanelExpanded(false)
        onCompositionChange?("")
    }

    private func scheduleProcess(_ key: RimeKey) {
        let generation = inputGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.inputGeneration == generation else { return }
            let output = self.engine.processKey(key)
            if key == .space {
                self.apply(output)
            } else {
                self.applyFast(output)
            }
        }
    }

    /// 字符/退格已经做了乐观上屏，异步结果只处理提交和候选，不再改 marked text。
    private func applyFast(_ output: RimeOutput) {
        if let commit = output.commit, !commit.isEmpty {
            onCommit?(commit)
            composition = ""
            onCompositionChange?("")
        }

        if composition.isEmpty {
            cancelCandidateRefresh()
            candidates = []
            pageNumber = 0
            hasPreviousPage = false
            hasNextPage = false
            setCandidatePanelExpanded(false)
        } else {
            scheduleCandidateRefresh()
        }
    }

    private func finishAndInsertNewline() {
        let generation = inputGeneration
        let hadComposition = !composition.isEmpty
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.inputGeneration == generation && hadComposition {
                self.apply(self.engine.commitComposition())
            }
            self.resetComposition()
            self.onCommit?("\n")
        }
    }

    private func notifyFeedback() {
        DispatchQueue.main.async { [weak self] in
            self?.onFeedback?()
        }
    }

    private func apply(_ output: RimeOutput, notifyComposition: Bool = true) {
        let previous = composition
        if let commit = output.commit, !commit.isEmpty {
            onCommit?(commit)
        }
        composition = output.composition

        if output.candidatesStale {
            if output.composition.isEmpty {
                cancelCandidateRefresh()
                candidates = []
                pageNumber = 0
                hasPreviousPage = false
                hasNextPage = false
                setCandidatePanelExpanded(false)
            } else {
                scheduleCandidateRefresh()
            }
        } else {
            cancelCandidateRefresh()
            candidates = output.candidates
            pageNumber = output.pageNumber
            hasPreviousPage = output.hasPreviousPage
            hasNextPage = output.hasMorePages
            if output.composition.isEmpty {
                setCandidatePanelExpanded(false)
            }
        }

        if notifyComposition || output.composition != previous {
            onCompositionChange?(output.composition)
        }

        if isSingleCharMode && !composition.isEmpty {
            refreshSingleCharCandidates()
        }
    }

    private func scheduleCandidateRefresh() {
        candidateRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }

            if self.isSingleCharMode {
                self.refreshSingleCharCandidates()
                return
            }

            let output = self.engine.refreshCandidates()
            guard !output.composition.isEmpty else { return }
            self.candidates = output.candidates
            self.pageNumber = output.pageNumber
            self.hasPreviousPage = output.hasPreviousPage
            self.hasNextPage = output.hasMorePages
        }
        candidateRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
    }

    private func refreshSingleCharCandidates() {
        guard isSingleCharMode, !composition.isEmpty else {
            candidates = []
            pageNumber = 0
            hasPreviousPage = false
            hasNextPage = false
            return
        }

        let all = engine.allCandidates(limit: 200)
        var seen = Set<String>()
        var singles: [RimeCandidate] = []
        for candidate in all where candidate.text.count == 1 {
            if seen.insert(candidate.text).inserted {
                singles.append(candidate)
            }
        }

        candidates = Array(singles.prefix(30))
        pageNumber = 0
        hasPreviousPage = false
        hasNextPage = false

        if !candidates.isEmpty {
            setCandidatePanelExpanded(true)
        }
    }

    private func cancelCandidateRefresh() {
        candidateRefresh?.cancel()
        candidateRefresh = nil
    }
}
