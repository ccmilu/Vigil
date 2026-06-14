<div align="center">

<img src="docs/assets/logo.png" width="128" alt="Vigil" />

# Vigil

**Let AI keep you focused.**

Real-time screen analysis · Gently pulls you back when you drift

[![Release](https://img.shields.io/github/v/release/ccmilu/Vigil?include_prereleases&label=release)](https://github.com/ccmilu/Vigil/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://github.com/ccmilu/Vigil/releases)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://www.swift.org/)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Stars](https://img.shields.io/github/stars/ccmilu/Vigil?style=social)](https://github.com/ccmilu/Vigil/stargazers)

English · [简体中文](README.md)

</div>

---

https://github.com/user-attachments/assets/5f46c8cd-623d-4fe4-be5d-33eb92025ad5

<p align="center">
  Write a goal → AI watches your screen → Pulls you back when you drift → Reflective AI summary
</p>

## Why Vigil

- **Privacy first** — Vigil never collects or uploads any of your data. You can also connect a locally-running AI model (e.g. LM Studio / Ollama) so screen content never leaves your machine.
- **Real-time screen analysis** — The moment you switch to your phone or open a social app, Vigil reacts.
- **Tiered interventions, no flow-breaking** — AI classifies your state into 4 levels with matching intervention strength:
  - **Focused**: silent. Vigil stays out of your way.
  - **Drifting** (sustained): Dynamic Island expands with a gentle hint. No sound, no overlay.
  - **Distracted**: Dynamic Island expands + system notification + full-screen overlay all at once. If you stay distracted, Vigil repeats every so often.
  - **Idle** (you're away from the computer): Dynamic Island expands + sound repeats until you come back and move your mouse or type.
  
  All reminders can be tuned in settings.
- **Reflection at the end of every session** — AI tells you how long you focused, where you drifted, and where your attention actually went.
- **Native macOS experience** — Liquid Glass main window, Dynamic Island, menu bar item, global shortcuts. Feels like it belongs.

## Screenshots

<table>
  <tr>
    <td align="center" width="50%"><b>Main window + history</b><br/><img src="docs/screenshots/main.jpg" /></td>
    <td align="center" width="50%"><b>Write a goal, pick a duration</b><br/><img src="docs/screenshots/promise.jpg" /></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><b>Distracted · Dynamic Island + system notification</b><br/><img src="docs/screenshots/guard.jpg" /></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><b>Distracted · Full-screen overlay + Dynamic Island</b><br/><img src="docs/screenshots/overlay.jpg" /></td>
  </tr>
  <tr>
    <td align="center" width="50%"><b>Session end · AI summary</b><br/><img src="docs/screenshots/summary.jpg" /></td>
    <td align="center" width="50%"><b>History · Timeline + per-frame screenshots</b><br/><img src="docs/screenshots/history.jpg" /></td>
  </tr>
</table>

## How it differs from typical focus apps

| Capability | Typical focus app | Vigil |
|---|:---:|:---:|
| Timer + AI summary | ❌ | ✅ |
| **AI vision actually judges whether you're focused** | ❌ | ✅ |
| **Local models (LM Studio / Ollama)** | ❌ | ✅ |
| **Connect any AI provider** | ❌ | ✅ |
| Fully local data storage | varies | ✅ |
| Price | mostly subscription | Free & open source |

## Install

### DMG download (recommended)

1. Grab the latest `Vigil-x.x.x.dmg` from [Releases](../../releases)
2. Double-click the DMG → drag Vigil into Applications
3. If macOS blocks first launch: System Settings → Privacy & Security → click "Open Anyway" next to the blocked Vigil.app
4. First launch requests 4 permissions: **Screen Recording / Accessibility / Notifications / Keychain**. Allow all.

### Homebrew Cask

Planned.

## Configure your AI provider

On first launch the onboarding will guide you to add a provider. Common setups:

| Provider | Base URL | API Key | Model |
|---|---|---|---|
| **LM Studio** (local) | `http://127.0.0.1:1234/v1` | any string | a loaded vision model |
| **Ollama** (local) | `http://127.0.0.1:11434/v1` | any string | a pulled vision model |
| **OpenAI** | `https://api.openai.com/v1` | your OpenAI key | `gpt-4o-mini` |

Any other OpenAI-compatible provider (DeepSeek / Kimi / Doubao / Zhipu / Qwen / OpenRouter / SiliconFlow ...) works the same way: Base URL + key + a vision model.

## Roadmap (tentative)

**v0.2**
- [ ] Weekly heatmap
- [ ] Automatic screenshot cleanup
- [ ] Homebrew installation

**v0.3+**
- [ ] More API protocols (Anthropic / Gemini)
- [ ] App allowlist / blocklist
- [ ] Ambient white noise
- [ ] iCloud sync
- [ ] Weekly / monthly markdown export

## FAQ

### The reminders feel too frequent. Can I dial them back?

Yes. Every reminder behavior is tunable in **Settings → Reminders**.

### Does Vigil collect my data?

Vigil never collects or uploads any of your data. All screenshots stay on your local disk. If you want screen content to never leave your machine, connect a local AI model (LM Studio / Ollama).

### Will it run on macOS 13 / Intel Mac?

Requires macOS 14 or later. Intel Mac should work in theory but is untested.

### Why is it called Vigil?

A vigil is keeping watch through the night — staying awake and alert while others sleep. Vigil is the watcher who stays alert for your focus so you don't have to.

## Project layout

```
Vigil/
├── App/                @main entry, entitlements
├── Sources/
│   ├── AI/             AI service abstraction & implementations
│   ├── Capture/        Screen capture + dHash + system detection
│   ├── Session/        Session state machine, Dynamic Island, menu bar
│   ├── UI/             SwiftUI views
│   ├── Settings/       Provider / Keychain / @AppStorage
│   ├── Persistence/    SwiftData @Model + Migrations
│   └── Config/         Demo / Local config placeholders
└── Tests/              Unit + integration tests
```

## Feedback

- Bug reports / feature requests: [New Issue](../../issues/new)
- Email: [ccmilu@outlook.com](mailto:ccmilu@outlook.com)
- Enjoying Vigil? A Star is the best support.

## License

[GPL-3.0](LICENSE) © 2026 Jason
