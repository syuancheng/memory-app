//
//  Components.swift
//  Cardly Design System — Step 2: 组件规范
//
//  所有尺寸/颜色/字体/圆角/间距均引用 Tokens.swift，本文件不含任何字面量。
//  例外：仅结构性的 0 / 1 / 2（如 spacing: 0、lineLimit(1)）与比例值。
//
//  最小点击区域：全部交互组件 ≥ 44×44pt（HIG 及 WCAG 2.5.8 Target Size）。
//  视觉尺寸可小于 44，但必须用 .frame(minWidth:minHeight:) + .contentShape 外扩热区。
//

import SwiftUI
import UIKit

// MARK: - 0. 全局外观（NavBar / TabBar）
//
// 原生导航栏与 Tab bar 由 UIKit appearance 驱动，必须在 App 启动时统一注入，
// 否则每屏各自 .toolbar(.hidden) 再自绘 —— 这正是 #1「三套导航并存」的成因。

enum AppAppearance {

    static func configure() {
        configureNavigationBar()
        configureTabBar()
    }

    private static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppColor.surfaceBase)
        // 滚动前无分割线，滚动后才出现 —— 与 AppElevation.raised 对应
        appearance.shadowColor = .clear

        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(AppColor.textPrimary),
            .font: UIFont.systemFont(ofSize: AppType.headline.size, weight: AppType.headline.uiWeight)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(AppColor.textPrimary),
            .font: UIFont.systemFont(ofSize: AppType.display.size, weight: AppType.display.uiWeight)
        ]

        // 返回按钮：只留箭头，不显示上一页标题（避免 "< Account" 这类超长返回标签）
        let back = UIBarButtonItemAppearance(style: .plain)
        back.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        back.highlighted.titleTextAttributes = [.foregroundColor: UIColor.clear]
        appearance.backButtonAppearance = back

        let scrolled = appearance.copy()
        scrolled.shadowColor = UIColor(AppColor.separator)

        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().tintColor = UIColor(AppColor.primary)
    }

    private static func configureTabBar() {
        let appearance = UITabBarAppearance()
        // ⚠️ 不要用 configureWithOpaqueBackground() + isTranslucent = false。
        //    实测（iPhone 16 Pro / iOS 18.6）：系统会按旧式不透明 Tab bar 预留高度，
        //    但实际绘制的 bar 更矮，差额（约 74pt）露出 UIKit 的 systemBackground ——
        //    浅色下纯白、深色下纯黑，与页面底色 surfaceBase 明显不同。
        //    背景交给系统，我们只接管图标与文字色。
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = UIColor(AppColor.separator)

        let item = appearance.stackedLayoutAppearance
        item.normal.iconColor = UIColor(AppColor.iconMuted)
        item.normal.titleTextAttributes = [
            .foregroundColor: UIColor(AppColor.textTertiary),
            .font: UIFont.systemFont(ofSize: AppType.caption.size, weight: AppType.caption.uiWeight)
        ]
        item.selected.iconColor = UIColor(AppColor.primary)
        item.selected.titleTextAttributes = [
            .foregroundColor: UIColor(AppColor.primary),
            .font: UIFont.systemFont(ofSize: AppType.caption.size, weight: AppType.caption.uiWeight)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - 1. 屏幕容器
//
// 统一负责：背景色（单一实色，不用渐变）+ 水平边距 + 安全区。
// 全 App 的 screenMargin 只有此处一个出口 —— 解决 #9。

struct AppScreen<Content: View>: View {
    var scrollable: Bool = true
    /// 内容是否自带水平边距（卡片需要边距；全宽列表可关掉自行控制）
    var applyMargin: Bool = true
    var topSpacing: CGFloat = AppSpace.lg
    var bottomSpacing: CGFloat = AppSpace.giant
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AppColor.surfaceBase.ignoresSafeArea()

            if scrollable {
                ScrollView {
                    stack
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                stack
            }
        }
        // 不显式撑满时，ZStack 只按最大子视图定尺寸，下方会露出 UIKit 容器的
        // systemBackground（浅色纯白 / 深色纯黑），在 Tab bar 上方形成约 74pt 色带。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: AppSpace.xxl) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, applyMargin ? AppLayout.screenMargin : 0)
        .padding(.top, topSpacing)
        .padding(.bottom, bottomSpacing)
    }
}

// MARK: - 2. 导航 NavBar
//
// ===== 收敛规则（解决 #1）=====
//
// 判据只有一个问题：**这个屏可以返回吗？**
//
// ┌── 样式 A · 标准导航栏 ────────────────────────────────────────────┐
// │ 适用：所有 push / sheet / fullScreenCover 出来的屏。              │
// │ 例如：Subject 编辑页、Username 页、Me 全部二级页、Card 编辑页。   │
// │ 构成：左返回(chevron.left / xmark) + inline 标题 + 右主操作。      │
// │ 实现：**用原生 toolbar**，禁止 .toolbar(.hidden, for:.navigationBar)。│
// │      原生免费提供边缘返回手势、VoiceOver 标签、大字号适配。         │
// │ 高度：44pt（安全区之上）。                                        │
// └──────────────────────────────────────────────────────────────────┘
//
// ┌── 样式 B · 大标题头 ─────────────────────────────────────────────┐
// │ 适用：**仅 Tab 根屏**（Today / Cards / AI / Me），因其不可返回。   │
// │ 构成：display 大标题 +（可选）副标题 + 右侧至多 1 个圆形图标按钮。│
// │ 实现：AppLargeHeader，随内容滚动，不吸顶。                        │
// └──────────────────────────────────────────────────────────────────┘
//
// ❌ 废弃的第三套：「圆形返回按钮 + 大标题」。
//    Subject 编辑页现在就是这套 —— 把 B 用在了可返回的屏上，是三套并存的根源。
//    改为样式 A。

/// 样式 A —— 标准导航栏。挂在被 push / present 的屏上。
struct AppNavBarModifier<Trailing: View>: ViewModifier {
    let title: String
    /// present 出来的屏用 .close（xmark）；push 出来的屏用 .back（系统箭头，不需传）
    var dismissStyle: AppNavDismiss = .back
    var onDismiss: (() -> Void)? = nil
    let trailing: Trailing

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColor.surfaceBase, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .appText(AppType.headline)
                        .lineLimit(1)
                }
                if dismissStyle == .close, let onDismiss {
                    ToolbarItem(placement: .topBarLeading) {
                        // 原生导航栏里用无容器纯图标 —— 带 surface 填充 + 描边的圆形按钮
                        // 与右侧文字按钮视觉重量严重不对称（模拟器实测）。
                        Button(action: onDismiss) {
                            Image(systemName: AppIcon.close)
                                .font(AppIcon.font(AppLayout.iconMD))
                                .foregroundStyle(AppColor.iconDefault)
                                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Close")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    trailing
                }
            }
    }
}

enum AppNavDismiss { case back, close }

extension View {
    func appNavBar<Trailing: View>(
        _ title: String,
        dismiss: AppNavDismiss = .back,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(AppNavBarModifier(title: title, dismissStyle: dismiss, onDismiss: onDismiss, trailing: trailing()))
    }

    func appNavBar(_ title: String, dismiss: AppNavDismiss = .back, onDismiss: (() -> Void)? = nil) -> some View {
        modifier(AppNavBarModifier(title: title, dismissStyle: dismiss, onDismiss: onDismiss, trailing: EmptyView()))
    }
}

/// 样式 B —— Tab 根屏大标题头。
struct AppLargeHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpace.lg) {
            VStack(alignment: .leading, spacing: AppSpace.xs) {
                Text(title)
                    .appText(AppType.display)

                if let subtitle {
                    Text(subtitle)
                        .appText(AppType.body, color: AppColor.textTertiary)
                }
            }

            Spacer(minLength: AppSpace.sm)

            trailing
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
        }
        .padding(.top, AppSpace.sm)
    }
}

extension AppLargeHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - 3. Button
//
// ┌ 变体 ────────┬ 默认 ───────────────┬ 按下 ──────────┬ 禁用 ─────────────┐
// │ primary      │ primary / onPrimary │ primaryPressed │ disabledFill/Text │
// │ secondary    │ surface + 描边       │ surfacePressed │ disabledFill/Text │
// │ ghost        │ 透明 / primary       │ primarySoft    │ 透明 / disabledText│
// │ destructive  │ dangerFill / onDanger│ dangerPressed  │ disabledFill/Text │
// └──────────────┴─────────────────────┴────────────────┴───────────────────┘
//
// ┌ 尺寸 ──┬ 高度 ┬ 圆角 ┬ 字体 ────┬ 水平内边距 ┬ 热区 ┐
// │ large  │ 50   │ md12 │ headline │ xl 20      │ 50   │  全宽主操作
// │ medium │ 44   │ md12 │ headline │ lg 16      │ 44   │  常规
// │ small  │ 32   │ sm 8 │ label    │ md 12      │ 44   │  内联，外扩热区
// └────────┴──────┴──────┴──────────┴────────────┴──────┘
//
// 🔒 铁律（解决 #4 / #5）：
//    1. 灰色填充 = disabled 的**专属签名**。enabled 的主操作永远是 primary 实心。
//    2. 禁用**不用 .opacity()**，只换实色 token。disabledText 于 disabledFill 上 6.92:1。
//    3. loading 时按钮尺寸不变，仅把 label 换成 ProgressView 并阻断交互。

enum AppButtonVariant { case primary, secondary, ghost, destructive }
enum AppButtonSize { case large, medium, small }

private extension AppButtonSize {
    var height: CGFloat {
        switch self {
        case .large:  return AppLayout.buttonHeightLarge
        case .medium: return AppLayout.buttonHeightMedium
        case .small:  return AppLayout.buttonHeightSmall
        }
    }
    var radius: CGFloat {
        switch self {
        case .large, .medium: return AppRadius.md
        case .small:          return AppRadius.sm
        }
    }
    var textStyle: AppTextStyle {
        switch self {
        case .large, .medium: return AppType.headline
        case .small:          return AppType.label
        }
    }
    var paddingH: CGFloat {
        switch self {
        case .large:  return AppSpace.xl
        case .medium: return AppSpace.lg
        case .small:  return AppSpace.md
        }
    }
    var iconSize: CGFloat {
        switch self {
        case .large, .medium: return AppLayout.iconMD
        case .small:          return AppLayout.iconSM
        }
    }
}

struct AppButtonStyle: ButtonStyle {
    let variant: AppButtonVariant
    let size: AppButtonSize
    var fullWidth: Bool
    var isEnabled: Bool
    var isLoading: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled && !isLoading
        let shape = AppRadius.shape(size.radius)

        return ZStack {
            configuration.label
                .opacity(isLoading ? 0 : 1)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(foreground)
            }
        }
        .appText(size.textStyle, color: foreground)
        .lineLimit(1)
        .padding(.horizontal, size.paddingH)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .frame(height: size.height)
        .background(background(pressed: pressed), in: shape)
        .overlay {
            if borderColor != .clear {
                shape.strokeBorder(borderColor, lineWidth: AppLayout.hairline)
            }
        }
        // 视觉高度可为 32，但热区恒 ≥44
        .frame(minHeight: AppLayout.minHitTarget)
        .contentShape(Rectangle())
        .animation(AppMotion.instant, value: pressed)
    }

    private var foreground: Color {
        guard isEnabled else { return AppColor.disabledText }
        switch variant {
        case .primary:     return AppColor.onPrimary
        case .secondary:   return AppColor.textPrimary
        case .ghost:       return AppColor.primary
        case .destructive: return AppColor.onDanger
        }
    }

    private func background(pressed: Bool) -> Color {
        guard isEnabled else {
            return variant == .ghost ? .clear : AppColor.disabledFill
        }
        switch variant {
        case .primary:     return pressed ? AppColor.primaryPressed : AppColor.primary
        case .secondary:   return pressed ? AppColor.surfacePressed : AppColor.surface
        case .ghost:       return pressed ? AppColor.primarySoft : .clear
        case .destructive: return pressed ? AppColor.dangerPressed : AppColor.dangerFill
        }
    }

    private var borderColor: Color {
        guard variant == .secondary else { return .clear }
        return isEnabled ? AppColor.borderStrong : AppColor.disabledBorder
    }
}

struct AppButton: View {
    let title: String
    var icon: String? = nil
    var variant: AppButtonVariant = .primary
    var size: AppButtonSize = .medium
    var fullWidth: Bool = false
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpace.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(AppIcon.font(size.iconSize))
                }
                Text(title)
            }
        }
        .buttonStyle(AppButtonStyle(
            variant: variant, size: size,
            fullWidth: fullWidth, isEnabled: isEnabled, isLoading: isLoading
        ))
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
        // 禁用不改变可聚焦性，但要让 VoiceOver 播报状态
        .accessibilityValue(isLoading ? Text("Loading") : Text(""))
    }
}

/// 圆形图标按钮。视觉 36pt，热区 44pt。
/// 用于：Tab 根屏大标题右侧（Today 的铃铛）、NavBar 关闭键、反相卡上的箭头。
enum AppIconButtonStyle { case plain, filled, tonal, onInverse }

struct AppIconButton: View {
    let icon: String
    var style: AppIconButtonStyle = .plain
    var size: CGFloat = AppLayout.navIconButton
    var badge: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(fill)
                    .overlay {
                        if style == .plain {
                            Circle().strokeBorder(AppColor.border, lineWidth: AppLayout.hairline)
                        }
                    }
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: icon)
                            .font(AppIcon.font(AppLayout.iconMD))
                            .foregroundStyle(foreground)
                    }

                if badge {
                    Circle()
                        .fill(AppColor.dangerFill)
                        .frame(width: AppSpace.sm, height: AppSpace.sm)
                        .overlay(Circle().strokeBorder(AppColor.surfaceBase, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
            .contentShape(Circle())
        }
        .buttonStyle(AppPressableStyle())
        .disabled(!isEnabled)
    }

    private var fill: Color {
        guard isEnabled else { return AppColor.disabledFill }
        switch style {
        case .plain:     return AppColor.surface
        case .filled:    return AppColor.primary
        case .tonal:     return AppColor.primarySoft
        case .onInverse: return AppColor.buttonOnInverse
        }
    }

    private var foreground: Color {
        guard isEnabled else { return AppColor.disabledIcon }
        switch style {
        case .plain:     return AppColor.iconDefault
        case .filled:    return AppColor.onPrimary
        case .tonal:     return AppColor.primaryOnSoft
        case .onInverse: return AppColor.onButtonOnInverse
        }
    }
}

/// 通用可按压反馈（卡片 / 图标按钮 / 整行）
struct AppPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AppMotion.pressScale : 1)
            .animation(AppMotion.instant, value: configuration.isPressed)
    }
}

// MARK: - 4. Card
//
// 尺寸：宽度撑满（受 screenMargin 约束）· 内边距 16 · 圆角 lg 16 · elevation .card
// 变体：
//   .standard  白底 + 1px 描边 —— 默认，95% 场景
//   .sunken    仅当已嵌在白卡内部
//   .inverse   每屏至多一处，承载该屏唯一主推动作
// 可点击卡片：套 AppPressableStyle，按压缩放 0.97

enum AppCardVariant { case standard, sunken, inverse }

struct AppCard<Content: View>: View {
    var variant: AppCardVariant = .standard
    var padding: CGFloat = AppLayout.cardPadding
    var radius: CGFloat = AppRadius.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .appSurface(elevation, fill: fill, radius: radius)
    }

    private var fill: Color {
        switch variant {
        case .standard: return AppColor.surface
        case .sunken:   return AppColor.surfaceSunken
        case .inverse:  return AppColor.surfaceInverse
        }
    }

    private var elevation: AppElevation {
        switch variant {
        case .standard: return .card
        case .sunken:   return .flat
        case .inverse:  return .flat
        }
    }
}

// MARK: - 5. ListRow
//
// 尺寸：最小高度 52（热区 ≥44 自动满足）· 水平内边距 16 · 垂直内边距 12
// 结构：[图标容器 32×32, radius 8] — 8 — [标题 headline / 副标题 body] — Spacer — [尾部]
// 分隔线：hairline，左缩进 56（有图标）或 16（无图标），最后一行不画
// 状态：默认 / 按下 surfacePressed / 禁用 disabledText
//
// ⚠️ 现状修正：Me 页行标题现在是 iconAccent(#3F6D84) 深青灰 —— 那是把中性文字染了色。
//    改为 textPrimary。行首图标容器由 iconSoft 改为 iconContainerBase（中性）。

enum AppListRowAccessory: Equatable {
    case none
    case disclosure
    case value(String)
    case valueWithDisclosure(String)
}

struct AppListRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    /// 仅 Subject 身份色场景传入；chrome 场景保持 nil（中性）
    var iconTint: AppColor.SubjectAccent? = nil
    var accessory: AppListRowAccessory = .disclosure
    var isDestructive: Bool = false
    var isEnabled: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        if let action, isEnabled {
            Button(action: action) { rowContent }
                .buttonStyle(AppListRowButtonStyle())
                .accessibilityAddTraits(.isButton)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: AppSpace.sm) {
            if let icon {
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(iconTint?.soft ?? AppColor.iconContainerBase)
                    .frame(width: AppLayout.iconContainer, height: AppLayout.iconContainer)
                    .overlay {
                        Image(systemName: icon)
                            .font(AppIcon.font(AppLayout.iconSM))
                            .foregroundStyle(iconForeground)
                    }
            }

            VStack(alignment: .leading, spacing: AppSpace.xs / 2) {
                Text(title)
                    .appText(AppType.headline, color: titleColor)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .appText(AppType.body, color: AppColor.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: AppSpace.sm)

            accessoryView
        }
        .padding(.horizontal, AppLayout.rowPaddingH)
        .padding(.vertical, AppLayout.rowPaddingV)
        .frame(minHeight: AppLayout.rowMinHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .disclosure:
            chevron
        case .value(let text):
            Text(text)
                .appText(AppType.body, color: AppColor.textTertiary)
                .lineLimit(1)
        case .valueWithDisclosure(let text):
            HStack(spacing: AppSpace.xs) {
                Text(text)
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .lineLimit(1)
                chevron
            }
        }
    }

    private var chevron: some View {
        Image(systemName: AppIcon.disclose)
            .font(AppIcon.font(AppLayout.iconSM))
            .foregroundStyle(AppColor.neutral400)
    }

    private var titleColor: Color {
        if !isEnabled { return AppColor.disabledText }
        return isDestructive ? AppColor.dangerText : AppColor.textPrimary
    }

    private var iconForeground: Color {
        if !isEnabled { return AppColor.disabledIcon }
        if isDestructive { return AppColor.dangerText }
        return iconTint?.text ?? AppColor.iconDefault
    }
}

private struct AppListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AppColor.surfacePressed : Color.clear)
            .animation(AppMotion.instant, value: configuration.isPressed)
    }
}

/// 行之间的分隔线。有图标的行用 separatorInsetIcon(56)，无图标用 separatorInsetPlain(16)。
struct AppRowSeparator: View {
    var inset: CGFloat = AppLayout.separatorInsetIcon

    var body: some View {
        Rectangle()
            .fill(AppColor.separator)
            .frame(height: AppLayout.separatorHeight)
            .padding(.leading, inset)
    }
}

/// 分组列表容器：白底 + 描边 + 裁切，行与分隔线由调用方按序放入。
struct AppGroupedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .appSurface(.card, fill: AppColor.surface, radius: AppRadius.lg)
    }
}

// MARK: - 6. TextField
//
// 尺寸：单行高 48 · 多行最小高 96 · 圆角 md 12 · 内边距 H16 / V12
// 结构：[label 13] — 8 — [输入框] — 4 — [helper / error 13]
// 状态：
//   default  fill sunken · border borderStrong 1px
//   focused  fill surface · border focusRing 2px
//   error    border dangerFill 1px · helper 用 dangerText
//   disabled fill disabledFill · text disabledText · 不可聚焦
// placeholder 用 textPlaceholder（neutral500，5.35:1），**不用 neutral400**（2.44:1 不达标）

struct AppTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var helper: String? = nil
    var errorText: String? = nil
    var isEnabled: Bool = true
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpace.sm) {
            Text(label)
                .appText(AppType.label, color: AppColor.textTertiary)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .appText(AppType.body, color: AppColor.textPlaceholder)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .appText(AppType.body, color: isEnabled ? AppColor.textPrimary : AppColor.disabledText)
                    .focused($isFocused)
                    .submitLabel(submitLabel)
                    .onSubmit { onSubmit?() }
                    .disabled(!isEnabled)
            }
            .padding(.horizontal, AppSpace.lg)
            .frame(height: AppLayout.fieldHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fieldFill, in: AppRadius.shape(AppRadius.md))
            .overlay {
                AppRadius.shape(AppRadius.md)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .contentShape(Rectangle())
            .onTapGesture { if isEnabled { isFocused = true } }
            .animation(AppMotion.instant, value: isFocused)

            if let message = errorText ?? helper {
                Text(message)
                    .appText(AppType.label, color: errorText != nil ? AppColor.dangerText : AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fieldFill: Color {
        if !isEnabled { return AppColor.disabledFill }
        return isFocused ? AppColor.surface : AppColor.surfaceSunken
    }
    private var borderColor: Color {
        if !isEnabled { return AppColor.disabledBorder }
        if errorText != nil { return AppColor.dangerFill }
        return isFocused ? AppColor.focusRing : AppColor.borderStrong
    }
    private var borderWidth: CGFloat {
        isFocused ? AppLayout.focusRingWidth : AppLayout.hairline
    }
}

/// 多行输入（卡片正反面、Subject 描述）
struct AppTextArea: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var helper: String? = nil
    var minHeight: CGFloat = 96
    var isEnabled: Bool = true

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpace.sm) {
            Text(label)
                .appText(AppType.label, color: AppColor.textTertiary)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .appText(AppType.body, color: AppColor.textPlaceholder)
                        .padding(.horizontal, AppSpace.lg)
                        .padding(.vertical, AppSpace.md + AppSpace.xs)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .appText(AppType.body, color: isEnabled ? AppColor.textPrimary : AppColor.disabledText)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .disabled(!isEnabled)
                    .padding(.horizontal, AppSpace.md)
                    .padding(.vertical, AppSpace.md)
            }
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(isEnabled ? (isFocused ? AppColor.surface : AppColor.surfaceSunken) : AppColor.disabledFill,
                        in: AppRadius.shape(AppRadius.md))
            .overlay {
                AppRadius.shape(AppRadius.md)
                    .strokeBorder(
                        isEnabled ? (isFocused ? AppColor.focusRing : AppColor.borderStrong) : AppColor.disabledBorder,
                        lineWidth: isFocused ? AppLayout.focusRingWidth : AppLayout.hairline
                    )
            }
            .animation(AppMotion.instant, value: isFocused)

            if let helper {
                Text(helper)
                    .appText(AppType.label, color: AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 7. SectionHeader
//
// 字体 label(13 Medium) · 色 textTertiary · 下间距 8 · 与上一区块间距 32
// **不做大写转换** —— 中文内容无大写概念，混排时大写只作用于拉丁部分，层级会碎。
// 可选尾部动作：label 13 Medium primary，热区 ≥44。
//
// ⚠️ 现状修正：Me 页的 Achievements / Profile / Settings 现在是 22pt Bold，
//    与卡片内容标题同级，压不住层级。降为 label。

struct AppSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: AppSpace.sm) {
            Text(title)
                .appText(AppType.label, color: AppColor.textTertiary)

            Spacer(minLength: AppSpace.sm)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .appText(AppType.label, color: AppColor.primary)
                        .padding(.horizontal, AppSpace.sm)
                        .frame(minHeight: AppLayout.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // 尾部动作靠右对齐到内容边缘，抵消上面的热区内边距
                .padding(.trailing, -AppSpace.sm)
            }
        }
        .padding(.bottom, AppSpace.sm)
    }
}

// MARK: - 8. EmptyState
//
// 两种密度：
//   .standard —— 整屏为空。图标 32 + 标题 headline + 说明 body + 可选主按钮。
//                上下留白 huge(40)，说明文字最大宽 280 居中。
//   .compact  —— 嵌在已有卡片内（如 Achievements 热力图无数据）。
//                无图标，仅标题 + 一行说明，上下留白 xxl(24)。
//
// 解决 #7：热力图空数据时**网格照常绘制**（全部 heatLevel0），
//          再在其上叠 .compact 空状态说明。绝不整块留白。

enum AppEmptyStateDensity { case standard, compact }

struct AppEmptyState: View {
    var icon: String? = nil
    let title: String
    var message: String? = nil
    var density: AppEmptyStateDensity = .standard
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: density == .standard ? AppSpace.md : AppSpace.xs) {
            if density == .standard, let icon {
                // 裸图标浮在页面上像「忘了放东西」；套一个中性圆底后
                // 读起来才是「这里本来就是空的」。
                Circle()
                    .fill(AppColor.iconContainerBase)
                    .frame(width: AppLayout.avatarLG, height: AppLayout.avatarLG)
                    .overlay {
                        Image(systemName: icon)
                            .font(AppIcon.font(AppLayout.iconLG))
                            .foregroundStyle(AppColor.iconMuted)
                    }
                    .padding(.bottom, AppSpace.xs)
            }

            Text(title)
                .appText(density == .standard ? AppType.headline : AppType.label,
                         color: density == .standard ? AppColor.textPrimary : AppColor.textSecondary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .appText(density == .standard ? AppType.body : AppType.label,
                             color: AppColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: density == .standard ? 280 : .infinity)
            }

            if density == .standard, let actionTitle, let action {
                AppButton(title: actionTitle, variant: .secondary, size: .medium, action: action)
                    .padding(.top, AppSpace.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, density == .standard ? AppSpace.huge : AppSpace.xxl)
        .padding(.horizontal, AppSpace.lg)
        .accessibilityElement(children: .combine)
    }
}



/// 内容类型徽标。恒定的中性容器 + 类型图形，回答「这是什么」。
/// 与 subject 身份色（每个 subject 不同，回答「这是哪一个」）分工明确 ——
/// 类型不该用颜色区分，否则会和身份色抢同一个视觉通道。
struct AppTypeBadge: View {
    let icon: String
    var size: CGFloat = AppLayout.avatarMD

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .fill(AppColor.iconContainerBase)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: icon)
                    .font(AppIcon.font(AppLayout.iconMD))
                    .foregroundStyle(AppColor.iconDefault)
            }
    }
}
