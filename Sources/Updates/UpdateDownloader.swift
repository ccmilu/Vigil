import Foundation
import AppKit

/// dmg 下载器：URLSession download → 落地到 Application Support → 调 NSWorkspace mount。
///
/// 状态机：idle → downloading → mounting → mounted；任意阶段失败转 failed。
@MainActor
final class UpdateDownloader: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(progress: Double)
        case mounting
        case mounted(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var session: URLSession?
    private var currentTask: URLSessionDownloadTask?

    /// 落地目录：~/Library/Containers/<bundle>/Data/Library/Application Support/Vigil/Updates/
    /// 沙盒 App 写自己的 Container 不需要额外 entitlement。
    static var updatesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Vigil/Updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func download(from url: URL) {
        // 防重入：下载 / mount 进行中时静默忽略
        switch state {
        case .downloading, .mounting: return
        case .idle, .mounted, .failed: break
        }
        // 清掉上一次失败的 session（带任务、delegate）
        session?.invalidateAndCancel()
        session = nil

        state = .downloading(progress: 0)

        let delegate = DownloadDelegate(owner: self)
        let config = URLSessionConfiguration.default
        // GitHub release asset 会 302 重定向到 objects.githubusercontent.com，
        // 国内网络冷启动经常 30s 不够 — 给到 90s。资源整体超时 10 分钟。
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 600
        // 网络瞬断时让 URLSession 等连接恢复而不是立即 fail
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = ["User-Agent": "Vigil-Updater/1.0"]
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: url)
        currentTask = task
        task.resume()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        session?.invalidateAndCancel()
        session = nil
        state = .idle
    }

    func reset() {
        cancel()
    }

    fileprivate func cleanupOldDownloads() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Self.updatesDirectory, includingPropertiesForKeys: nil) else { return }
        for item in items where item.pathExtension.lowercased() == "dmg" {
            try? fm.removeItem(at: item)
        }
    }

    // MARK: - 被 delegate 回调（nonisolated → 跳回 main）

    nonisolated fileprivate func reportProgress(_ progress: Double) {
        Task { @MainActor in
            // 只有还在下载中才更新（防覆盖已经切到 mounting / failed 的状态）
            if case .downloading = self.state {
                self.state = .downloading(progress: progress)
            }
        }
    }

    nonisolated fileprivate func reportFinished(tempURL: URL, suggestedName: String) {
        Task { @MainActor in
            self.handleFinished(tempURL: tempURL, suggestedName: suggestedName)
        }
    }

    nonisolated fileprivate func reportError(_ error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in
            self.state = .failed(msg)
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }

    private func handleFinished(tempURL: URL, suggestedName: String) {
        cleanupOldDownloads()
        let dest = Self.updatesDirectory.appendingPathComponent(suggestedName)
        do {
            // 之前 cleanup 应该删掉了，但兜底
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
        } catch {
            state = .failed(L("写入下载文件失败：%@", args: error.localizedDescription as CVarArg))
            return
        }
        state = .mounting
        // 短暂延迟，避免 Finder 刚拿到文件就被 open 抢
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            let opened = NSWorkspace.shared.open(dest)
            if opened {
                self.state = .mounted(dest)
            } else {
                self.state = .failed(L("无法自动挂载 dmg，请从 %@ 手动打开", args: dest.path as CVarArg))
            }
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }
}

/// URLSession delegate：跑在 background queue，回调通过 nonisolated 方法转回 main。
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var owner: UpdateDownloader?

    init(owner: UpdateDownloader) {
        self.owner = owner
        super.init()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        owner?.reportProgress(p)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // 拿到推荐文件名；优先用 response 的 suggestedFilename，否则从 URL 推
        let suggestedName: String = {
            if let resp = downloadTask.response,
               let suggested = resp.suggestedFilename,
               suggested.lowercased().hasSuffix(".dmg") {
                return suggested
            }
            if let last = downloadTask.originalRequest?.url?.lastPathComponent,
               last.lowercased().hasSuffix(".dmg") {
                return last
            }
            return "Vigil-update.dmg"
        }()

        // location 是系统临时文件，回调返回后即删除——必须立即 copy 到一个稳定位置
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + suggestedName)
        do {
            try FileManager.default.copyItem(at: location, to: temp)
            owner?.reportFinished(tempURL: temp, suggestedName: suggestedName)
        } catch {
            owner?.reportError(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 注意：didFinishDownloadingTo 也会触发这个，error 可能为 nil
        if let error = error {
            owner?.reportError(error)
        }
    }

    /// 显式同意跟随 GitHub release → objects.githubusercontent.com 的 302 重定向。
    /// 默认实现就是 follow，这里写出来便于将来做诊断 / 限流。
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request)
    }
}
