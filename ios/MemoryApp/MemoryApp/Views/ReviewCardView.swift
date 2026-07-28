import SwiftUI

enum CardSide {
    case front
    case back
}

struct ReviewCardView: View {
    let card: ReviewCard
    let progressText: String
    let resetToken: Int
    let onClose: () -> Void
    let onDelete: () async -> Void
    let onMaster: () async -> Void
    let onRate: (Rating, Int) async -> Void

    @State private var side: CardSide = .front
    @State private var revealedTokenIndexes: Set<Int> = []
    @State private var isSubmitting = false

    private var allTokensRevealed: Bool {
        card.answerTokens.allSatisfy { revealedTokenIndexes.contains($0.index) }
    }

    private var answerFontSize: CGFloat {
        let tokenCount = card.answerTokens.count
        let characterCount = card.answerTokens.reduce(0) { $0 + $1.text.count }

        if tokenCount >= 28 || characterCount >= 150 {
            return 17
        }
        if tokenCount >= 22 || characterCount >= 120 {
            return 18
        }
        if tokenCount >= 16 || characterCount >= 88 {
            return 19.5
        }
        return 21
    }

    private var tokenSpacing: CGFloat {
        card.answerTokens.count >= 20 ? 5 : 6
    }

    private var tokenLineSpacing: CGFloat {
        card.answerTokens.count >= 20 ? 10 : 13
    }

    private var tokenVerticalPadding: CGFloat {
        1
    }

    private var answerTextFontSize: CGFloat {
        max(13.5, answerFontSize - 5)
    }

    var body: some View {
        VStack(spacing: 0) {
            if side == .front {
                pageHeader
                    .frame(height: 64)
            } else {
                ZStack {
                    Color.clear.frame(height: 8)
                    progressPill
                        .padding(.top, 8)
                    HStack {
                        Spacer()
                        moreButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
                .frame(height: 44)
            }

            if side == .front {
                frontCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                backCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if side == .back {
                Spacer(minLength: 14)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        side = .front
                    }

                HStack(spacing: 9) {
                    ForEach(Rating.allCases, id: \.rawValue) { rating in
                        Button(rating.title) {
                            Task {
                                await submit(rating)
                            }
                        }
                        .disabled(isSubmitting)
                        .buttonStyle(RatingButtonStyle(rating: rating))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: side)
        .onChange(of: card.id) { _, _ in
            resetCardInteraction()
        }
        .onChange(of: resetToken) { _, _ in
            resetCardInteraction()
        }
    }

    private func resetCardInteraction() {
        side = .front
        revealedTokenIndexes = []
        isSubmitting = false
    }

    private var pageHeader: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.green)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.50))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 4) {
                progressPill

                Text(contextText)
                    .font(AppFont.medium(11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer()

            moreButton
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private var progressPill: some View {
        Text(progressText)
            .font(AppFont.medium(12))
            .foregroundStyle(Theme.green)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.greenSoft.opacity(0.92))
            .clipShape(Capsule())
    }

    private var moreButton: some View {
        Menu {
            Button {
                Task {
                    await masterCard()
                }
            } label: {
                Label("标记熟悉", systemImage: "checkmark.seal")
            }
            .disabled(isSubmitting)

            Button(role: .destructive) {
                Task {
                    await deleteCard()
                }
            } label: {
                Label("删除当前卡", systemImage: "trash")
            }
            .disabled(isSubmitting)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Theme.green)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.66))
                .clipShape(Circle())
                .shadow(color: Theme.text.opacity(0.09), radius: 26, y: 10)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var contextText: String {
        let tag = card.tags.first?.name ?? "Review"
        return "\(card.subjectName ?? "English") · \(tag) · Review"
    }

    private var frontCard: some View {
        Button {
            side = .back
        } label: {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Text(card.cardType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(AppFont.medium(12))
                        .foregroundStyle(Theme.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.greenSoft)
                        .clipShape(Capsule())
                        .position(x: 24 + 72, y: 24 + 16)

                    Text(card.frontText)
                        .font(AppFont.medium(28))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: max(0, proxy.size.width - 48), alignment: .leading)
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height * 0.382
                        )

                    Text("Tap card to flip")
                        .font(AppFont.regular(13))
                        .foregroundStyle(Theme.muted)
                        .position(x: 24 + 52, y: proxy.size.height - 32)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 494, maxHeight: 542, alignment: .leading)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [Theme.panel.opacity(0.97), Color(hex: 0xFCF4E8).opacity(0.93)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    RadialGradient(
                        colors: [.white.opacity(0.82), .clear],
                        center: UnitPoint(x: 0.82, y: 0.15),
                        startRadius: 0,
                        endRadius: 190
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Theme.green.opacity(0.105), lineWidth: 1)
            )
            .shadow(color: Theme.text.opacity(0.12), radius: 44, y: 18)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 80)
        }
        .buttonStyle(.plain)
    }

    private var backCard: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    side = .front
                }

            VStack(spacing: 12) {
                tokenPanel
                phrasePanel
                    .contentShape(Rectangle())
                    .onTapGesture {
                        side = .front
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var tokenPanel: some View {
        FlowLayout(spacing: tokenSpacing, lineSpacing: tokenLineSpacing) {
            ForEach(card.answerTokens) { token in
                Button {
                    revealedTokenIndexes.insert(token.index)
                } label: {
                    tokenChip(token)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, card.answerTokens.count >= 22 ? 18 : 22)
        .padding(.top, card.answerTokens.count >= 22 ? 20 : 24)
        .padding(.bottom, card.answerTokens.count >= 22 ? 48 : 52)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .center)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.green.opacity(0.105), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            Button {
                revealAllTokens()
            } label: {
                Image(systemName: allTokensRevealed ? "eye.fill" : "eye")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Color(hex: 0x69706F).opacity(allTokensRevealed ? 0.58 : 1))
                    .frame(width: 44, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(allTokensRevealed)
            .padding(.trailing, 20)
            .padding(.bottom, 18)
            .accessibilityLabel("Show full answer")
        }
        .shadow(color: Theme.text.opacity(0.10), radius: 34, y: 14)
    }

    private func tokenChip(_ token: AnswerToken) -> some View {
        let isRevealed = revealedTokenIndexes.contains(token.index)
        let tokenText = Text(token.text)
            .font(AppFont.regular(answerTextFontSize))

        return ZStack {
            tokenText
                .foregroundStyle(.clear)
                .padding(.vertical, tokenVerticalPadding)
                .background(hiddenTokenBackground(isRevealed: isRevealed))
                .overlay(hiddenTokenSheen(isRevealed: isRevealed))

            if isRevealed {
                tokenText
                    .foregroundStyle(Theme.text)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func hiddenTokenBackground(isRevealed: Bool) -> some View {
        if !isRevealed {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xE8ECEA), Color(hex: 0xDDE3E1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    @ViewBuilder
    private func hiddenTokenSheen(isRevealed: Bool) -> some View {
        if !isRevealed {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var phrasePanel: some View {
        Group {
            if card.grammarPhrases.count > 3 {
                ScrollView(showsIndicators: false) {
                    phraseContent
                }
                .frame(maxHeight: 330)
            } else {
                phraseContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.green.opacity(0.105), lineWidth: 1)
        )
        .shadow(color: Theme.text.opacity(0.10), radius: 34, y: 14)
    }

    private var phraseContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(card.grammarPhrases) { phrase in
                VStack(alignment: .leading, spacing: 6) {
                    Text(phrase.text)
                        .font(AppFont.regular(answerTextFontSize))
                        .lineSpacing(2)
                        .foregroundStyle(Color(hex: 0x1F2F28).opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(phrase.note)
                        .font(AppFont.regular(answerTextFontSize))
                        .lineSpacing(2)
                        .foregroundStyle(Color(hex: 0x1F2F28).opacity(0.66))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var panelBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.panel.opacity(0.98), Color(hex: 0xFCF4E8).opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [.white.opacity(0.82), .clear],
                center: UnitPoint(x: 0.88, y: 0.08),
                startRadius: 0,
                endRadius: 160
            )
        }
    }

    private func submit(_ rating: Rating) async {
        isSubmitting = true
        await onRate(rating, revealedTokenIndexes.count)
        isSubmitting = false
    }

    private func revealAllTokens() {
        revealedTokenIndexes.formUnion(card.answerTokens.map(\.index))
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

struct RatingButtonStyle: ButtonStyle {
    let rating: Rating

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.medium(16))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(background.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .shadow(color: shadow, radius: 18, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }

    private var foreground: Color {
        rating == .remembered ? .white : Theme.text
    }

    private var background: Color {
        switch rating {
        case .forgot:
            return Color(red: 0.98, green: 0.91, blue: 0.88)
        case .fuzzy:
            return Theme.paper
        case .remembered:
            return Theme.green
        }
    }

    private var stroke: Color {
        rating == .remembered ? .clear : Theme.green.opacity(0.12)
    }

    private var shadow: Color {
        rating == .remembered ? Theme.green.opacity(0.18) : Theme.text.opacity(0.05)
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
