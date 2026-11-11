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

    init(engine: RimeEngine = RimeEngineFactory.make()) {
        self.engine = engine
        isPinyinSchema = RimePreferences.selectedSchema != RimePreferences.wubi
        NotificationCenter.default.publisher(for: AppGroup.settingsChangedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.settings = SharedStore.load()
            }
            .store(in: &cancellables)
    }

    func tap(_ key: KeyboardKey) {
        guard key.action != .none else { return }
        onFeedback?()

        switch key.action {
        case .character(let character):
            let output = engine.processKey(.character(character))
            apply(output)
            if isShifted {
                isShifted = false
            }
        case .shift:
            isShifted.toggle()
        case .delete:
            if composition.isEmpty {
                onDelete?()
            } else {
                apply(engine.processKey(.backspace))
            }
        case .space:
            if composition.isEmpty {
                onCommit?(" ")
            } else {
                apply(engine.processKey(.space))
            }
        case .returnKey:
            if !composition.isEmpty {
                apply(engine.commitComposition())
            }
            resetComposition()
            onCommit?("\n")
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
    }

    func selectCandidate(at index: Int) {
        cancelCandidateRefresh()
        onFeedback?()
        apply(engine.selectCandidate(at: index))
    }

    func changePage(backward: Bool) {
        guard !candidates.isEmpty else { return }
        cancelCandidateRefresh()
        onFeedback?()
        apply(engine.changePage(backward: backward))
    }

    func toggleCandidatePanel() {
        guard !candidates.isEmpty else { return }
        setCandidatePanelExpanded(!isCandidatePanelExpanded)
    }

    func toggleSchema() {
        let newSchema = isPinyinSchema ? RimePreferences.wubi : RimePreferences.pinyin
        RimePreferences.setSchema(newSchema)
        engine.selectSchema(newSchema)
        resetComposition()
        isPinyinSchema = !isPinyinSchema
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
        guard !composition.isEmpty || !candidates.isEmpty else { return }
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

    private func apply(_ output: RimeOutput) {
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

        onCompositionChange?(output.composition)
    }

    private func scheduleCandidateRefresh() {
        candidateRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
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

    private func cancelCandidateRefresh() {
        candidateRefresh?.cancel()
        candidateRefresh = nil
    }
}
