import CryptoKit
import Foundation

/// 飞书自定义机器人 Webhook。发送 interactive 卡片。
enum FeishuWebhook {
    struct Config: Sendable {
        var webhookURL: String
        var secret: String
    }

    struct Summary: Sendable {
        var categoryName: String
        var minutes: Int
        var todayCount: Int
        var todayMinutes: Int
        var dailyTargetMinutes: Int
        var completedAt: Date
        var isTest: Bool = false
    }

    enum SendError: LocalizedError {
        case invalidURL
        case http(Int, String)
        case api(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Webhook 地址无效"
            case .http(let code, let body):
                return "HTTP \(code)：\(body.prefix(160))"
            case .api(let message):
                return message
            case .invalidResponse:
                return "服务器返回了无法识别的响应"
            }
        }
    }

    static func send(config: Config, summary: Summary) async throws {
        let urlString = config.webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw SendError.invalidURL
        }

        var payload: [String: Any] = [
            "msg_type": "interactive",
            "card": card(for: summary)
        ]

        let secret = config.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty {
            let timestamp = String(Int(Date().timeIntervalSince1970))
            payload["timestamp"] = timestamp
            payload["sign"] = signature(timestamp: timestamp, secret: secret)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SendError.http(http.statusCode, body)
        }

        // 飞书机器人成功时返回 StatusCode/code = 0；测试或代理地址没有这些字段时按 HTTP 状态判断。
        if let result = try? JSONDecoder().decode(FeishuResponse.self, from: data) {
            if let code = result.code, code != 0 {
                throw SendError.api(result.msg ?? "飞书返回错误码 \(code)")
            }
            if let status = result.StatusCode, status != 0 {
                throw SendError.api(result.StatusMessage ?? "飞书返回错误码 \(status)")
            }
        }
    }

    private static func card(for summary: Summary) -> [String: Any] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"

        let target = max(0, summary.dailyTargetMinutes)
        let progress: String
        if target > 0 {
            let percent = Int((Double(summary.todayMinutes) / Double(target) * 100).rounded())
            progress = "\(summary.todayCount) 个 · \(summary.todayMinutes) / \(target) 分钟（\(percent)%）"
        } else {
            progress = "\(summary.todayCount) 个 · \(summary.todayMinutes) 分钟"
        }

        let title = summary.isTest ? "🧪 飞书通知测试" : "🍅 专注完成"
        let content = """
        **分类**：\(summary.categoryName)
        **本次专注**：\(summary.minutes) 分钟
        **今日进度**：\(progress)
        """

        return [
            "config": ["wide_screen_mode": true],
            "header": [
                "template": "red",
                "title": ["tag": "plain_text", "content": title]
            ],
            "elements": [
                ["tag": "div", "text": ["tag": "lark_md", "content": content]],
                ["tag": "hr"],
                ["tag": "note", "elements": [["tag": "plain_text", "content": "完成于 \(formatter.string(from: summary.completedAt)) · 番茄钟"]]]
            ]
        ]
    }

    private static func signature(timestamp: String, secret: String) -> String {
        let stringToSign = "\(timestamp)\n\(secret)"
        let key = SymmetricKey(data: Data(stringToSign.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(), using: key)
        return Data(code).base64EncodedString()
    }

    private struct FeishuResponse: Decodable {
        let code: Int?
        let msg: String?
        let StatusCode: Int?
        let StatusMessage: String?
    }
}
