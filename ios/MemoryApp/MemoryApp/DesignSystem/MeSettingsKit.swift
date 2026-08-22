import SwiftUI
import UIKit

// MARK: - Me tab 专用视觉层
//
// 这套 token 与组件**只服务 Me tab**，是对 Tokens.swift 三条全局决策的「有意局部例外」，
// 依据是设计参考稿 CardlyMePageV2（渐变底 + 无描边软阴影卡片 + 彩色图标容器）：
//
//   1. Tokens.swift:429-431 定的是「以描边为主、阴影为辅」；这里反过来，浅色下用软阴影、去描边。
//   2. Tokens.swift:96 定的是「页面背景不用渐变」；这里 Me tab 用冷→暖竖向渐变。
//   3. Tokens.swift:198-205 禁止 SubjectAccent 用于 chrome；这里不挪用它，另建 MeRowTint。
//
// 边界：Cards / Home / Review 继续走 AppScreen + AppGroupedList + AppElevation.card，
// 全局 token 一个字节都没改。要撤销本次改版，只需把 Me 各页换回 MePageScaffold 系列。

/// Tokens.swift 里的 dsColor 是 private，跨文件不可见，这里补一个等价实现。
private func meColor(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(meRGB: dark) : UIColor(meRGB: light)
    })
}

private extension UIColor {
    convenience init(meRGB rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Token

enum MeTheme {

    // 背景：参考稿的冷 → 暖奶油竖向渐变。深色下压成近黑的同向渐变，保留层次但不发灰。
    static let bgTop = meColor(light: 0xE4EBF1, dark: 0x0B0D12)
    static let bgMid = meColor(light: 0xEAEAEE, dark: 0x10131A)
    static let bgBottom = meColor(light: 0xF2ECE4, dark: 0x14171F)

    static var background: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: bgTop, location: 0),
                .init(color: bgMid, location: 0.42),
                .init(color: bgBottom, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // 卡片
    static let cardRadius: CGFloat = 22
    static let cardGap: CGFloat = 14
    static let cardPadding: CGFloat = 16

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    }

    /// 参考稿 `0 4px 20px rgba(80,80,120,.06)`。CSS blur ≈ SwiftUI radius × 2，故 radius 取 10。
    static let shadowColor = Color(red: 80 / 255, green: 80 / 255, blue: 120 / 255).opacity(0.06)
    static let shadowRadius: CGFloat = 10
    static let shadowY: CGFloat = 4
    /// 深色下阴影不成立（黑底看不见），降级为极浅描边。
    static let darkCardBorder = meColor(light: 0x000000, dark: 0x232834)

    // 行
    static let rowPaddingH: CGFloat = 16
    static let rowPaddingV: CGFloat = 16
    static let rowMinHeight: CGFloat = 56
    /// 图标与文字之间
    static let rowGap: CGFloat = 14

    static let divider = meColor(light: 0xF2F2F6, dark: 0x20242E)
    static let rowPressed = meColor(light: 0xF8F8FB, dark: 0x1B1F29)

    // 图标容器
    static let iconContainer: CGFloat = 40
    static let iconContainerRadius: CGFloat = 13
    static let iconSize: CGFloat = 20

    // 文字
    /// 参考稿行标签为 16pt semibold（比全局 headline 的 17 小一号，行更密集时更稳）。
    static let rowLabel = AppTextStyle(
        size: 16, weight: .semibold, uiWeight: .semibold,
        lineHeight: 21, tracking: -0.31, metric: .headline
    )
    /// 右侧数值 / 副标题沿用全局 body，颜色走 AppColor.textTertiary。
    /// 参考稿用的 #9A9DAB 在白底上仅约 2.9:1，达不到 WCAG AA 正文要求，故不采用。
    static let rowValue = AppType.body

    /// chevron 属装饰件（行本身有可访问名称），可以比正文浅。
    static let chevron = meColor(light: 0xC6C8D2, dark: 0x4A5060)
}

/// 设置行图标容器的柔和着色。**不复用 AppColor.SubjectAccent** —— 那是 Subject 身份色，
/// Tokens.swift:198-205 明文禁止用于 chrome，挪用会污染其语义。
struct MeRowTint {
    let foreground: Color
    let background: Color

    static let violet = MeRowTint(
        foreground: meColor(light: 0x7C6CF6, dark: 0xA79BFF),
        background: meColor(light: 0xEEEBFB, dark: 0x262046)
    )
    static let teal = MeRowTint(
        foreground: meColor(light: 0x3DBD9E, dark: 0x5FD9BC),
        background: meColor(light: 0xE1F4EE, dark: 0x0F3830)
    )
    static let blue = MeRowTint(
        foreground: meColor(light: 0x4E7FF0, dark: 0x7BA5FF),
        background: meColor(light: 0xE6EEFC, dark: 0x14264A)
    )
    static let amber = MeRowTint(
        foreground: meColor(light: 0xD08707, dark: 0xFBBF24),
        background: meColor(light: 0xFEF2DE, dark: 0x3A2A08)
    )
    static let rose = MeRowTint(
        foreground: meColor(light: 0xE0607C, dark: 0xFF9BAC),
        background: meColor(light: 0xFDE9ED, dark: 0x431A24)
    )
    static let neutral = MeRowTint(
        foreground: meColor(light: 0x646B7A, dark: 0x9BA3B2),
        background: meColor(light: 0xF0F1F4, dark: 0x1B1F29)
    )
}

// MARK: - 容器

/// Me tab 的屏幕底座：渐变背景 + 滚动 + 统一边距。等价于全局的 AppScreen，
/// 但 AppScreen 硬编码了 surfaceBase 纯色背景，无法参数化，故另立一个。
struct MeScreen<Content: View>: View {
    var topSpacing: CGFloat = AppSpace.lg
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            MeTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: MeTheme.cardGap) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppLayout.screenMargin)
                .padding(.top, topSpacing)
                .padding(.bottom, AppSpace.giant)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 可返回的 Me 子页：MeScreen + 原生 inline 导航栏。
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        MeScreen {
            content
        }
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

/// 新卡片外壳：白面 + 22pt 连续圆角 + 软阴影，浅色下无描边。
/// 行自带内边距，故默认 padding 为 0；自由内容（图表、说明段落）传 `padding:`。
struct MeCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(AppColor.surface, in: MeTheme.cardShape)
        // 必须裁切：首行 / 末行的按压高亮是矩形，不裁会溢出圆角把卡片四角削成直角。
        .clipShape(MeTheme.cardShape)
        .overlay {
            // 深色下阴影不可见，用极浅描边维持卡片边界。
            if colorScheme == .dark {
                MeTheme.cardShape.strokeBorder(MeTheme.darkCardBorder, lineWidth: 1)
            }
        }
        .compositingGroup()
        .shadow(
            color: colorScheme == .dark ? .clear : MeTheme.shadowColor,
            radius: MeTheme.shadowRadius,
            x: 0,
            y: MeTheme.shadowY
        )
    }
}

/// 一个分组 = 一张卡。参考稿没有分组小标题，故 header 默认 nil；
/// 需要语义提示时再传，footer 用于状态提示 / 补充说明。
struct SettingsSection<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpace.sm) {
            if let header {
                Text(LocalizedStringKey(header))
                    .appText(AppType.label, color: AppColor.textTertiary)
                    .padding(.horizontal, AppSpace.xs)
            }

            MeCard(padding: padding) {
                content
            }

            if let footer {
                Text(LocalizedStringKey(footer))
                    .appText(AppType.label, color: AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpace.xs)
            }
        }
    }
}

/// 卡片内的行间发丝线。参考稿是通栏（不缩进），跟着卡片左右边缘走。
struct MeRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(MeTheme.divider)
            .frame(height: 1)
    }
}

// MARK: - 行

/// 所有设置行的共同底座：统一 16/16 内边距、56 最小高、可选 40pt 着色图标容器。
struct MeSettingsRow<Content: View>: View {
    var icon: String? = nil
    var tint: MeRowTint = .neutral
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: MeTheme.rowGap) {
            if let icon {
                RoundedRectangle(cornerRadius: MeTheme.iconContainerRadius, style: .continuous)
                    .fill(tint.background)
                    .frame(width: MeTheme.iconContainer, height: MeTheme.iconContainer)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: MeTheme.iconSize, weight: .medium))
                            .foregroundStyle(tint.foreground)
                    }
            }

            content
        }
        .padding(.horizontal, MeTheme.rowPaddingH)
        .padding(.vertical, MeTheme.rowPaddingV)
        .frame(minHeight: MeTheme.rowMinHeight)
        .contentShape(Rectangle())
    }
}

/// 行的按压反馈，对应参考稿的 `active:bg-[#F8F8FB]`。
struct MeRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? MeTheme.rowPressed : Color.clear)
            .animation(AppMotion.instant, value: configuration.isPressed)
    }
}

private struct MeChevron: View {
    var body: some View {
        Image(systemName: AppIcon.disclose)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MeTheme.chevron)
    }
}

/// 跳转行：标签 +（可选）右侧值 + chevron。
struct NavigationRow<Destination: Hashable>: View {
    let title: String
    var value: String? = nil
    var icon: String? = nil
    var tint: MeRowTint = .neutral
    let destination: Destination

    var body: some View {
        NavigationLink(value: destination) {
            MeSettingsRow(icon: icon, tint: tint) {
                Text(LocalizedStringKey(title))
                    .appText(MeTheme.rowLabel)

                Spacer(minLength: AppSpace.sm)

                if let value {
                    Text(LocalizedStringKey(value))
                        .appText(MeTheme.rowValue, color: AppColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                MeChevron()
            }
        }
        .buttonStyle(MeRowButtonStyle())
    }
}

/// 点击触发动作的行（非导航），可选 chevron。
struct ActionRow: View {
    let title: String
    var value: String? = nil
    var icon: String? = nil
    var tint: MeRowTint = .neutral
    var showsChevron: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MeSettingsRow(icon: icon, tint: tint) {
                Text(LocalizedStringKey(title))
                    .appText(MeTheme.rowLabel, color: isDestructive ? AppColor.dangerText : AppColor.textPrimary)

                Spacer(minLength: AppSpace.sm)

                if let value {
                    Text(LocalizedStringKey(value))
                        .appText(MeTheme.rowValue, color: AppColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if showsChevron {
                    MeChevron()
                }
            }
        }
        .buttonStyle(MeRowButtonStyle())
    }
}

/// 只读的「标签 + 右侧值」行。
struct ValueRow: View {
    let title: String
    let value: String
    var icon: String? = nil
    var tint: MeRowTint = .neutral

    var body: some View {
        MeSettingsRow(icon: icon, tint: tint) {
            Text(LocalizedStringKey(title))
                .appText(MeTheme.rowLabel)

            Spacer(minLength: AppSpace.sm)

            Text(LocalizedStringKey(value))
                .appText(MeTheme.rowValue, color: AppColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// 开关行。label 放在 Toggle 内部，保证整行可点且 VoiceOver 能读到名称。
struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var icon: String? = nil
    var tint: MeRowTint = .neutral

    var body: some View {
        MeSettingsRow(icon: icon, tint: tint) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: AppSpace.xs / 2) {
                    Text(LocalizedStringKey(title))
                        .appText(MeTheme.rowLabel)

                    if let subtitle {
                        Text(LocalizedStringKey(subtitle))
                            .appText(AppType.body, color: AppColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(AppColor.primary)
        }
    }
}

/// 数字输入行：直接键入，不用 +/− 步进器。
/// 用 String 中转而非 `TextField(value:format:)`，这样用户清空 / 打半截时不会被解析器打断，
/// 只在失焦时统一按 range 夹取并回写。
struct NumberFieldRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var icon: String? = nil
    var tint: MeRowTint = .neutral

    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        MeSettingsRow(icon: icon, tint: tint) {
            Text(LocalizedStringKey(title))
                .appText(MeTheme.rowLabel)

            Spacer(minLength: AppSpace.sm)

            TextField("", text: $text)
                .appText(MeTheme.rowValue, color: AppColor.textPrimary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(maxWidth: 72)
                .padding(.horizontal, AppSpace.sm)
                .padding(.vertical, AppSpace.xs)
                .background(MeTheme.rowPressed, in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                .accessibilityLabel(LocalizedStringKey(title))
                // numberPad 没有回车键，必须给一个显式的收起入口。
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isFocused = false }
                    }
                }
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, newValue in
            // 外部（如网络加载完成）改了值时同步显示，但不打断正在输入的用户。
            if !isFocused { text = "\(newValue)" }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        let parsed = Int(digits) ?? value
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        value = clamped
        text = "\(clamped)"
    }
}

/// 分段选择行。分段控件本身横向铺满，故不套行基座，只对齐左右内边距。
struct PickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    @ViewBuilder var content: Content

    var body: some View {
        Picker(title, selection: $selection) {
            content
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, MeTheme.rowPaddingH)
        .padding(.vertical, MeTheme.rowPaddingV)
    }
}

/// 带标题的分段选择块（Appearance 页那种「标签在上、分段在下」的形态）。
struct LabeledPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpace.md) {
            Text(LocalizedStringKey(title))
                .appText(MeTheme.rowLabel)

            Picker(title, selection: $selection) {
                content
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, MeTheme.rowPaddingH)
        .padding(.vertical, MeTheme.rowPaddingV)
    }
}
