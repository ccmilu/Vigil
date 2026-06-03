import SwiftUI

// MARK: - 公共 API

/// 液态玻璃材质浓度。
///
/// - 在 macOS 26+ 上：原生 Glass 本身自适应明暗，浓度差异主要通过
///   tint 透明度与是否处于 `GlassEffectContainer` 控制；此处的 intensity
///   仅在没有显式 tint 时作为提示存在，原生路径下不直接区分。
/// - 在 macOS 14-25 上：实打实映射到不同浓度的 `Material`。
enum GlassIntensity: Sendable {
    /// 极轻——badge / chip / 时间轴行等"几乎透明"的小元素
    case ultraThin
    /// 轻——一般卡片背景
    case thin
    /// 标准——窗口级背景、主面板
    case regular
    /// 强——重要的浮层、模态卡
    case prominent

    fileprivate var fallbackMaterial: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin:      return .thinMaterial
        case .regular:   return .regularMaterial
        case .prominent: return .thickMaterial
        }
    }
}

extension View {
    /// 给当前 View 套一层液态玻璃背景。
    ///
    /// macOS 26+ 走原生 `.glassEffect()`；macOS 14-25 回退到 `Material` + 细边描边。
    /// 项目内所有"卡片 / chip / badge / 窗口"应统一通过此 modifier 来加玻璃，
    /// 未来全量切到 macOS 26+ 后可以直接删 fallback 分支。
    ///
    /// - Parameters:
    ///   - shape: 玻璃形状。常用 `.rect(cornerRadius:)` 或 `.capsule`。
    ///   - tint: 可选染色（半透明叠加）。badge / 卡片想要颜色提示时填上。
    ///   - intensity: 玻璃浓度,默认 `.regular`。
    @ViewBuilder
    func liquidGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        intensity: GlassIntensity = .regular
    ) -> some View {
        if #available(macOS 26.0, *) {
            modifier(NativeGlassModifier(shape: shape, tint: tint))
        } else {
            modifier(FallbackGlassModifier(shape: shape, tint: tint, intensity: intensity))
        }
    }

    /// 玻璃风格的按钮样式。macOS 26+ 用 `.glass` / `.glassProminent`，
    /// 旧系统回退到 `.bordered` / `.borderedProminent`。
    ///
    /// 用法和 `.buttonStyle(.bordered)` 一致——直接接在 Button 后面。
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - macOS 26+ 原生实现

@available(macOS 26.0, *)
private struct NativeGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        // Glass 当前 SDK 暴露 .regular / .identity 两个静态成员；
        // 浓度差异主要通过 tint 透明度体现。
        let glass: Glass = {
            if let tint {
                return Glass.regular.tint(tint)
            }
            return .regular
        }()
        return content.glassEffect(glass, in: shape)
    }
}

// MARK: - macOS 14-25 回退实现

// MARK: - 把承载窗口透明化

/// 找到自身所在的 NSWindow，把背景置为透明，让 SwiftUI 内容侧的 material
/// 或 glass 能真正透出底层（桌面 / 父窗口）。
///
/// 用法：在 SwiftUI View 上叠 `.background(GlassWindowAccessor())`。
/// 主窗口、设置窗口、sheet 都可以共用。
struct GlassWindowAccessor: NSViewRepresentable {
    /// 是否同时把 titlebar 透明化（主窗口需要，sheet 不需要）
    var transparentTitlebar: Bool = false

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { apply(view: v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // sheet 偶尔会在 view 嵌入后才设好不透明 layer，重复 apply 一次兜底
        DispatchQueue.main.async { apply(view: nsView) }
    }

    private func apply(view v: NSView) {
        guard let window = v.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // sheet 的 contentView 可能有不透明 backing layer，强制清掉
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = .clear
        }
        if transparentTitlebar {
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}

// MARK: - macOS 14-25 回退实现

private struct FallbackGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let intensity: GlassIntensity

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(intensity.fallbackMaterial)
                    if let tint {
                        shape.fill(tint)
                    }
                }
            }
            .overlay {
                // 细边模拟玻璃边缘的高光反射
                shape.stroke(.white.opacity(0.08), lineWidth: 0.5)
            }
    }
}

// MARK: - 预览

#Preview("Liquid Glass · 浓度对照") {
    LiquidGlassPreviewWrapper {
        VStack(alignment: .leading, spacing: 14) {
            Text("不同浓度（rect cornerRadius 12）")
                .font(.caption.smallCaps())
                .foregroundStyle(.white.opacity(0.8))

            cardRow("ultraThin", intensity: .ultraThin)
            cardRow("thin",      intensity: .thin)
            cardRow("regular",   intensity: .regular)
            cardRow("prominent", intensity: .prominent)

            Divider().background(.white.opacity(0.3))

            Text("capsule + tint（badge 用法）")
                .font(.caption.smallCaps())
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 8) {
                tintBadge("fully",      color: .green)
                tintBadge("wandering",  color: .yellow)
                tintBadge("distracted", color: .red)
                tintBadge("idle",       color: .gray)
            }

            Divider().background(.white.opacity(0.3))

            Text("带 tint 的卡片（StreakCard 风格）")
                .font(.caption.smallCaps())
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 10) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("7").font(.system(size: 28, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("连续打卡天数").font(.caption).foregroundStyle(.secondary)
                    Text("最长 12 天").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(12)
            .liquidGlass(
                in: .rect(cornerRadius: 12),
                tint: .orange.opacity(0.15),
                intensity: .regular
            )
        }
        .padding(24)
    }
    .frame(width: 520, height: 560)
}

#Preview("Liquid Glass · PromisePanel 模拟") {
    LiquidGlassPreviewWrapper {
        VStack(alignment: .leading, spacing: 16) {
            Text("This time I promise to...")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
            Text("完成季度报告初稿")
                .font(.title3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(in: .rect(cornerRadius: 10), intensity: .ultraThin)
            HStack(spacing: 8) {
                ForEach([10, 15, 25, 45, 60], id: \.self) { m in
                    Text("\(m)")
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .liquidGlass(
                            in: .capsule,
                            tint: m == 25 ? Color.accentColor.opacity(0.3) : nil,
                            intensity: .ultraThin
                        )
                }
            }
        }
        .padding(28)
        .liquidGlass(in: .rect(cornerRadius: 24), intensity: .prominent)
        .padding(40)
    }
    .frame(width: 600, height: 360)
}

/// 给预览垫一张彩色渐变底 + 几何图形，否则玻璃效果看不出折射 / 染色。
private struct LiquidGlassPreviewWrapper<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.32, blue: 0.78),
                         Color(red: 0.66, green: 0.22, blue: 0.62),
                         Color(red: 0.96, green: 0.42, blue: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 加几个白色圆圈作"光斑"——能看出玻璃折射边缘
            Circle().fill(.white.opacity(0.22)).frame(width: 220, height: 220)
                .offset(x: -120, y: -80)
            Circle().fill(.white.opacity(0.18)).frame(width: 140, height: 140)
                .offset(x: 140, y: 120)

            content()
        }
    }
}

@MainActor @ViewBuilder
private func cardRow(_ label: String, intensity: GlassIntensity) -> some View {
    Text(label)
        .font(.callout.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 16)
        .liquidGlass(in: .rect(cornerRadius: 12), intensity: intensity)
}

@MainActor @ViewBuilder
private func tintBadge(_ label: String, color: Color) -> some View {
    Text(label)
        .font(.caption2.bold())
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(color)
        .liquidGlass(in: .capsule, tint: color.opacity(0.22), intensity: .ultraThin)
}
