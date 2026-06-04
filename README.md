# Vigil

AI 守护型专注 App（macOS 14+），可接入任意 OpenAI 兼容的 AI 厂商及本地部署的多模态模型。

详细产品需求见 [`docs/PRD.md`](docs/PRD.md)。

## 一、目录结构

```
Vigil/
├── App/                        @main 入口、Info.plist、entitlements
├── Sources/
│   ├── AI/                     AI 服务抽象与实现
│   ├── Models/                 数据模型（Codable / @Model）
│   ├── UI/                     SwiftUI 视图、面板、ViewModel
│   └── Config/                 Demo 阶段硬编码配置
├── Resources/                  Assets.xcassets 等资源
├── Tests/FocusTests/           单元测试 + 集成测试（target 名为 VigilTests）
├── docs/                       PRD、prompt 模板
├── scripts/                    一键脚本（生成 / 构建 / 测试 / 运行）
├── Project.yml                 XcodeGen 项目描述
└── Vigil.xcodeproj             由 xcodegen 生成（已 .gitignore）
```

## 二、首次启动

```bash
# 1. 装 xcodegen（一次性）
brew install xcodegen

# 2. 生成 Vigil.xcodeproj
./scripts/generate.sh

# 3. 用 Xcode 打开
open Vigil.xcodeproj
```

之后日常开发用 Xcode 即可。改了 `Project.yml` 或新增 / 移动文件后再跑 `./scripts/generate.sh`。

## 三、本地 AI 配置

当前 demo 写死在 `Sources/Config/DemoConfig.swift`：

```swift
baseURL = http://192.168.1.23:1234/v1   // LM Studio 局域网地址
model   = "qwen2.5-vl-7b-instruct"
apiKey  = "lm-studio"
```

改成你实际的地址 / 模型 ID 即可。

**先确认 LM Studio 可达**：

```bash
./scripts/probe-lmstudio.sh           # 默认 192.168.1.23:1234
./scripts/probe-lmstudio.sh host:port # 自定义
```

## 四、运行 Demo

任选一种：

| 方式 | 命令 | 适合 |
|---|---|---|
| Xcode | `open Focus.xcodeproj` → ⌘R | 日常开发，能断点 / 看日志 |
| 命令行 | `./scripts/run.sh` | 快速验证一次 build |

操作流程：

1. App 启动后显示主窗口
2. 按 ⌘⌥Space → 弹出 Promise 浮窗
3. 输入承诺（例如"写一份周报"）→ 回车
4. 等 AI 返回 → 主窗口显示 taskType / suggestion

## 五、测试

```bash
./scripts/test.sh                # 单元测试（mock，离线）
./scripts/test.sh --integration  # 同时跑集成测试（连真实 LM Studio）
```

- 单元测试用 `URLProtocol` 拦截 URLSession，不依赖网络
- 集成测试只在 `RUN_INTEGRATION=1` 时跑

## 六、常用脚本

```bash
./scripts/generate.sh          # 重新生成 .xcodeproj
./scripts/build.sh             # 命令行构建
./scripts/test.sh              # 跑测试
./scripts/run.sh               # 构建并启动
./scripts/probe-lmstudio.sh    # 探活 LM Studio
```
