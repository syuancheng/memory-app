import SwiftUI

enum CardSide {
    case front
    case back
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
    let onRate: (Rating, Int) async -> Void

    @State private var side: CardSide = .front
    @State private var revealedTokenIndexes: Set<Int> = []
    @State private var isSubmitting = false

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
        let tag = card.tags.first?.name ?? mode.title
        return "\(card.subjectName ?? "English") · \(tag)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 18)

            if side == .front {
                frontCard
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))

                Spacer(minLength: 28)
            } else {
                ScrollView(showsIndicators: false) {
                    backCard
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                        .padding(.bottom, 18)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))

                feedbackBar
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                    .background(AppSurface.background)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppSurface.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.18), value: side)
        .onChange(of: card.id) { _, _ in
            resetCardInteraction()
        }
        .onChange(of: resetToken) { _, _ in
            resetCardInteraction()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                progressPill

                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppSurface.text)
                            .frame(width: 44, height: 44)
                            .background(AppSurface.cardSubtle)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(AppSurface.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Spacer()

                    moreButton
                }
            }
            .frame(height: 44)

            Text(contextText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppSurface.muted)
                .lineLimit(1)
        }
    }

    private var progressPill: some View {
        Text(progressText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppSurface.accent)
            .monospacedDigit()
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(AppSurface.accentSoft)
            .clipShape(Capsule())
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
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppSurface.text)
                .frame(width: 44, height: 44)
                .background(AppSurface.cardSubtle)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(AppSurface.line, lineWidth: 1)
                )
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
                    Spacer(minLength: 82)

                    Text(card.frontText)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppSurface.text)
                        .lineSpacing(7)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 78)

                    Text("Tap to reveal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppSurface.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: 470, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show hints")
    }

    private var backCard: some View {
        VStack(spacing: 12) {
            maskedAnswerCard
            grammarHintCard
        }
    }

    private var maskedAnswerCard: some View {
        FlashcardSurface {
            VStack(alignment: .leading, spacing: 0) {
                FlowLayout(spacing: 6, lineSpacing: 12) {
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
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 50)
            .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    revealAllTokens()
                } label: {
                    Image(systemName: allTokensRevealed ? "eye.fill" : "eye")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppSurface.muted.opacity(allTokensRevealed ? 0.58 : 1))
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(allTokensRevealed)
                .padding(.trailing, 18)
                .padding(.bottom, 16)
                .accessibilityLabel("Reveal full answer")
            }
        }
    }

    private func answerTokenView(_ token: AnswerToken) -> some View {
        let isRevealed = revealedTokenIndexes.contains(token.index)
        let tokenText = Text(token.text)
            .font(.system(size: 18, weight: .medium))

        return ZStack {
            tokenText
                .foregroundStyle(.clear)
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
                .background {
                    if !isRevealed {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: 0xE8ECEA))
                    }
                }

            if isRevealed {
                tokenText
                    .foregroundStyle(AppSurface.text)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var grammarHintCard: some View {
        FlashcardSurface {
            Group {
                if card.grammarPhrases.isEmpty {
                    Text("No phrase notes for this card.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppSurface.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(card.grammarPhrases) { phrase in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(phrase.text)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppSurface.textSecondary)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(phrase.note)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(AppSurface.muted)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var feedbackBar: some View {
        HStack(spacing: 8) {
            ForEach(Rating.allCases, id: \.rawValue) { rating in
                Button {
                    Task {
                        await submit(rating)
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(rating.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(intervalText(for: rating))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(intervalForeground(for: rating))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
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

    private func intervalForeground(for rating: Rating) -> Color {
        switch rating {
        case .again:
            return Color(hex: 0xBE123C)
        case .hard:
            return AppSurface.amber
        case .good:
            return AppSurface.slateLight
        case .easy:
            return AppSurface.green
        }
    }

    private func resetCardInteraction() {
        side = .front
        revealedTokenIndexes = []
        isSubmitting = false
    }

    private func submit(_ rating: Rating) async {
        guard preview(for: rating) != nil else {
            return
        }
        isSubmitting = true
        await onRate(rating, revealedTokenIndexes.count)
        isSubmitting = false
    }

    private func revealAllTokens() {
        revealedTokenIndexes.formUnion(answerMaskTokens.map(\.index))
    }

    private func deleteCard() async {
        isSubmitting = true
        await onDelete()
        isSubmitting = false
    }

    private func masterCard() async {
        isSubmitting = true
        await onMaster()
        isSubmitting = false
    }
}

private struct FlashcardSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color(hex: 0xFFFCF7))
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color(hex: 0xF1E7D8), lineWidth: 1)
            )
            .shadow(color: AppSurface.shadow.opacity(0.08), radius: 18, x: 0, y: 12)
    }
}

private struct FeedbackButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let rating: Rating

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.46))
            .background(background.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.52))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(stroke.opacity(isEnabled ? 1 : 0.5), lineWidth: 1)
            )
            .shadow(color: isEnabled ? shadow : .clear, radius: 18, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: configuration.isPressed)
    }

    private var foreground: Color {
        rating == .good ? .white : foregroundColor
    }

    private var background: Color {
        switch rating {
        case .again:
            return AppSurface.roseSoft
        case .hard:
            return Color(hex: 0xFFF7ED)
        case .good:
            return AppSurface.dark
        case .easy:
            return Color(hex: 0xECFDF5)
        }
    }

    private var stroke: Color {
        rating == .good ? .clear : AppSurface.line
    }

    private var shadow: Color {
        rating == .good ? AppSurface.dark.opacity(0.14) : AppSurface.shadow.opacity(0.05)
    }

    private var foregroundColor: Color {
        switch rating {
        case .again:
            return Color(hex: 0x9F1239)
        case .hard:
            return Color(hex: 0x92400E)
        case .good:
            return .white
        case .easy:
            return Color(hex: 0x047857)
        }
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
