import AppKit
import CryptoKit
import Foundation
import Observation
import UserNotifications

/// 从 GitHub Releases 检查、下载并安装新版本。
///
/// 检查是自动的（启动后一次，之后每 6 小时一次）；下载和安装需要用户点一下，
/// 因为安装完成后必须重启 App，会中断正在进行的专注。
@MainActor
@Observable
final class UpdateService {
    /// 发布 Release 的仓库。
    static let repository = "Phil-Fan/tomato-timer"

    struct Release: Equatable, Identifiable, Sendable {
        var id: String { version }
        /// 去掉 `v` 前缀的版本号，例如 `1.2.0`。
        let version: String
        /// Release 的 tag，例如 `v1.2.0`。
        let tagName: String
        let name: String
        let notes: String
        let pageURL: URL
        let zipURL: URL
        let zipName: String
        let checksumURL: URL?
        let publishedAt: String?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Release)
        case ready(Release)
        case installing(Release)
        case failed(String)
    }

    enum UpdateError: LocalizedError {
        case invalidResponse(String)
        case http(Int)
        case missingAsset
        case downloadFailed
        case checksumMismatch
        case invalidBundle(String)
        case verificationFailed(String)
        case toolFailed(String)
        case developmentBuild
        case translocated
        case notWritable
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let detail):
                return "GitHub 返回了无法识别的数据：\(detail)"
            case .http(let code):
                return "检查更新失败（HTTP \(code)），请稍后再试。"
            case .missingAsset:
                return "这个 Release 里没有可以自动安装的 zip 包。"
            case .downloadFailed:
                return "下载更新失败，请检查网络后重试。"
            case .checksumMismatch:
                return "下载的文件校验失败，已停止安装。"
            case .invalidBundle(let detail):
                return "下载的 App 无法使用：\(detail)"
            case .verificationFailed(let detail):
                return "更新包签名校验失败：\(detail)"
            case .toolFailed(let detail):
                return "处理更新包失败：\(detail)"
            case .developmentBuild:
                return "当前是开发构建，不能自动安装更新。请手动下载新版本。"
            case .translocated:
                return "App 正从下载目录的临时位置运行，请先把它拖进「应用程序」再更新。"
            case .notWritable:
                return "当前 App 所在位置不可写入。请先把「番茄钟」拖进「应用程序」再更新。"
            case .installFailed(let detail):
                return "启动安装脚本失败：\(detail)"
            }
        }
    }

    /// 自动检查间隔。
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    /// 失败后的重试间隔。
    private static let retryInterval: TimeInterval = 15 * 60

    let settings: AppSettings

    private(set) var state: State = .idle
    /// 自动检查失败时保留错误，但不打扰用户；手动检查会展示出来。
    private(set) var lastError: String?
    private(set) var lastCheck: Date?

    private var automaticTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - 派生状态

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var currentVersion: String {
        Self.currentVersion
    }

    /// 正在下载/安装中的版本，用于在界面上保持提示。
    var pendingRelease: Release? {
        switch state {
        case .available(let release),
             .downloading(let release),
             .ready(let release),
             .installing(let release):
            return release
        case .idle, .checking, .upToDate, .failed:
            return nil
        }
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .ready, .installing:
            return true
        case .idle, .upToDate, .available, .failed:
            return false
        }
    }

    // MARK: - 自动检查

    /// 启动后检查一次，之后每隔一段时间检查；断网失败会更快重试。
    func startAutomaticChecks() {
        guard automaticTask == nil else { return }

        automaticTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))

            while !Task.isCancelled {
                guard let self else { return }

                var delay = Self.retryInterval
                if self.settings.autoCheckUpdates, !self.isBusy {
                    let succeeded = await self.checkForUpdates(interactive: false)
                    delay = succeeded ? Self.checkInterval : Self.retryInterval
                }

                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    // MARK: - 检查

    /// 返回是否成功完成了检查（用于自动检查决定下次重试时间）。
    @discardableResult
    func checkForUpdates(interactive: Bool = true) async -> Bool {
        guard !isBusy else { return false }

        let previous = state
        state = .checking

        do {
            let release = try await fetchLatestRelease()
            lastCheck = Date()
            lastError = nil

            guard let remote = SemanticVersion(release.tagName),
                  let local = SemanticVersion(Self.currentVersion),
                  remote > local else {
                state = .upToDate
                return true
            }

            // 用户主动点「检查更新」时忽略跳过设置，避免看起来像没反应。
            if !interactive, settings.skippedUpdateVersion == release.version {
                state = .upToDate
                return true
            }

            state = .available(release)
            if !interactive {
                notify(release)
            }
            return true
        } catch {
            let message = error.localizedDescription
            lastError = message
            state = interactive ? .failed(message) : previous
            return false
        }
    }

    /// 跳过当前发现的版本，直到下一个版本发布。
    func skipPendingUpdate() {
        guard let release = pendingRelease else { return }
        settings.skippedUpdateVersion = release.version
        state = .upToDate
    }

    // MARK: - 下载与安装

    func downloadAndInstall() async {
        guard case .available(let release) = state else { return }

        state = .downloading(release)
        lastError = nil

        do {
            let newApp = try await prepare(release)
            state = .ready(release)
            try install(release, newApp: newApp)
            state = .installing(release)
            // 给安装脚本一点时间启动，然后退出让脚本替换 App。
            try? await Task.sleep(for: .milliseconds(400))
            NSApp.terminate(nil)
        } catch {
            let message = error.localizedDescription
            lastError = message
            state = .failed(message)
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else {
            throw UpdateError.invalidResponse("地址无效")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TomatoTimer/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse("不是 HTTP 响应")
        }
        switch http.statusCode {
        case 200:
            break
        case 404:
            throw UpdateError.invalidResponse("仓库还没有发布 Release")
        default:
            throw UpdateError.http(http.statusCode)
        }

        let api: APIRelease
        do {
            api = try JSONDecoder().decode(APIRelease.self, from: data)
        } catch {
            throw UpdateError.invalidResponse("Release 数据解析失败")
        }

        guard let version = SemanticVersion(api.tagName) else {
            throw UpdateError.invalidResponse("版本号 \(api.tagName) 无法识别")
        }
        guard let zip = api.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
            throw UpdateError.missingAsset
        }

        let checksum = api.assets.first {
            $0.name.lowercased() == "sha256sums.txt"
        }

        return Release(
            version: version.description,
            tagName: api.tagName,
            name: api.name ?? api.tagName,
            notes: api.body ?? "",
            pageURL: api.htmlURL,
            zipURL: zip.browserDownloadURL,
            zipName: zip.name,
            checksumURL: checksum?.browserDownloadURL,
            publishedAt: api.publishedAt
        )
    }

    /// 下载并解压，返回解压出来的新 App。
    private func prepare(_ release: Release) async throws -> URL {
        if let existing = cachedApp(for: release) {
            return existing
        }

        let fm = FileManager.default
        let directory = Self.updateDirectory(for: release.version)
        try? fm.removeItem(at: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let zipURL = directory.appendingPathComponent(release.zipName)

        let (temporary, response) = try await URLSession.shared.download(from: release.zipURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }
        try fm.moveItem(at: temporary, to: zipURL)

        if let checksumURL = release.checksumURL {
            try await verifyChecksum(zipURL: zipURL, expectedName: release.zipName, checksumURL: checksumURL)
        }

        let payload = directory.appendingPathComponent("payload", isDirectory: true)
        try await Task.detached(priority: .userInitiated) {
            try Self.unzip(zipURL, to: payload)
        }.value

        guard let appURL = Self.firstApp(in: payload) else {
            throw UpdateError.invalidBundle("压缩包里没有 .app")
        }
        try Self.verify(appURL, matches: release)

        return appURL
    }

    private func cachedApp(for release: Release) -> URL? {
        let payload = Self.updateDirectory(for: release.version)
            .appendingPathComponent("payload", isDirectory: true)
        guard let appURL = Self.firstApp(in: payload) else { return nil }
        do {
            try Self.verify(appURL, matches: release)
            return appURL
        } catch {
            return nil
        }
    }

    private func verifyChecksum(zipURL: URL, expectedName: String, checksumURL: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: checksumURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }

        let text = String(decoding: data, as: UTF8.self)
        var expected: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, let digest = parts.first else { continue }
            var name = parts.dropFirst().joined(separator: " ")
            if name.hasPrefix("*") { name.removeFirst() }
            if name == expectedName {
                expected = String(digest)
                break
            }
        }

        guard let expected else {
            throw UpdateError.invalidBundle("校验文件里没有 \(expectedName)")
        }

        let actual = try await Task.detached(priority: .userInitiated) {
            try Self.sha256(of: zipURL)
        }.value

        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw UpdateError.checksumMismatch
        }
    }

    /// 启动一个等待 App 退出后替换文件的脚本。脚本自身在 App 退出后继续运行。
    private func install(_ release: Release, newApp: URL) throws {
        let fm = FileManager.default
        let currentApp = Bundle.main.bundleURL

        guard currentApp.pathExtension == "app" else {
            throw UpdateError.notWritable
        }
        guard !currentApp.path.contains("/AppTranslocation/") else {
            throw UpdateError.translocated
        }
        guard !currentApp.path.contains("/.build/"),
              !currentApp.path.contains("/DerivedData/") else {
            throw UpdateError.developmentBuild
        }

        let parent = currentApp.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable
        }

        let directory = Self.updateDirectory(for: release.version)
        let scriptURL = directory.appendingPathComponent("install.sh")
        let logURL = directory.appendingPathComponent("install.log")

        let script = """
        #!/bin/bash
        set -u
        PID="$1"
        APP="$2"
        NEW="$3"
        LOG="$4"
        exec >>"${LOG}" 2>&1
        echo "[$(date)] 安装更新：${NEW} -> ${APP}（进程 ${PID}）"

        # 等待 App 退出，最多三分钟。
        for _ in $(seq 1 900); do
          if ! kill -0 "${PID}" 2>/dev/null; then break; fi
          sleep 0.2
        done
        sleep 1

        BACKUP="${APP}.old-$$"
        if ! mv "${APP}" "${BACKUP}"; then
          echo "无法移动旧版本，放弃安装"
          exit 1
        fi

        if /usr/bin/ditto "${NEW}" "${APP}"; then
          rm -rf "${BACKUP}"
          /usr/bin/xattr -dr com.apple.quarantine "${APP}" 2>/dev/null || true
          echo "安装完成，重新启动"
          /usr/bin/open "${APP}"
        else
          rm -rf "${APP}"
          mv "${BACKUP}" "${APP}"
          echo "复制新版本失败，已恢复旧版本"
          exit 1
        fi
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            currentApp.path,
            newApp.path,
            logURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }

    // MARK: - 通知

    private func notify(_ release: Release) {
        guard settings.notificationsEnabled else { return }
        guard settings.lastNotifiedUpdateVersion != release.version else { return }

        let content = UNMutableNotificationContent()
        content.title = "番茄钟有新版本"
        content.body = "v\(release.version) 已发布，点开菜单栏图标即可更新。"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "update-\(release.version)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard error == nil else { return }
            Task { @MainActor [weak self] in
                self?.settings.lastNotifiedUpdateVersion = release.version
            }
        }
    }

    // MARK: - 文件工具

    private static var updateRoot: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.philfan.tomato"
        return caches.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    private static func updateDirectory(for version: String) -> URL {
        updateRoot.appendingPathComponent(version, isDirectory: true)
    }

    private nonisolated static func unzip(_ zip: URL, to destination: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try runTool("/usr/bin/ditto", ["-x", "-k", zip.path, destination.path])
    }

    private nonisolated static func firstApp(in directory: URL) -> URL? {
        let fm = FileManager.default
        if let direct = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.pathExtension == "app" {
            return url
        }
        return nil
    }

    private nonisolated static func verify(_ appURL: URL, matches release: Release) throws {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw UpdateError.invalidBundle("读不到 Info.plist")
        }

        if let identifier = plist["CFBundleIdentifier"] as? String,
           let expected = Bundle.main.bundleIdentifier,
           identifier != expected {
            throw UpdateError.invalidBundle("Bundle ID 不匹配")
        }

        guard let version = plist["CFBundleShortVersionString"] as? String,
              let downloaded = SemanticVersion(version),
              let expected = SemanticVersion(release.version),
              downloaded == expected else {
            throw UpdateError.invalidBundle("版本号不一致")
        }

        do {
            try runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        } catch {
            throw UpdateError.verificationFailed(error.localizedDescription)
        }

        // 已经用 Developer ID 签名的版本，只接受同一个团队签出的更新，
        // 避免有人往仓库里塞一个自己签名的包。ad-hoc 构建没有团队信息，跳过。
        if let currentTeam = teamIdentifier(of: Bundle.main.bundleURL),
           teamIdentifier(of: appURL) != currentTeam {
            throw UpdateError.verificationFailed("新版本与当前 App 的签名团队不一致")
        }
    }

    private nonisolated static func teamIdentifier(of appURL: URL) -> String? {
        guard let output = try? runToolOutput("/usr/bin/codesign", ["-d", "--verbose=4", appURL.path]) else {
            return nil
        }
        let prefix = "TeamIdentifier="
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix(prefix) {
            let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty || value == "not set" ? nil : value
        }
        return nil
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 同步运行工具，失败时把 stderr 带出来。
    private nonisolated static func runTool(_ executable: String, _ arguments: [String]) throws {
        let result = try runToolResult(executable, arguments)
        guard result.status == 0 else {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.toolFailed(message.isEmpty ? "\(executable) 执行失败" : message)
        }
    }

    private nonisolated static func runToolOutput(_ executable: String, _ arguments: [String]) throws -> String {
        try runToolResult(executable, arguments).output
    }

    private nonisolated static func runToolResult(
        _ executable: String,
        _ arguments: [String]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - GitHub API

    private struct APIRelease: Decodable, Sendable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let publishedAt: String?
        let assets: [APIAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case assets
        }
    }

    private struct APIAsset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

/// 用于比较 `1.2.3`、`v1.2` 这类版本号。
struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        // 预发布后缀（-beta.1）不参与比较；GitHub 的 latest 接口也不会返回预发布版本。
        if let dash = text.firstIndex(of: "-") {
            text = String(text[..<dash])
        }
        let parts = text.split(separator: ".")
        guard !parts.isEmpty else { return nil }

        var components: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        self.components = components
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return false }
        }
        return true
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
