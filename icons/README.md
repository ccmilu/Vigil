# Focus 图标设计稿

4 个方案 × 每个 3 个 layer SVG + 1 个 squircle 预览。

| 方案 | 风格 | 文件夹 |
|---|---|---|
| A | 靶心 + 暖橙径向渐变 | `A-target-warm/` |
| B | 靶心 + 冷蓝径向渐变 + 暖色中心点 | `B-target-cool/` |
| C | 极简单圆点 + 玻璃环 + 深背景 | `C-minimal-dot/` |
| D | 大写字母 F + 暖橙背景 | `D-letter-F/` |

每个文件夹包含：
- `background.svg` — 渐变底色
- `midground.svg` — 中景元素（同心圆 / 玻璃环）；D 方案无
- `foreground.svg` — 前景符号（中心点 / F 字）
- `preview.svg` — squircle 裁切后的合成预览（不是 Icon Composer 最终效果，仅看构图）

## 用 Icon Composer 合成

1. `open /Applications/Xcode.app/Contents/Applications/Icon\ Composer.app`
2. File → New → 选 macOS App Icon
3. 拖 `background.svg` → 标记为 Background
4. 拖 `midground.svg`（如有）→ 标记为 Middle，Material 选 `Liquid Glass`
5. 拖 `foreground.svg` → 标记为 Foreground，Material 选 `Liquid Glass`，Z-depth 调高
6. File → Export → 保存为 `Focus.icon`
7. 拖进 Xcode `Resources/Assets.xcassets`

注意：preview.svg 看不到液态玻璃质感，那是 Icon Composer 的着色器才有的。
