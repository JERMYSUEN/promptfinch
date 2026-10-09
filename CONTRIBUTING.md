# 參與開發

需要 Node.js 22 以上。原生功能另需要 macOS 13 以上與 Xcode Command Line Tools（`xcode-select --install`）。

```sh
npm ci
npm run check
npm test
PLAYWRIGHT_CHANNEL=chrome npm run test:ui
# macOS
npm run test:mac
npm run build:mac
```

瀏覽器測試也可先 `npx playwright install chromium` 再 `npm run test:ui`。

請維持零執行期套件的後端與原生 Swift/AppKit/SwiftUI 架構。修改英文編輯策略時，核對數字、名稱、原本的答案語言、輸出格式、關鍵缺漏與非關鍵假設；API 假模型測試只能驗證協定，不能證明真實模型的翻譯品質。

提交 Issue 或 PR 時不要附上金鑰、`.env`、私人原文、剪貼簿或原生偏好設定。使用虛構、可公開的範例。涉及 Services 或取字時，請記錄 macOS 版本、來源軟體版本、是否有輔助使用權限、重現步驟，以及使用哪個入口。

專案包含 MIT 授權。請保留第三方套件的原有授權，勿直接加入授權不相容的程式碼。
