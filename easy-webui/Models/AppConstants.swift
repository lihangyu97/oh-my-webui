import Foundation

/// 窗口标识（Window scene 的 id / openWindow 参数），集中管理防字面量手误
enum WindowID {
    static let settings = "settings"
    static let webview = "webview"
}

/// @AppStorage / UserDefaults key，集中管理
enum AppStorageKey {
    static let preferredBrowserPath = "preferredBrowserPath"
    static let webWindowStyle = "webWindowStyle"
}

/// App 元信息（bundle id 兜底等）
enum AppBundle {
    static let fallbackID = "lhy.easy-webui"
}
