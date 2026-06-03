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
    ///   - intensity: 玻璃浓度，默认 `.regular`。
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
