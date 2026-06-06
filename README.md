<div align="center">

<img src="docs/assets/logo.png" width="128" alt="Vigil" />

# Vigil

**AI 守护型专注 macOS App**

支持本地模型 · 兼容 OpenAI 格式API

[![Release](https://img.shields.io/github/v/release/ccmilu/Vigil?include_prereleases&label=release)](https://github.com/ccmilu/Vigil/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://github.com/ccmilu/Vigil/releases)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)](https://www.swift.org/)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Stars](https://img.shields.io/github/stars/ccmilu/Vigil?style=social)](https://github.com/ccmilu/Vigil/stargazers)

</div>

---

https://github.com/ccmilu/Vigil/releases/download/v0.1.0-media/6.6.2.mp4

## 为什么是 Vigil

- **不绑云端** —— 自带 OpenAI / Kimi / DeepSeek / Doubao / Ollama / LM Studio 等任意 OpenAI 兼容厂商，截图不外传也能跑
- **真守护，不只是计时器** —— AI 每 5 秒看屏一次，走神时灵动岛提醒 + 全屏遮罩 + 系统通知三路并发把你拉回
- **原生 macOS 体验** —— Liquid Glass 玻璃化主窗口、灵动岛、菜单栏常驻图标、全局快捷键
- **AI 复盘** —— 会话结束自动复盘 4 档时间分布（专注 / 走神 / 分心 / 闲置），让你看清自己刚才到底干了什么

## 演示截图

<table>
  <tr>
    <td align="center" width="50%"><b>主窗口 · Streak + 历史</b><br/><img src="docs/screenshots/main.jpg" /></td>
    <td align="center" width="50%"><b>写一句承诺，选时长</b><br/><img src="docs/screenshots/promise.jpg" /></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><b>实时监督 · 走神瞬间，刘海岛红 pulse + 系统通知第一时间提醒</b><br/><img src="docs/screenshots/guard.jpg" /></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><b>仍不回头 · 全屏遮罩 + 「我回来了」仪式感按钮把你拦下来</b><br/><img src="docs/screenshots/overlay.jpg" /></td>
  </tr>
  <tr>
    <td align="center" width="50%"><b>会话结束 · AI 复盘 4 档时间分布</b><br/><img src="docs/screenshots/summary.jpg" /></td>
    <td align="center" width="50%"><b>历史详情 · 时间轴 + 每帧截图</b><br/><img src="docs/screenshots/history.jpg" /></td>
  </tr>
</table>

## 与普通专注 App 的区别

| 能力 | 普通专注 App | Vigil |
|---|:---:|:---:|
| 倒计时 + 屏蔽干扰 App | ✅ | ✅ |
| **AI 视觉判断你是否专注** | ❌ | ✅ |
| **接入任意 AI Provider** | ❌ | ✅ |
| **本地模型 (LM Studio / Ollama)** | ❌ | ✅ |
| 走神时全屏遮罩拉回 | 偶有 | ✅ |
| 数据完全本地存储 | 因 App 而异 | ✅ |
| 价格 | 多数订阅制 | 免费开源 |

## 安装

### DMG 下载（推荐）

1. 到 [Releases](../../releases) 下载最新 `Vigil-x.x.x.dmg`
2. 双击 DMG → 把 Vigil 拖进 Applications 文件夹
3. 首次启动若被系统阻止：系统设置 → 隐私与安全 → 在「已阻止 Vigil.app」处点「仍要打开」
4. 首启会请求 4 个权限：**屏幕录制 / 辅助功能 / 通知 / 钥匙串**，全部允许

### Homebrew Cask

计划中（v0.1 稳定后提交）。

## 配置 AI 服务

首次启动时，根据引导提示添加一个 Provider。常用配置：

<details>
<summary><b>LM Studio（本地，推荐隐私敏感用户）</b></summary>

- Base URL: `http://127.0.0.1:1234/v1`
- API Key: 任意字符串（LM Studio 不校验）
- Model: 你加载的多模态模型名，如 `qwen2-vl-7b-instruct`

</details>

<details>
<summary><b>Ollama（本地）</b></summary>

- Base URL: `http://127.0.0.1:11434/v1`
- API Key: `ollama`
- Model: 你 `ollama pull` 的多模态模型，如 `llama3.2-vision`

</details>

<details>
<summary><b>DeepSeek</b></summary>

- Base URL: `https://api.deepseek.com/v1`
- API Key: 你的 DeepSeek key
- Model: `deepseek-vl2`（必须是 vision 模型）

</details>

<details>
<summary><b>OpenAI</b></summary>

- Base URL: `https://api.openai.com/v1`
- API Key: 你的 OpenAI key
- Model: `gpt-4o-mini`（性价比高）或 `gpt-4o`（更准）

</details>

## 工作原理

每帧（每 5 秒）按顺序过 5 道闸门，绝大多数帧都不会调 AI：

1. **idle 检测** —— 鼠标键盘 30s 无动作，跳过 AI 直接标 idle
2. **屏幕抓取** —— ScreenCaptureKit 抓 active 窗口；桌面 only / 无窗口跳过
3. **AI 节流** —— 上一帧 AI 还在跑就跳过，AI 完成时立即续跑最新帧（latest-only 重入）
4. **dHash 去重** —— 16×16 dHash 距离 < 30 跳过 AI（屏幕没变）
5. **任务超时** —— 单帧 AI 调用硬超时，超时回落上一次结果

会话结束后 AI 基于本次所有 AnalysisRecord 生成自然语言复盘。

> [!note]- 完整架构与设计取舍
>
> ### 数据层
> SwiftData 持久化 `FocusSession` / `AnalysisRecord` / `StreakInfo` / `PlayTimer`。截图 jpg 落在 `~/Library/Application Support/Vigil/Screenshots/<sessionID>/`，每个 session 一个目录，含 `diagnostic.jsonl` 决策日志。
>
> ### Session 状态机
> ```
> idle → preparing → running → analyzing → completed
>                ↓
>            resting（休息倒计时，无截屏）
> ```
>
> ### dHash 阈值经验
> 0-15 几乎不动；15-30 滚动 / 光标；30-60 切 tab / 段落；60+ 切 app。默认 30。
>
> ### AI 服务层
> `AIService` protocol 三方法（`analyzeTask` / `analyzeFrame` / `summarize`）。`OpenAICompatibleService` 是唯一实现，覆盖所有 OpenAI 兼容厂商。本地 host（localhost / 127.0.0.1 / 192.168.x / 10.x / .local）自动剥离 `detail` 字段避免 LM Studio / Ollama 报错。
>
> ### 5 秒 tick 节奏
> 给用户可预期的监督密度。AI 慢时由 latest-only 重入兜底，不会丢帧也不会堆积。

## 项目结构

```
Vigil/
├── App/                @main 入口、entitlements
├── Sources/
│   ├── AI/             AI 服务抽象与实现
│   ├── Capture/        截屏 + dHash + 系统检测
│   ├── Session/        会话状态机、刘海岛、菜单栏
│   ├── UI/             SwiftUI 视图
│   ├── Settings/       Provider / Keychain / @AppStorage
│   ├── Persistence/    SwiftData @Model + Migrations
│   └── Config/         Demo / Local 配置占位
└── Tests/              单元测试 + 集成测试
```

## Roadmap

**v0.2**
- [ ] Streak 周历热力图（GitHub 风格方格图）
- [ ] 截图自动清理（30 天保留期）
- [ ] 9 个 PlayTimer + 9 个全局快捷键
- [ ] Homebrew Cask 公式

**v0.3+**
- [ ] Anthropic / Gemini 协议族
- [ ] 自定义 prompt（Settings 暴露）
- [ ] App 白名单 / 黑名单
- [ ] 环境白噪音
- [ ] iCloud 同步
- [ ] 周报 / 月报导出

## FAQ

<details>
<summary><b>截图会发到哪？</b></summary>

取决于你配的 Provider。本地 LM Studio / Ollama 完全离线，不出本机；云端厂商发到对应 API 端点。可在「设置 → AI 服务」里看每个 Provider 的目的地。
</details>

<details>
<summary><b>5 秒截一次屏会不会卡？</b></summary>

不会。dHash 去重让 80%+ 的帧不调 AI（屏幕没变直接 skip），AI 调用走 actor 异步不阻塞主线程。M 系列 Mac 上 CPU 几乎无感。
</details>

<details>
<summary><b>macOS 13 / Intel Mac 能用吗？</b></summary>

需要 macOS 14+。用了 macOS 14 才有的 ScreenCaptureKit 增量 API 和 Liquid Glass 材质。Intel Mac 理论可跑但未做兼容测试。
</details>

<details>
<summary><b>数据放在哪？能导出吗？</b></summary>

全在 `~/Library/Application Support/Vigil/`，SwiftData 数据库 + 截图 jpg。当前版本无导出功能，v0.3 计划做 markdown 导出。
</details>

<details>
<summary><b>为什么叫 Vigil？</b></summary>

Vigil = 守夜人 / 警觉守望，守护你的专注。
</details>

<details>
<summary><b>能不能不弹遮罩，只用通知？</b></summary>

可以。「设置 → 干扰」里关掉「分心时显示遮罩」即可，保留通知和刘海岛 pulse。
</details>

## 反馈

- Bug 报告 / 功能建议：[New Issue](../../issues/new)
- 讨论：[Discussions](../../discussions)
- 邮件联系：[ccmilu@outlook.com](mailto:ccmilu@outlook.com)
- 喜欢这个项目？给个 Star 是最大鼓励

## License

[GPL-3.0](LICENSE) © 2026 Jason

任何人可以自由使用、修改、分发本项目；但**再分发的修改版本必须以 GPL-3.0 同等条款开源**（含完整源码 + License 文件）。商用同样需开源衍生作品。
