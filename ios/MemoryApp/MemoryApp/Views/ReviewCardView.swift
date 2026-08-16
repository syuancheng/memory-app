import AVFoundation
import SwiftUI

enum CardSide {
    case front
    case back
}

enum ReviewEnglishVoice: String, CaseIterable, Identifiable {
    case american
    case british

    var id: String { rawValue }

    var title: String {
        switch self {
        case .american: return "American"
        case .british:  return "British"
        }
    }

    var languageCode: String {
        switch self {
        case .american: return "en-US"
        case .british:  return "en-GB"
        }
    }
}

struct ReviewCardView: View {
    var mode: StudyMode = .review
    let card: ReviewCard
    let progressText: String
    let gradePreviews: [ReviewGradePreview]
    let resetToken: Int
    let onClose: () -> Void
    let onDelete: () async -> Void
    let onMaster: () async -> Void
    let onRate: (Rating, Int) async -> Bool

    @State private var side: CardSide = .front
    @State private var revealedTokenIndexes: Set<Int> = []
    @State private var isSubmitting = false
    @State private var isAdvancing = false
    @StateObject private var speechManager = SpeechManager.shared
    @AppStorage("reviewEnglishVoice") private var englishVoice = ReviewEnglishVoice.american.rawValue

    /// 两种方向唯一的差异：中→英逐词遮挡英文答案；英→中中文翻译直接呈现。
    private var masksAnswer: Bool { card.cardDirection.masksAnswer }

    private var allTokensRevealed: Bool {
        answerMaskTokens.allSatisfy { revealedTokenIndexes.contains($0.index) }
    }

    private var answerMaskTokens: [AnswerToken] {
        if !card.answerTokens.isEmpty {
            return card.answerTokens
        }
        return card.answerText
            .split(separator: " ")
            .enumerated()
            .map { AnswerToken(text: String($0.element), index: $0.offset) }
    }

    private var contextText: String {
        let setName = card.set.name.isEmpty ? mode.title : card.set.name
        return "\(card.subjectName ?? "English") · \(setName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppLayout.screenMargin)
                .padding(.top, AppSpace.md)

            if side == .front {
                frontCard
                    .padding(.horizontal, AppLayout.screenMargin)
                    .padding(.top, AppSpace.xxl)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))

                Spacer(minLength: AppSpace.xxl)
            } else {
                ScrollView(showsIndicators: false) {
                    backCard
                        .padding(.horizontal, AppLayout.screenMargin)
                        .padding(.top, AppSpace.xxl)
                        .padding(.bottom, AppSpace.lg)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))

                if !isAdvancing {
                    feedbackBar
                        .padding(.horizontal, AppLayout.screenMargin)
                        .padding(.top, AppSpace.sm)
                        .padding(.bottom, AppSpace.md)
                        .background(AppColor.surfaceBase)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(AppColor.separator)
                                .frame(height: AppLayout.separatorHeight)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColor.surfaceBase.ignoresSafeArea())
        .animation(AppMotion.standard, value: side)
        .onChange(of: card.id) { _, _ in
            resetCardInteractionWithoutAnimation()
        }
        .onChange(of: resetToken) { _, _ in
            resetCardInteractionWithoutAnimation()
        }
        .onDisappear {
            stopSpeakingAnswer()
        }
    }

    // 「沉浸式学习会话头」—— 样式 A 的受控变体，全 App 仅此一处：
    //   与样式 A 同构（左 dismiss + 右溢出操作、同一批 AppIconButton），
    //   但标题位换成进度药丸、且不用原生导航栏 —— 因为卡面需要占满整屏高度。
    //   离开会话是"关闭"而非"返回"，故用 xmark。
    private var header: some View {
        VStack(spacing: AppSpace.sm) {
            ZStack {
                progressPill

                HStack {
                    AppIconButton(icon: AppIcon.close, style: .plain, action: onClose)
                        .accessibilityLabel("Close session")

                    Spacer()

                    moreButton
                }
            }
            .frame(height: AppLayout.minHitTarget)

            Text(contextText)
                .appText(AppType.caption, color: AppColor.textTertiary)
                .lineLimit(1)
        }
    }

    private var progressPill: some View {
        Text(progressText)
            .appText(AppType.label, color: AppColor.primaryOnSoft)
            .monospacedDigit()
            .padding(.horizontal, AppSpace.md)
            .frame(height: AppLayout.buttonHeightSmall)
            .background(AppColor.primarySoft, in: Capsule())
    }

    private var moreButton: some View {
        Menu {
            Button {
                Task {
                    await masterCard()
                }
            } label: {
                Label("Mark mastered", systemImage: "checkmark.seal")
            }
            .disabled(isSubmitting)

            Button(role: .destructive) {
                Task {
                    await deleteCard()
                }
            } label: {
                Label("Delete card", systemImage: "trash")
            }
            .disabled(isSubmitting)
        } label: {
            Circle()
                .fill(AppColor.surface)
                .overlay { Circle().strokeBorder(AppColor.border, lineWidth: AppLayout.hairline) }
                .frame(width: AppLayout.navIconButton, height: AppLayout.navIconButton)
                .overlay {
                    Image(systemName: AppIcon.more)
                        .font(AppIcon.font(AppLayout.iconMD))
                        .foregroundStyle(AppColor.iconDefault)
                }
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }

    private var frontCard: some View {
        Button {
            side = .back
        } label: {
            FlashcardSurface {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: AppSpace.giant)

                    // 长句自动缩放而非按方向切字号 —— 溢出取决于文本长度，与方向无关
                    Text(card.frontText)
                        .appText(AppType.title1)
                        .minimumScaleFactor(0.68)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: AppSpace.giant)

                    Text("Tap to reveal")
                        .appText(AppType.label, color: AppColor.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(AppSpace.xl)
                .frame(maxWidth: .infinity, minHeight: 440, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show hints")
    }

    private var backCard: some View {
        VStack(spacing: AppLayout.cardGap) {
            maskedAnswerCard
            grammarHintCard
        }
    }

    private var maskedAnswerCard: some View {
        FlashcardSurface {
            VStack(alignment: .leading, spacing: AppSpace.sm) {
                HStack {
                    Spacer()

                    answerCardIconButton(
                        icon: speechManager.isSpeaking ? "speaker.slash" : "speaker.wave.2",
                        tint: speechManager.isSpeaking ? AppColor.primary : AppColor.iconDefault,
                        accessibilityLabel: speechManager.isSpeaking ? "Stop answer audio" : "Play answer audio"
                    ) {
                        toggleAnswerSpeech()
                    }
                }

                answerContent
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)

                // 不遮挡时没有"揭示"这个动作，按钮无意义
                if masksAnswer {
                    HStack {
                        Spacer()

                        answerCardIconButton(
                            icon: "eye",
                            tint: allTokensRevealed ? AppColor.disabledIcon : AppColor.iconDefault,
                            accessibilityLabel: "Reveal full answer",
                            isEnabled: !allTokensRevealed
                        ) {
                            revealAllTokens()
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpace.xl)
            .padding(.top, AppSpace.sm)
            .padding(.bottom, AppSpace.sm)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        }
        .contentShape(AppRadius.shape(AppRadius.xl))
        .onTapGesture {
            returnToFront()
        }
    }

    @ViewBuilder
    private var answerContent: some View {
        if !masksAnswer {
            plainAnswerText
        } else {
            FlowLayout(spacing: AppLayout.answerTokenGap, lineSpacing: AppSpace.md) {
                ForEach(answerMaskTokens) { token in
                    Button {
                        revealedTokenIndexes.insert(token.index)
                    } label: {
                        answerTokenView(token)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealedTokenIndexes.contains(token.index) ? token.text : "Reveal word")
                }
            }
        }
    }

    private func answerCardIconButton(
        icon: String,
        tint: Color = AppColor.iconDefault,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppIcon.font(AppLayout.iconSM))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    /// 英→中：翻译直接呈现，无遮挡、无交互。
    private var plainAnswerText: some View {
        Text(card.answerText)
            .appText(AppType.headline)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func answerTokenView(_ token: AnswerToken) -> some View {
        let isRevealed = revealedTokenIndexes.contains(token.index)
        let tokenText = Text(token.text)
            .font(.system(size: AppType.headline.size, weight: AppType.headline.weight))

        return ZStack {
            tokenText
                .foregroundStyle(.clear)
                .padding(.vertical, AppSpace.xs / 2)
                .background {
                    if !isRevealed {
                        AppRadius.shape(AppRadius.sm)
                            .fill(AppColor.neutral200)
                    }
                }

            if isRevealed {
                tokenText
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
        .contentShape(AppRadius.shape(AppRadius.sm))
    }

    private var grammarHintCard: some View {
        FlashcardSurface {
            Group {
                if card.grammarPhrases.isEmpty {
                    Text("No phrase notes for this card.")
                        .appText(AppType.body, color: AppColor.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(card.grammarPhrases) { phrase in
                            VStack(alignment: .leading, spacing: AppSpace.xs) {
                                Text(phrase.text)
                                    .appText(AppType.headline)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(phrase.note)
                                    .appText(AppType.body, color: AppColor.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, AppSpace.md)
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpace.xl)
            .padding(.vertical, AppSpace.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .contentShape(AppRadius.shape(AppRadius.xl))
        .onTapGesture {
            returnToFront()
        }
    }

    private var feedbackBar: some View {
        HStack(spacing: AppSpace.sm) {
            ForEach(Rating.allCases, id: \.rawValue) { rating in
                Button {
                    Task {
                        await submit(rating)
                    }
                } label: {
                    VStack(spacing: AppSpace.xs / 2) {
                        Text(rating.title)
                            .appTextMetrics(AppType.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(intervalText(for: rating))
                            .appTextMetrics(AppType.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: AppLayout.buttonHeightLarge)
                }
                .disabled(isSubmitting || preview(for: rating) == nil)
                .buttonStyle(FeedbackButtonStyle(rating: rating))
            }
        }
    }

    private func preview(for rating: Rating) -> ReviewGradePreview? {
        gradePreviews.first { $0.grade == rating }
    }

    private func intervalText(for rating: Rating) -> String {
        guard let intervalSeconds = preview(for: rating)?.intervalSeconds else {
            return "..."
        }
        return ReviewIntervalFormatter.string(seconds: intervalSeconds)
    }

    private func resetCardInteraction() {
        stopSpeakingAnswer()
        side = .front
        revealedTokenIndexes = []
        isSubmitting = false
        isAdvancing = false
    }

    private func resetCardInteractionWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resetCardInteraction()
        }
    }

    private func submit(_ rating: Rating) async {
        guard preview(for: rating) != nil else {
            return
        }
        stopSpeakingAnswer()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isSubmitting = true
            isAdvancing = true
        }
        let didSubmit = await onRate(rating, revealedTokenIndexes.count)
        if !didSubmit {
            isSubmitting = false
            isAdvancing = false
        }
    }

    private func revealAllTokens() {
        revealedTokenIndexes.formUnion(answerMaskTokens.map(\.index))
    }

    private func returnToFront() {
        stopSpeakingAnswer()
        side = .front
    }

    private func deleteCard() async {
        stopSpeakingAnswer()
        isSubmitting = true
        await onDelete()
        isSubmitting = false
    }

    private func masterCard() async {
        stopSpeakingAnswer()
        isSubmitting = true
        await onMaster()
        isSubmitting = false
    }

    private func toggleAnswerSpeech() {
        let selectedVoice = ReviewEnglishVoice(rawValue: englishVoice) ?? .american
        speechManager.toggle(card.answerText, voice: selectedVoice)
    }

    private func stopSpeakingAnswer() {
        speechManager.stop()
    }
}

final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()

    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    func toggle(_ text: String, voice: ReviewEnglishVoice) {
        if synthesizer.isSpeaking {
            stop()
            return
        }

        speak(text, voice: voice)
    }

    func speak(_ text: String, voice: ReviewEnglishVoice) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = preferredVoice(for: voice.languageCode)
        utterance.rate = 0.42
        utterance.pitchMultiplier = 1.02
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.35

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    private func preferredVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if languageCode == ReviewEnglishVoice.american.languageCode {
            if let avaVoice = voices.first(where: { voice in
                isAvaVoice(voice)
                    && (voice.quality == .premium || voice.quality == .enhanced)
            }) {
                return avaVoice
            }

            if let fallbackAva = voices.first(where: isAvaVoice) {
                return fallbackAva
            }

            return AVSpeechSynthesisVoice(language: ReviewEnglishVoice.american.languageCode)
        }

        if let premiumVoice = voices.first(where: { $0.language == languageCode && $0.quality == .premium }) {
            return premiumVoice
        }
        if let enhancedVoice = voices.first(where: { $0.language == languageCode && $0.quality == .enhanced }) {
            return enhancedVoice
        }
        return AVSpeechSynthesisVoice(language: languageCode)
    }

    private func isAvaVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.identifier.localizedCaseInsensitiveContains("Ava")
            || voice.name.localizedCaseInsensitiveContains("Ava")
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

/// 卡面容器。改造前是暖米色 #FFFCF7 + #F1E7D8 描边 —— 旧配色主题的残留，
/// 等于全 App 第四套表面色。现归入标准 surface + border。
private struct FlashcardSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .appSurface(.card, fill: AppColor.surface, radius: AppRadius.xl)
    }
}

private struct FeedbackButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let rating: Rating

    func makeBody(configuration: Configuration) -> some View {
        let shape = AppRadius.shape(AppRadius.md)
        return configuration.label
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed), in: shape)
            .overlay {
                if stroke != .clear {
                    shape.strokeBorder(stroke, lineWidth: AppLayout.hairline)
                }
            }
            .scaleEffect(configuration.isPressed ? AppMotion.pressScale : 1)
            .animation(AppMotion.instant, value: configuration.isPressed)
    }

    /// good 是推荐动作 → 唯一使用 primary 的一档；其余走语义色的 *Text 变体（均 ≥5.4:1）
    private var foreground: Color {
        guard isEnabled else { return AppColor.disabledText }
        switch rating {
        case .again: return AppColor.dangerText
        case .hard:  return AppColor.warningText
        case .good:  return AppColor.onPrimary
        case .easy:  return AppColor.successText
        }
    }

    private func background(pressed: Bool) -> Color {
        guard isEnabled else { return AppColor.disabledFill }
        switch rating {
        case .again: return pressed ? AppColor.surfacePressed : AppColor.dangerSoft
        case .hard:  return pressed ? AppColor.surfacePressed : AppColor.warningSoft
        case .good:  return pressed ? AppColor.primaryPressed : AppColor.primary
        case .easy:  return pressed ? AppColor.surfacePressed : AppColor.successSoft
        }
    }

    private var stroke: Color {
        guard isEnabled else { return AppColor.disabledBorder }
        return rating == .good ? .clear : AppColor.border
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        return CGSize(width: maxWidth, height: rows.reduce(CGFloat.zero) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = origin.x
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: origin.y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            origin.y += row.height + lineSpacing
        }
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !current.items.isEmpty && current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.items.append(RowItem(subview: subview, size: size))
            current.width += (current.items.count == 1 ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }
}

enum ReviewIntervalFormatter {
    static func string(seconds rawSeconds: Int) -> String {
        let seconds = max(0, rawSeconds)
        if seconds < 60 {
            return "<1m"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        let days = hours / 24
        if days < 14 {
            return "\(days)d"
        }

        let weeks = days / 7
        if days < 30 {
            return "\(weeks)w"
        }

        let months = days / 30
        if days < 365 {
            return "\(months)mo"
        }

        let years = days / 365
        return "\(years)y"
    }
}
