# Vigil

AI 守护型专注 macOS App（macOS 14+）。

> 写一句你这次要做的承诺 → AI 每 5 秒看一眼屏幕判断你是否在专注 →
> 走神时通知 + 全屏遮罩 + 刘海岛红色 pulse 把你拉回 → 会话结束 AI 复盘。

支持任意 OpenAI 兼容厂商（OpenAI / Kimi / DeepSeek / Doubao / 智谱 / 阿里千问 等）
+ 本地 LM Studio / Ollama，不强绑云端。

## 安装

到 [Releases](../../releases) 下载最新 `.dmg`：

1. 双击 DMG → 把 Vigil 拖进 Applications 文件夹
2. 首次启动若被系统阻止：系统设置 → 隐私与安全 → 在「已阻止 Vigil.app」处点「仍要打开」
3. 首次启动后到「设置 → AI 服务」配置你的 Provider

## 项目结构（仓库内可见部分）

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

构建相关的 `Project.yml`（XcodeGen）/ `Vigil.xcodeproj` / `scripts/` /
`docs/` 均未入仓库，源码仅供参考，不保证 fork 后可直接构建。
