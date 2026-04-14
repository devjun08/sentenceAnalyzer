import AppKit
import SwiftUI
import Translation

class AnalysisWindow: NSObject {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnalysisView>?
    private var viewModel = AnalysisViewModel()

    func show() {
        if panel == nil { createPanel() }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setStatus(_ message: String) {
        viewModel.statusMessage = message
        viewModel.isLoading = true
        show()
    }

    func setContent(text: String) {
        viewModel.startAnalysis(text: text)
        show()
    }

    private func createPanel() {
        let screenFrame = NSScreen.main?.frame ?? .zero
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 700
        let xPos = screenFrame.maxX - panelWidth - 20
        let yPos = (screenFrame.height - panelHeight) / 2

        let panel = NSPanel(
            contentRect: NSRect(x: xPos, y: yPos, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "문장 분석"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.97)
        panel.titlebarAppearsTransparent = true

        let hosting = NSHostingView(rootView: AnalysisView(viewModel: viewModel))
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)

        self.panel = panel
        self.hostingView = hosting
    }
}

// MARK: - ViewModel

class AnalysisViewModel: ObservableObject {
    // 분석
    @Published var analyses: [SentenceAnalysis] = []
    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var rawText = ""

    // 채팅
    @Published var chatInput = ""
    @Published var chatCurrentQ = ""
    @Published var chatAnswer = ""
    @Published var chatLoading = false

    func startAnalysis(text: String) {
        rawText = text
        isLoading = true
        chatCurrentQ = ""
        chatAnswer = ""

        let sentences = AnalysisManager.shared.splitIntoSentences(text)
        statusMessage = "\(sentences.count)개 문장 인식됨"

        analyses = sentences.map {
            SentenceAnalysis(original: $0, translation: nil, structure: nil, questions: nil)
        }

        var basicCompleted = 0
        for i in sentences.indices {
            AnalysisManager.shared.analyze(
                sentences[i],
                onBasic: { [weak self] analysis in
                    guard let self = self, i < self.analyses.count else { return }
                    self.analyses[i].structure = analysis.structure
                    self.analyses[i].structureError = analysis.structureError
                    basicCompleted += 1
                    if basicCompleted == sentences.count {
                        self.isLoading = false
                        self.statusMessage = "분석 완료 ✓"
                    }
                },
                onQuestions: { [weak self] _, questions, error in
                    guard let self = self, i < self.analyses.count else { return }
                    self.analyses[i].questions = questions
                    self.analyses[i].questionsError = error
                }
            )
        }
    }

    // Q 버튼 탭 → 입력창 자동 채우기
    func setQuestion(_ q: String) {
        chatInput = q
    }

    // 질문 제출
    func retryAnalysis(index: Int) {
        guard index < analyses.count else { return }
        let sentence = analyses[index].original
        analyses[index].structure = nil
        analyses[index].structureError = nil
        analyses[index].questions = nil
        analyses[index].questionsError = nil

        AnalysisManager.shared.analyze(
            sentence,
            onBasic: { [weak self] analysis in
                guard let self = self, index < self.analyses.count else { return }
                self.analyses[index].structure = analysis.structure
                self.analyses[index].structureError = analysis.structureError
            },
            onQuestions: { [weak self] _, questions, error in
                guard let self = self, index < self.analyses.count else { return }
                self.analyses[index].questions = questions
                self.analyses[index].questionsError = error
            }
        )
    }

    func submitQuestion() {
        guard !chatInput.isEmpty, !chatLoading else { return }
        chatCurrentQ = chatInput
        chatInput = ""
        chatAnswer = ""
        chatLoading = true

        AnalysisManager.shared.askQuestion(chatCurrentQ, context: rawText) { [weak self] answer in
            self?.chatAnswer = answer
            self?.chatLoading = false
        }
    }
}

// MARK: - AnalysisView

struct AnalysisView: View {
    @ObservedObject var viewModel: AnalysisViewModel

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.12).ignoresSafeArea()

            VStack(spacing: 0) {

                // 헤더
                HStack {
                    Image(systemName: "text.magnifyingglass").foregroundColor(.blue)
                    Text("Sentence Analyzer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    }
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(red: 0.12, green: 0.12, blue: 0.15))

                Divider().background(Color.white.opacity(0.1))

                // 카드 목록
                if viewModel.analyses.isEmpty {
                    VStack(spacing: 12) {
                        if viewModel.isLoading {
                            Text(viewModel.statusMessage)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.analyses.indices, id: \.self) { i in
                                SentenceCard(
                                    analysis: $viewModel.analyses[i],
                                    onQuestionTapped: { q in viewModel.setQuestion(q) },
                                    onRetry: { viewModel.retryAnalysis(index: i) }
                                )
                            }
                        }
                        .padding(16)
                    }
                }

                // 채팅 영역
                ChatView(viewModel: viewModel)
            }
        }
        // 앱 첫 실행 시 언어팩 선제 다운로드
        .prepareAppleTranslation()
    }
}

// MARK: - ChatView

struct ChatView: View {
    @ObservedObject var viewModel: AnalysisViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.15))

            // 답변 영역 — 질문이 있을 때만 표시
            if !viewModel.chatCurrentQ.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {

                        // 질문 버블
                        HStack {
                            Spacer()
                            Text(viewModel.chatCurrentQ)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.blue.opacity(0.35))
                                .cornerRadius(10)
                        }

                        // 답변
                        if viewModel.chatLoading {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.6).tint(.gray)
                                Text("답변 생성 중...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                        } else if !viewModel.chatAnswer.isEmpty {
                            Text(viewModel.chatAnswer)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                    }
                    .padding(12)
                    .animation(.easeOut(duration: 0.25), value: viewModel.chatAnswer)
                }
                .frame(maxHeight: 160)
                .background(Color(red: 0.11, green: 0.11, blue: 0.15))

                Divider().background(Color.white.opacity(0.1))
            }

            // 입력창
            HStack(spacing: 10) {
                TextField("궁금한 점 입력 또는 위 Q 탭…", text: $viewModel.chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .focused($inputFocused)
                    .onSubmit { viewModel.submitQuestion() }

                Button(action: viewModel.submitQuestion) {
                    Image(systemName: viewModel.chatLoading ? "hourglass" : "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(
                            viewModel.chatInput.isEmpty || viewModel.chatLoading ? .gray : .blue
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.chatInput.isEmpty || viewModel.chatLoading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.13, green: 0.13, blue: 0.17))
        }
    }
}

// MARK: - SentenceCard

struct SentenceCard: View {
    @Binding var analysis: SentenceAnalysis
    var onQuestionTapped: (String) -> Void
    var onRetry: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 원문
            Text(analysis.original)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().background(Color.white.opacity(0.1))

            TranslationRow(translation: analysis.translation, pulse: pulse)

            StructureSection(
                structure: analysis.structure,
                structureError: analysis.structureError,
                pulse: pulse,
                onRetry: onRetry
            )

            QuestionsSection(
                questions: analysis.questions,
                questionsError: analysis.questionsError,
                pulse: pulse,
                onQuestionTapped: onQuestionTapped,
                onRetry: onRetry
            )
        }
        .padding(14)
        .background(Color(red: 0.16, green: 0.16, blue: 0.2))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.easeOut(duration: 0.3), value: analysis.translation)
        .animation(.easeOut(duration: 0.3), value: analysis.structure?.count)
        .animation(.easeOut(duration: 0.3), value: analysis.questions?.count)
        .onAppear { pulse = true }
        .appleTranslation(text: analysis.original, result: $analysis.translation)
    }
}

// MARK: - 번역 행

private struct TranslationRow: View {
    let translation: String?
    let pulse: Bool

    var body: some View {
        if let translation = translation {
            HStack(alignment: .top, spacing: 8) {
                Text("뜻")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.2)).cornerRadius(4)
                Text(translation)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            SkeletonBar(width: 200, height: 14, pulse: pulse)
        }
    }
}

// MARK: - 문장 구조 섹션

private struct StructureSection: View {
    let structure: [SentenceComponent]?
    let structureError: String?
    let pulse: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "문장 구조", isDone: structure != nil)
            if let structure = structure {
                if structure.isEmpty {
                    ErrorRow(message: structureError, onRetry: onRetry)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(structure) { ComponentChip(component: $0) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                SkeletonChips(pulse: pulse)
            }
        }
    }
}

// MARK: - 문법 질문 섹션

private struct QuestionsSection: View {
    let questions: [String]?
    let questionsError: String?
    let pulse: Bool
    let onQuestionTapped: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "이런 건 왜 이럴까?", isDone: questions != nil)
            if let questions = questions {
                if questions.isEmpty {
                    ErrorRow(message: questionsError, onRetry: onRetry)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
                            QuestionButton(question: q, onTap: { onQuestionTapped(q) })
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                SkeletonBar(width: 160, height: 14, pulse: pulse)
            }
        }
    }
}

// MARK: - 재사용 컴포넌트

private struct SectionTitle: View {
    let title: String
    let isDone: Bool
    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
            if !isDone {
                ProgressView().scaleEffect(0.5).tint(.gray)
            }
        }
    }
}

private struct ErrorRow: View {
    let message: String?
    let onRetry: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text(message.map { String($0.prefix(80)) } ?? "분석 실패")
                .font(.system(size: 11))
                .foregroundColor(.orange.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRetry) {
                Text("재시도")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct QuestionButton: View {
    let question: String
    let onTap: () -> Void
    private let accent = Color(hex: "#4A90E2") ?? .blue
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Text("Q")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(accent)
                    .frame(width: 16, height: 16)
                    .background(accent.opacity(0.15))
                    .cornerRadius(3)
                Text(question)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SkeletonBar: View {
    let width: CGFloat
    let height: CGFloat
    let pulse: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(pulse ? 0.1 : 0.04))
            .frame(width: width, height: height)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
    }
}

private struct SkeletonChips: View {
    let pulse: Bool
    private let widths: [CGFloat] = [52, 44, 60, 48]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(widths, id: \.self) { w in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(pulse ? 0.08 : 0.04))
                    .frame(width: w, height: 36)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            }
        }
    }
}

// MARK: - ComponentChip

struct ComponentChip: View {
    let component: SentenceComponent

    var chipColor: Color { Color(hex: component.color) ?? .gray }

    var body: some View {
        VStack(spacing: 2) {
            Text(component.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            if !component.hint.isEmpty {
                Text(component.hint)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }
            Text(component.role)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(chipColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(chipColor.opacity(0.15))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(chipColor.opacity(0.4), lineWidth: 1))
        .cornerRadius(6)
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map {
            $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        }.reduce(0) { $0 + $1 + spacing }
        return CGSize(width: proposal.width ?? 0, height: max(height - spacing, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in computeRows(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && !rows.last!.isEmpty {
                rows.append([]); x = 0
            }
            rows[rows.count - 1].append(subview)
            x += size.width + spacing
        }
        return rows
    }
}

// MARK: - Apple Translation Helper

@available(macOS 15.0, *)
private struct TranslationPrepareModifier: ViewModifier {
    @State private var config: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onAppear {
                config = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "ko")
                )
            }
            .translationTask(config) { session in
                try? await session.prepareTranslation()
            }
    }
}

@available(macOS 15.0, *)
private struct AppleTranslationModifier: ViewModifier {
    let text: String
    @Binding var result: String?
    @State private var config: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onAppear {
                config = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "ko")
                )
            }
            .translationTask(config) { session in
                do {
                    let response = try await session.translate(text)
                    result = response.targetText
                } catch {
                    result = ""
                    print("Apple Translation 실패: \(error)")
                }
            }
    }
}

extension View {
    @ViewBuilder
    func appleTranslation(text: String, result: Binding<String?>) -> some View {
        if #available(macOS 15.0, *) {
            self.modifier(AppleTranslationModifier(text: text, result: result))
        } else {
            self.onAppear { result.wrappedValue = "" }
        }
    }

    @ViewBuilder
    func prepareAppleTranslation() -> some View {
        if #available(macOS 15.0, *) {
            self.modifier(TranslationPrepareModifier())
        } else {
            self
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexStr = hexStr.hasPrefix("#") ? String(hexStr.dropFirst()) : hexStr
        guard hexStr.count == 6, let value = UInt64(hexStr, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
