//
//  Tokens.swift
//  Cardly Design System — Step 1: Design Tokens
//
//  唯一真实来源 (single source of truth)。
//  规则：视图层禁止出现字面量颜色、字号、间距、圆角、阴影。
//        所有值必须来自本文件的 AppColor / AppType / AppSpace / AppRadius /
//        AppElevation / AppLayout / AppMotion / AppIcon。
//
//  本文件只新增、不修改既有类型，可安全并入现有工程。
//  旧的 AppSurface (HomeView.swift:863) 与 Theme (Theme.swift) 在第三步逐屏替换后删除。
//

import SwiftUI
import UIKit

// MARK: - 基础设施

/// 支持浅色 / 深色双值的颜色构造。深色模式已全量预留，无需二次改造。
private func dsColor(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
    })
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - 1. 色彩 Color

enum AppColor {

    // MARK: 1.1 品牌主色（单一主色，唯一）
    //
    // 决策：保留靛紫 #4F46E5，删除 #3F6D84（深青灰）与 #7C3AED（紫）。
    // 主色只用于三处：主按钮填充 / 选中态 / 需要引导视线的单一强调元素。
    // 主色不用于：普通图标、列表项装饰、分隔线、正文。

    /// 主色。白字于其上 6.29:1 (AA ✓)；作为文字于白底 6.29:1 (AA ✓)
    static let primary        = dsColor(light: 0x4F46E5, dark: 0x6366F1)
    /// 主色按下态（比 primary 深两档，非透明度变化）。白字于其上 7.90:1 ✓
    static let primaryPressed = dsColor(light: 0x4338CA, dark: 0x4F46E5)
    /// 主色上的前景（按钮文字/图标）
    static let onPrimary      = dsColor(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// 主色浅底（tinted 卡片、选中行背景、Badge 底）
    static let primarySoft    = dsColor(light: 0xEEF2FF, dark: 0x1E1B4B)
    /// 浅底上的主色文字/图标。于 primarySoft 上 5.62:1 (AA ✓)
    static let primaryOnSoft  = dsColor(light: 0x4338CA, dark: 0xA5B4FC)
    /// 键盘焦点 / 输入框激活描边
    static let focusRing      = dsColor(light: 0x4F46E5, dark: 0x818CF8)

    // MARK: 1.2 中性色阶 9 档
    //
    // 命名按明度递增编号，与用途解耦。深色模式为镜像映射（非简单反色）。

    /// 页面底色 · 最浅
    static let neutral50  = dsColor(light: 0xFBFBFC, dark: 0x0B0D12)
    /// 次级/下沉表面（嵌套在白卡内的次级块）
    static let neutral100 = dsColor(light: 0xF4F5F7, dark: 0x1B1F29)
    /// 分隔线 / 卡片描边
    static let neutral200 = dsColor(light: 0xE7E8EC, dark: 0x262B36)
    /// 输入框描边 / 强分隔
    static let neutral300 = dsColor(light: 0xD5D7DE, dark: 0x333A48)
    /// 装饰性图标、禁用态图标。⚠️ 对比度 2.44:1，禁止用于任何文字
    static let neutral400 = dsColor(light: 0xA1A6B2, dark: 0x646B7A)
    /// 次级文字 / placeholder。白底 5.35:1 ✓，neutral100 底 4.90:1 ✓
    static let neutral500 = dsColor(light: 0x646B7A, dark: 0x9BA3B2)
    /// 三级文字、禁用按钮文字。neutral100 底 6.92:1 ✓
    static let neutral600 = dsColor(light: 0x4B5563, dark: 0xB6BDC9)
    /// 正文强调 / ListRow 副标题。白底 10.3:1 ✓
    static let neutral700 = dsColor(light: 0x374151, dark: 0xD4D8E0)
    /// 主文字 · 最深。白底 17.7:1 ✓
    static let neutral900 = dsColor(light: 0x111827, dark: 0xF5F6F8)

    // MARK: 1.3 文字语义别名（视图层优先用这组，而非直呼色阶）

    static let textPrimary     = neutral900   // 标题、ListRow 主标题、正文
    static let textSecondary   = neutral700   // 副标题、次要正文
    static let textTertiary    = neutral500   // 说明文字、时间戳、SectionHeader
    static let textPlaceholder = neutral500   // 输入框占位符（不用 400，会掉到 2.44:1）
    static let textDisabled    = neutral600   // 禁用态文字，配 surfaceSunken 底
    static let textOnPrimary   = onPrimary

    // MARK: 1.4 表面色 Surface
    //
    // 卡片背景四选一规则（解决 #6「白卡 / 灰卡 / 紫卡混用」）：
    //
    //   surfaceBase     → 页面背景。全 App 只有这一层，不用渐变。
    //   surface         → **默认卡片**。承载内容的容器 95% 都用它（白 + 1px 描边）。
    //   surfaceSunken   → 仅用于「已经在白卡内部的嵌套块」：输入框底、次级统计格。
    //                      ❌ 绝不直接铺在页面背景上 —— 那是 Me 页设置分组现在的错误：
    //                         #F1F2F5 的分组坐在 #FBFBFC 的页面上，边界几乎不可见。
    //   surfaceInverse  → **每屏至多一处**，且必须是该屏的唯一主推动作。
    //                      即 Today 页 "Review your English cards" 那张深色卡。
    //                      它是全 App 视觉权重最高的容器，因此必须稀缺。
    //
    //   ⚠️ 淡紫卡 (原 purpleSoft，Today 的 "DUE TODAY") 从表面色体系中移除：
    //      同屏出现「淡紫统计卡 + 深色主推卡」是两个强调面互抢。
    //      统计卡降级为 surface（白卡），强调交给 surfaceInverse 独占。
    //      primarySoft 保留，但只用于「选中态背景 / Badge 底」这类小面积场景。

    static let surfaceBase    = neutral50
    static let surface        = dsColor(light: 0xFFFFFF, dark: 0x14171F)
    static let surfaceSunken  = neutral100
    /// 高强调反相面 —— **真正反相**，不是"深一点的灰"。
    /// ⚠️ 初版深色取 0x272D3B（抬升深灰），模拟器实测：它比页面底 #0B0D12 只亮一点，
    ///    与旁边的普通白卡沦为同一层，浅色下"全屏最重容器"的强调在深色下完全丢失。
    ///    深色改为浅面 + 深色前景，才能保住"每屏唯一强调面"的语义。
    static let surfaceInverse = dsColor(light: 0x111827, dark: 0xF5F6F8)
    /// Tab bar / NavBar / Sheet 的不透明底
    static let surfaceChrome  = dsColor(light: 0xFFFFFF, dark: 0x14171F)
    /// 按压反馈遮罩（ListRow / Card 可点时）
    static let surfacePressed = dsColor(light: 0xF1F2F5, dark: 0x1F2430)

    // MARK: 1.5 反相面上的前景色
    //
    // surfaceInverse 上的文字/图标专用。现有深色卡的 "START LEARNING" 标签
    // 与白色箭头按钮都归入这组。

    /// 浅色：白字于 #111827 上 17.7:1 ✓ ／ 深色：#111827 于 #F5F6F8 上 16.8:1 ✓
    static let textOnInverse          = dsColor(light: 0xFFFFFF, dark: 0x111827)
    /// 反相面次级文字。浅色 7.28:1 ✓ ／ 深色 #4B5563 于 #F5F6F8 上 8.0:1 ✓
    static let textOnInverseSecondary = dsColor(light: 0xA1A6B2, dark: 0x4B5563)
    /// 反相面上的主色标签（eyebrow）。浅色 8.90:1 ✓ ／ 深色 #4338CA 于 #F5F6F8 上 7.5:1 ✓
    static let primaryOnInverse       = dsColor(light: 0xA5B4FC, dark: 0x4338CA)
    /// 反相面上的实心圆形按钮 —— 始终与反相面对比最大
    static let buttonOnInverse        = dsColor(light: 0xFFFFFF, dark: 0x111827)
    static let onButtonOnInverse      = dsColor(light: 0x111827, dark: 0xFFFFFF)

    // MARK: 1.5 描边与分隔

    static let border        = neutral200   // 卡片描边
    static let borderStrong  = neutral300   // 输入框默认描边
    static let separator     = neutral200   // ListRow 之间的分隔线（inset 见 AppLayout）

    // MARK: 1.6 语义色
    //
    // 每个语义提供 3 个 token：fill(块/图标) / text(文字，已加深至 AA) / soft(浅底)
    // ⚠️ success 与 warning 的 fill 值对比度为 3.7:1 / 3.6:1 —— 只能用于图标、
    //    大字(≥18pt bold)、非文字 UI 元素；作为正文文字必须用 *Text 变体。

    static let successFill = dsColor(light: 0x059669, dark: 0x34D399)  // 白底 3.77:1（大字/图标 ✓）
    static let successText = dsColor(light: 0x047857, dark: 0x6EE7B7)  // 白底 5.48:1 ✓
    static let successSoft = dsColor(light: 0xECFDF5, dark: 0x052E22)

    static let warningFill = dsColor(light: 0xB7791F, dark: 0xFBBF24)  // 白底 3.64:1（大字/图标 ✓）
    static let warningText = dsColor(light: 0x92400E, dark: 0xFCD34D)  // 白底 7.09:1 ✓
    static let warningSoft = dsColor(light: 0xFFFBEB, dark: 0x3A2A08)

    static let dangerFill    = dsColor(light: 0xE11D48, dark: 0xF43F5E)  // 白底 4.70:1 ✓（正文亦可）
    static let dangerPressed = dsColor(light: 0x9F1239, dark: 0xE11D48)  // 白字于其上 8.35:1 ✓
    static let dangerText     = dsColor(light: 0xBE123C, dark: 0xFDA4AF)  // 白底 6.28:1 ✓
    static let dangerSoft  = dsColor(light: 0xFFF1F2, dark: 0x3F1220)
    static let onDanger    = dsColor(light: 0xFFFFFF, dark: 0xFFFFFF)
    //
    // ⚠️ 已发现缺陷：现有 AppSurface.coral (#FF6B6B) 被用作 destructive 文字色
    //    （Delete / Sign out / Remove，共 8 处）—— 白底对比度仅 **2.77:1**，
    //    严重低于 AA 4.5:1。第三步全部替换为 dangerText。
    //    coral 仅可作为通知红点等非文字色标，此时用 dangerFill。

    // MARK: 1.7 禁用态
    //
    // 铁律：禁用态**绝不**用 .opacity() 实现 —— 那是 #5 对比度不足的根因。
    // 禁用 = 换填充 + 换文字色，两者都是实色 token。
    // 同时这条规则反向解决 #4：灰色填充是 disabled 的**专属签名**，
    // 任何 enabled 的主操作都不允许长成灰色。

    // ⚠️ disabledFill 必须与 surfaceSunken(neutral100) 不同值 —— 否则禁用按钮
    //    与其上方的输入框底色完全一致，二者在视觉上无法区分（模拟器实测已确认）。
    //    故取 neutral200。
    static let disabledFill   = neutral200   // 禁用按钮填充
    static let disabledText   = neutral600   // 于 disabledFill 上 6.10:1 ✓
    static let disabledBorder = neutral300   // 不能用 neutral200：与 disabledFill 同值，边界会消失
    static let disabledIcon   = neutral400   // 仅图标，无文字含义

    // MARK: 1.8 图标容器
    //
    // 替代原 iconAccent(#3F6D84) / iconSoft(#E9EEF2) 这组"第二主色"。
    // 默认中性；只有当图标代表当前选中/主推项时才升级为 primary 组。

    static let iconDefault       = neutral600
    static let iconMuted         = neutral500
    static let iconContainerBase = neutral100
    static let iconOnAccent      = primaryOnSoft
    static let iconContainerTint = primarySoft

    // MARK: 1.9 Subject 身份色板（分类色，非品牌色）
    //
    // 这是 Subject 编辑页 "Accent color" 的 5 个可选色（CardsHierarchyView.swift:1806）。
    // 它是**功能**，不是主色冲突，因此保留 —— 但必须与品牌主色划清边界：
    //
    //   ✅ 允许用在：Subject 的身份标记（首字母圆底、卡片左侧色条、列表行图标容器）
    //   ❌ 禁止用在：任何 chrome —— 导航栏、Tab bar、主按钮、链接、选中态。
    //      那些永远只用 AppColor.primary。
    //
    // 每色 3 变体：fill（色块/图标）· text（文字，已加深至 AA）· soft（浅底）。
    // indigo 与品牌主色同值，是有意的：它是默认项，让"未选色"的 subject 与品牌一致。

    struct SubjectAccent: Identifiable {
        let id: String
        let fill: Color
        let text: Color
        let soft: Color
        let onFill: Color
    }

    static let subjectAccents: [SubjectAccent] = [
        SubjectAccent(id: "indigo",
                      fill: dsColor(light: 0x4F46E5, dark: 0x6366F1),   // 白底 6.29:1 ✓
                      text: dsColor(light: 0x4338CA, dark: 0xA5B4FC),   // 白底 7.90:1 ✓
                      soft: dsColor(light: 0xEEF2FF, dark: 0x1E1B4B),
                      onFill: dsColor(light: 0xFFFFFF, dark: 0xFFFFFF)),
        SubjectAccent(id: "green",
                      fill: dsColor(light: 0x059669, dark: 0x34D399),   // 白底 3.77:1（非文字 ✓）
                      text: dsColor(light: 0x047857, dark: 0x6EE7B7),   // 白底 5.48:1 ✓
                      soft: dsColor(light: 0xECFDF5, dark: 0x052E22),
                      onFill: dsColor(light: 0xFFFFFF, dark: 0x052E22)),
        SubjectAccent(id: "amber",
                      fill: dsColor(light: 0xB7791F, dark: 0xFBBF24),   // 白底 3.64:1（非文字 ✓）
                      text: dsColor(light: 0x92400E, dark: 0xFCD34D),   // 白底 7.09:1 ✓
                      soft: dsColor(light: 0xFFFBEB, dark: 0x3A2A08),
                      onFill: dsColor(light: 0xFFFFFF, dark: 0x3A2A08)),
        SubjectAccent(id: "sky",
                      fill: dsColor(light: 0x0284C7, dark: 0x38BDF8),   // 白底 4.10:1（非文字 ✓）
                      text: dsColor(light: 0x075985, dark: 0x7DD3FC),   // 白底 7.56:1 ✓
                      soft: dsColor(light: 0xE0F2FE, dark: 0x082F49),
                      onFill: dsColor(light: 0xFFFFFF, dark: 0x082F49)),
        SubjectAccent(id: "purple",
                      fill: dsColor(light: 0x7C3AED, dark: 0xA78BFA),   // 白底 5.70:1 ✓
                      text: dsColor(light: 0x6D28D9, dark: 0xC4B5FD),   // 白底 7.10:1 ✓
                      soft: dsColor(light: 0xF5F3FF, dark: 0x2E1065),
                      onFill: dsColor(light: 0xFFFFFF, dark: 0x2E1065)),
    ]

    static func subjectAccent(_ id: String) -> SubjectAccent {
        subjectAccents.first { $0.id == id } ?? subjectAccents[0]
    }

    // MARK: 1.10 数据可视化 —— Achievements 热力图
    //
    // 5 档单色阶（主色 tint），level0 是"有网格但无数据"，
    // 与 EmptyState 配合解决 #7：网格永远绘制，空数据靠 level0 + 文案表达。

    /// ⚠️ 深色初版取 0x1B1F29，与 surfaceSunken 同值；且它落在卡片 #14171F 上只有 1.09:1，
    ///    空网格几乎不可见 —— 会让 #7 的"网格常驻"方案失效。改用 neutral200 档。
    static let heatLevel0 = dsColor(light: 0xF1F2F5, dark: 0x2A3040)
    static let heatLevel1 = dsColor(light: 0xDDE1FB, dark: 0x2E2A6B)
    static let heatLevel2 = dsColor(light: 0xB4BAF6, dark: 0x3F3A9E)
    static let heatLevel3 = dsColor(light: 0x8288EF, dark: 0x4F46E5)
    static let heatLevel4 = dsColor(light: 0x4F46E5, dark: 0x818CF8)

    static let heatScale: [Color] = [heatLevel0, heatLevel1, heatLevel2, heatLevel3, heatLevel4]
}

// MARK: - 2. 排版 Type

/// 一个排版级别 = 字号 + 字重 + 行高 + 字间距 + Dynamic Type 锚点
struct AppTextStyle {
    let size: CGFloat
    let weight: Font.Weight
    let uiWeight: UIFont.Weight
    /// 目标行高（含行距），非行间距
    let lineHeight: CGFloat
    let tracking: CGFloat
    /// Dynamic Type 缩放锚点
    let metric: UIFont.TextStyle
}

enum AppType {

    /// 34/Bold/40/+0.37 —— 屏级大标题。每屏至多 1 处。
    /// 用于：Today 首页问候标题、Me 主页用户名、启动页 Logotype
    static let display = AppTextStyle(
        size: 34, weight: .bold, uiWeight: .bold,
        lineHeight: 40, tracking: 0.37, metric: .largeTitle
    )

    /// 28/Bold/34/+0.36 —— 次屏级标题、大数字统计。
    /// 用于：Sheet 主标题、Achievements 连胜天数、复习完成页数字
    static let title1 = AppTextStyle(
        size: 28, weight: .bold, uiWeight: .bold,
        lineHeight: 34, tracking: 0.36, metric: .title1
    )

    /// 22/Semibold/28/-0.26 —— 卡片主标题、分组大标题。
    /// 用于：Subject 卡标题、Card 正面文本、模块标题
    static let title2 = AppTextStyle(
        size: 22, weight: .semibold, uiWeight: .semibold,
        lineHeight: 28, tracking: -0.26, metric: .title2
    )

    /// 17/Semibold/22/-0.43 —— 交互文本的默认级别。
    /// 用于：NavBar inline 标题、ListRow 主标题、所有按钮文字
    static let headline = AppTextStyle(
        size: 17, weight: .semibold, uiWeight: .semibold,
        lineHeight: 22, tracking: -0.43, metric: .headline
    )

    /// 15/Regular/20/-0.23 —— 正文默认级别。
    /// 用于：卡片正文、TextField 输入文字、ListRow 副标题、段落说明
    static let body = AppTextStyle(
        size: 15, weight: .regular, uiWeight: .regular,
        lineHeight: 20, tracking: -0.23, metric: .subheadline
    )

    /// 13/Medium/18/-0.08 —— 标签级别。
    /// 用于：SectionHeader、表单字段标签、次级说明文字、Chip 文字
    static let label = AppTextStyle(
        size: 13, weight: .medium, uiWeight: .medium,
        lineHeight: 18, tracking: -0.08, metric: .footnote
    )

    /// 11/Medium/14/+0.07 —— 最小可用级别。
    /// 用于：Badge 计数、Tab bar 文字、热力图月份轴、时间戳
    static let caption = AppTextStyle(
        size: 11, weight: .medium, uiWeight: .medium,
        lineHeight: 14, tracking: 0.07, metric: .caption1
    )

    // 迁移映射（现有代码 → token）：
    //   34        → display
    //   28 / 24   → title1 / title2
    //   22 / 20   → title2
    //   18 / 17   → headline
    //   16 / 15   → body
    //   14 / 13   → label
    //   12 / 11   → caption
    //
    // ✅ 字体家族决策（已确认）：全工程统一 SF，即 .system。
    //
    //   理由：
    //   1. 卡片内容为中英混排（front 为中文，见 CardsHierarchyView.swift:1305）。
    //      SF 无中文字形，iOS 自动回退苹方 PingFang SC —— 这是 Apple 调校过的配对，
    //      字重、基线、字面大小对齐，是 iOS 中英混排的最优解。
    //   2. OPPOSans 仅打包 Regular / Medium / Bold 三档，**缺 Semibold**。
    //      本 scale 的 title2 与 headline 均为 Semibold，其中 headline 是全 App
    //      使用最频繁的一级（NavBar 标题 / ListRow 主标题 / 全部按钮文字）。
    //      Font.custom 遇到缺失字重会静默回退 Regular，标题与正文将失去层次。
    //   3. 本文件的 tracking 值取自 Apple 官方 SF 字距表，对其他字面不成立。
    //
    //   ✅ 已完成清理：
    //      - ReviewSessionView.swift 的 AppFont.* 全部替换为 appText(...)
    //      - Theme.swift（含 enum AppFont）已删除
    //      - Info.plist 的 UIAppFonts 键已移除，Fonts/ 目录及三个 ttf 已删除
    //        （减少 26MB 未压缩资源）
}

extension View {
    /// 应用一个排版 token。行距按 Dynamic Type 缩放后的实际字体行高反推，保证行高精确。
    func appText(_ style: AppTextStyle, color: Color = AppColor.textPrimary) -> some View {
        appTextMetrics(style).foregroundStyle(color)
    }

    /// 只应用字号 / 字重 / 行高 / 字距，**不设前景色**。
    /// 用于颜色由外层 ButtonStyle 决定的场景 —— 若在此处设色，内层 foregroundStyle
    /// 会盖掉 ButtonStyle 的取值。
    func appTextMetrics(_ style: AppTextStyle) -> some View {
        let metrics = UIFontMetrics(forTextStyle: style.metric)
        let scaledSize = metrics.scaledValue(for: style.size)
        let scaledLineHeight = metrics.scaledValue(for: style.lineHeight)
        let naturalLineHeight = UIFont.systemFont(ofSize: scaledSize, weight: style.uiWeight).lineHeight

        return self
            .font(.system(size: scaledSize, weight: style.weight))
            .tracking(style.tracking)
            .lineSpacing(max(0, scaledLineHeight - naturalLineHeight))
    }
}

// MARK: - 3. 间距 Space（4pt 栅格）

enum AppSpace {
    static let none: CGFloat = 0
    /// 4 —— 图标与紧邻文字、Badge 内边距
    static let xs: CGFloat = 4
    /// 8 —— 主副标题之间、Chip 内 padding
    static let sm: CGFloat = 8
    /// 12 —— ListRow 垂直内边距、同组元素间距
    static let md: CGFloat = 12
    /// 16 —— 卡片内边距、ListRow 水平内边距、控件间标准间距
    static let lg: CGFloat = 16
    /// 20 —— 屏幕水平边距（唯一值）
    static let xl: CGFloat = 20
    /// 24 —— 卡片之间、Section 内容与下一个 SectionHeader 之间
    static let xxl: CGFloat = 24
    /// 32 —— Section 之间
    static let xxxl: CGFloat = 32
    /// 40 —— 大区块之间、EmptyState 上下留白
    static let huge: CGFloat = 40
    /// 48 —— 屏幕顶部/底部收尾留白
    static let giant: CGFloat = 48
}

// MARK: - 4. 圆角 Radius

enum AppRadius {
    /// 8 —— Badge、Chip、Tag、小图标容器、热力图格子
    static let sm: CGFloat = 8
    /// 12 —— Button、TextField、ListRow 选中态高亮、嵌套次级块
    static let md: CGFloat = 12
    /// 16 —— Card、分组容器（Grouped ListRow 容器）
    static let lg: CGFloat = 16
    /// 24 —— Sheet / Modal / 全屏卡片 / hero 卡
    static let xl: CGFloat = 24
    /// 圆形 —— 头像、圆形图标按钮、Pill 按钮、进度条
    static let full: CGFloat = 999

    /// 统一使用 .continuous（iOS 连续曲率），禁止 .circular
    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    // 迁移映射：
    //   8 / 11        → sm
    //   14 / 16 / 18  → md (控件) 或 lg (卡片)
    //   20 / 22 / 24  → lg
    //   26 / 28 / 30 / 34 → xl
    //   99            → full
}

// MARK: - 5. 阴影与描边 Elevation
//
// 方向：以描边为主、阴影为辅（Linear / Things 的做法）。
// 现有代码的 radius 34 / 60、y 14 / 24 的大范围软阴影全部废弃 —— 那是"未打磨"观感的主因。

struct AppShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum AppElevation {
    /// L0 —— 无描边无阴影。用于：直接铺在页面上的透明区块、下沉块 surfaceSunken
    case flat
    /// L1 —— 仅 1px 描边。用于：**默认卡片**、分组列表容器（占全部卡片的 90%）
    case card
    /// L2 —— 描边 + 极轻阴影。用于：可拖拽/浮起卡片、Tab bar、吸顶 NavBar 滚动后
    case raised
    /// L3 —— 无描边 + 明确阴影。用于：Sheet、Popover、悬浮主按钮 (FAB)
    case overlay

    var shadow: AppShadow? {
        switch self {
        case .flat, .card:
            return nil
        case .raised:
            return AppShadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        case .overlay:
            return AppShadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 8)
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .flat, .overlay: return 0
        case .card, .raised:  return 1
        }
    }

    var borderColor: Color { AppColor.border }
}

extension View {
    /// 一次性套用「表面 + 圆角 + 描边 + 阴影」，保证四者永远配套出现。
    func appSurface(
        _ elevation: AppElevation = .card,
        fill: Color = AppColor.surface,
        radius: CGFloat = AppRadius.lg
    ) -> some View {
        let shape = AppRadius.shape(radius)
        return self
            .background(fill, in: shape)
            .overlay {
                if elevation.borderWidth > 0 {
                    shape.strokeBorder(elevation.borderColor, lineWidth: elevation.borderWidth)
                }
            }
            .compositingGroup()
            .shadow(
                color: elevation.shadow?.color ?? .clear,
                radius: elevation.shadow?.radius ?? 0,
                x: elevation.shadow?.x ?? 0,
                y: elevation.shadow?.y ?? 0
            )
    }
}

// MARK: - 6. 布局常量 Layout

enum AppLayout {
    /// 屏幕水平边距 —— 全局唯一值，替换现有的 24/20/18/16/14/12/10/9/2/1
    static let screenMargin: CGFloat = AppSpace.xl        // 20

    /// 最小点击区域（HIG / WCAG 2.5.8）
    static let minHitTarget: CGFloat = 44

    /// NavBar 内容高度（不含安全区）
    static let navBarHeight: CGFloat = 44
    /// NavBar 内圆形图标按钮直径（视觉 36，点击区域扩至 44）
    static let navIconButton: CGFloat = 36

    /// ListRow 最小高度
    static let rowMinHeight: CGFloat = 52
    /// ListRow 内水平边距
    static let rowPaddingH: CGFloat = AppSpace.lg         // 16
    /// ListRow 内垂直边距
    static let rowPaddingV: CGFloat = AppSpace.md         // 12
    /// 分隔线左缩进 = 行内边距 + 图标宽 + 图标文字间距（有图标时）
    static let separatorInsetPlain: CGFloat = AppSpace.lg // 16
    static let separatorInsetIcon: CGFloat = 56
    static let separatorHeight: CGFloat = 1 / UIScreen.main.scale

    /// 卡片内边距
    static let cardPadding: CGFloat = AppSpace.lg         // 16
    /// 卡片之间的间距
    static let cardGap: CGFloat = AppSpace.md             // 12

    /// 控件高度
    static let buttonHeightLarge: CGFloat = 50            // 全宽主按钮
    static let buttonHeightMedium: CGFloat = 44           // 常规按钮 = 最小点击区
    static let buttonHeightSmall: CGFloat = 32            // 内联/Chip 按钮（需外扩点击区至 44）
    static let fieldHeight: CGFloat = 48                  // TextField 单行

    /// 图标尺寸
    static let iconSM: CGFloat = 16
    static let iconMD: CGFloat = 20
    static let iconLG: CGFloat = 24
    /// 图标容器（列表行首的圆角方块）
    static let iconContainer: CGFloat = 32

    /// 头像
    static let avatarSM: CGFloat = 32
    static let avatarMD: CGFloat = 44
    static let avatarLG: CGFloat = 72

    /// 描边线宽
    static let hairline: CGFloat = 1
    static let focusRingWidth: CGFloat = 2

    /// 答案遮词的词间距。**排版派生值，不受 4pt 栅格约束** ——
    /// 它要贴近字体的空格宽（22pt SF 约 6pt）。用 AppSpace.sm(8) 会把句子拆散，
    /// 读起来像并列的词而不是一句话（模拟器实测）。
    static let answerTokenGap: CGFloat = 6

    /// 热力图
    static let heatCell: CGFloat = 12
    static let heatCellGap: CGFloat = 3
}

// MARK: - 7. 动效 Motion

enum AppMotion {
    /// 120ms —— 按压反馈、颜色切换
    static let instant = Animation.easeOut(duration: 0.12)
    /// 200ms —— 展开/收起、选中态切换（默认）
    static let standard = Animation.easeInOut(duration: 0.20)
    /// 320ms 弹性 —— Sheet 呈现、卡片翻面
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// 按压时的缩放比（配合 instant 使用）
    static let pressScale: CGFloat = 0.97
}

// MARK: - 8. 图标 Icon
//
// ===== #8 的正确解法（初版规范已被模拟器实测推翻）=====
//
// 初版写的是「未选中 outline / 选中 fill」。**在 iOS 上做不到**：
// 系统会把 Tab bar 图标强制替换成该符号的 .fill 变体，无视传入的符号名。
//
// 实测（iPhone 16 Pro）：把默认选中项从 .home 改到 .me，两张截图对比 ——
// 图标字形完全没变、只有颜色变；house / person 在未选中态同样渲染为实心。
// wand.and.sparkles 之所以保持线性，仅仅因为它**没有** .fill 变体，
// 结果反而是 AI 一个线性、其余三个实心 —— 比改造前更不一致。
//
// 故 Tab bar 规则改为跟随平台：
//   · 四个图标全部使用**有 fill 变体**的符号
//   · 选中态**只靠 tint 区分**（AppColor.primary vs iconMuted）
//   · AI 页换回 sparkles —— 它本身是实心字形，与其余三个同重
//
// 非 Tab bar 的图标（列表行 / NavBar / 卡片内）不受此限，一律 outline，
// fill 仅保留给「选中 / 激活」语义。

enum AppIcon {
    static let tabHome  = "house.fill"
    static let tabCards = "rectangle.stack.fill"
    static let tabAI    = "sparkles"
    static let tabMe    = "person.fill"

    /// 导航语义符号 —— 全工程唯一来源，禁止逐屏另选
    static let back      = "chevron.left"
    static let close     = "xmark"
    static let disclose  = "chevron.right"
    static let confirm   = "checkmark"
    static let add       = "plus"
    static let more      = "ellipsis"
    static let search    = "magnifyingglass"

    /// 统一的图标字重（与 headline / body 字重视觉配平）
    static let weight: Font.Weight = .medium

    static func font(_ size: CGFloat) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - 9. 迁移映射表（第三步逐屏替换时对照）
//
// AppSurface.background   → AppColor.surfaceBase
// AppSurface.floating     → AppColor.surface
// AppSurface.cardSubtle   → AppColor.surfaceSunken
// AppSurface.grouped      → AppColor.surfaceSunken
// AppSurface.text         → AppColor.textPrimary
// AppSurface.textSecondary→ AppColor.textSecondary
// AppSurface.muted        → AppColor.textTertiary       (#6B7280 → #646B7A，修复灰底 4.43:1 不达标)
// AppSurface.line         → AppColor.border
// AppSurface.dark         → AppColor.textPrimary
// AppSurface.accent       → AppColor.primary
// AppSurface.accentSoft   → AppColor.primarySoft
// AppSurface.iconAccent   → ❌ 删除（这是 #2 的"第二主色" #3F6D84）
//                             ListRow 标题文字 → AppColor.textPrimary
//                             行首图标        → AppColor.iconDefault
// AppSurface.iconSoft     → AppColor.iconContainerBase
// AppSurface.indigoLight  → AppColor.heatLevel2
// AppSurface.slateLight   → AppColor.neutral300
// AppSurface.shadow       → ❌ 删除 → 走 AppElevation
//
// —— 以下四个不是"多余主色"，是 Subject 身份色板，迁入 subjectAccents ——
// AppSurface.green / greenSoft   → subjectAccent("green")   ＋ 语义 successFill/Text
// AppSurface.amber               → subjectAccent("amber")   ＋ 语义 warningFill/Text
// AppSurface.sky / skySoft       → subjectAccent("sky")      （仅身份色，无语义角色）
// AppSurface.purple / purpleSoft → subjectAccent("purple")   （仅身份色，无语义角色）
//   ⚠️ 例外：HomeView.swift:110/131/140 用 purple/purpleSoft 画 Today 的
//      "DUE TODAY" 淡紫统计卡 —— 那是误用身份色做 chrome。
//      该卡改为 AppColor.surface + textPrimary + textTertiary（普通白卡）。
//
// AppSurface.rose / roseSoft → AppColor.dangerFill / dangerSoft
// AppSurface.coral           → AppColor.dangerText （文字场景，修复 2.77:1 → 6.28:1）
//                            → AppColor.dangerFill （通知红点等非文字色标）
//
// Theme.* (Theme.swift 整个文件)  → ❌ 整体删除
//   3 套可切换主题 (forest/ink/plum) 与"单一主色"目标冲突，
//   且 ScreenBackground 的多层渐变是背景色不统一的直接来源。
//   如需保留主题切换能力，第三步可在 AppColor.primary 之上加一层 tint 映射，
//   但中性色阶与表面色必须固定。
