import AppKit

// Integration check of Apple's Services API, without reading the user's clipboard.
let app = NSApplication.shared
let board = NSPasteboard.withUniqueName()
defer { board.releaseGlobally() }
board.setString("請把這個需求整理成英文 Prompt：用繁體中文撰寫 100 字以內的活動邀請信，日期 2026-10-15，不提折扣。", forType: .string)
if NSPerformService("產生英文 Prompt", board) {
    print("macOS Services：測試文字已成功交付原生 App。非同步模型結果需另行確認。")
} else {
    fputs("Services 尚未啟用或無法交付；請檢查系統的鍵盤 → 服務設定。\n", stderr)
    exit(1)
}
