import SwiftUI
import AppKit
import UserNotifications
import ScreenCaptureKit

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var screenRecordingGranted = false
    @State private var notificationGranted = false

    enum Step: Int, CaseIterable {
        case welcome, screenRecording, notifications, provider, done
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 640, height: 480)
        .task { await checkPermissions() }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(Step.allCases, id: \.self) { s in
                Rectangle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.gray.opacity(0.2))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 24).padding(.top, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:      welcomePage
        case .screenRecording: screenRecordingPage
        case .notifications: notificationsPage
        case .provider:     providerPage
        case .done:         donePage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 18) {
            Image(systemName: "target")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
            Text("欢迎使用 Focus")
                .font(.system(size: 32, weight: .bold))
            Text("用一句承诺约束自己，AI 看屏判断你是否真在做。\n本地 / 任意 OpenAI 兼容 AI 都能接入。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 24)
    }

    private var screenRecordingPage: some View {
        permissionPage(
            icon: "rectangle.dashed.badge.record",
            title: "屏幕录制权限",
            description: "Focus 需要定时截屏给 AI 分析，判断你是否在做承诺的事。截图本地保存，仅按你选择的 Provider 发出。",
            granted: screenRecordingGranted,
            actionTitle: "打开系统设置",
            action: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            },
            recheck: {
                // ScreenCaptureKit 没有直接权限查询 API；尝试一次截屏检测
                let granted = await checkScreenRecording()
                await MainActor.run { screenRecordingGranted = granted }
            }
        )
    }

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var notificationsPage: some View {
        permissionPage(
            icon: "bell.badge",
            title: "通知权限",
            description: notificationStatus == .denied
                ? "之前选过「不允许」。系统不会再弹原生授权框，请到系统设置 → 通知 → Focus 手动开启。"
                : "走神时 Focus 会用通知 + 提示音把你拉回。首次会弹原生授权框。",
            granted: notificationGranted,
            actionTitle: notificationStatus == .denied ? "打开系统设置" : "请求授权",
            action: {
                if notificationStatus == .denied {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                } else {
                    Task {
                        let center = UNUserNotificationCenter.current()
                        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                        await refreshNotificationStatus()
                    }
                }
            },
            recheck: { await refreshNotificationStatus() }
        )
    }

    private var providerPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "brain")
                    .font(.system(size: 28))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("配置 AI Provider")
                        .font(.headline)
                    Text("可在这里直接增 / 删 / 改 / 测试。视觉模型才能分析截图。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProvidersTab(store: ProviderStore.shared)
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var donePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            Text("准备就绪")
                .font(.title.weight(.bold))
            Text("按 ⇧⌘⌥Space 或点主窗口大按钮起一次 Promise。\n可以从一个简单的承诺开始，比如『写一份周报』。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    private func permissionPage(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void,
        recheck: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(granted ? .green : .blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    if granted {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        Text("未授权")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            }
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(actionTitle) { action() }
                    .buttonStyle(.borderedProminent)
                Button("重新检查") { Task { await recheck() } }
            }
        }
        .padding(.horizontal, 30).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("上一步") {
                    if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
                }
            }
            Spacer()
            if step == .done {
                Button("开始使用") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("下一步") {
                    if let next = Step(rawValue: step.rawValue + 1) { step = next }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    // MARK: - Permission checks

    private func checkPermissions() async {
        await refreshNotificationStatus()
        screenRecordingGranted = await checkScreenRecording()
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationStatus = settings.authorizationStatus
            notificationGranted = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
    }

    private func checkScreenRecording() async -> Bool {
        // 用 SCShareableContent 探测：如果没权限会抛错或返回空 windows
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // 没权限时 windows 数量会异常少（仅自家进程）
            return !content.windows.isEmpty
        } catch {
            return false
        }
    }
}
