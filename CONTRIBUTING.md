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

文件翻譯以根目錄 `README.md` 的英文內容為來源，各語言文件位於 `docs/readme/README.<locale>.md`；簡體中文使用 `zh-CN`，繁體中文使用 `zh-TW`。各 README 最上方的語言列連至獨立文件頁。新增語言時請同步更新所有頁面的語言列，以及 `scripts/package-source.js` 的 `readmeLocales` 清單。翻譯中的文件連結須相對於所在目錄，指令、API 欄位、固定字串與設定範例應保留原樣；僅翻譯簡介的頁面須清楚標示，並保留完整英文技術文件入口。

請維持零執行期套件的後端與原生 Swift/AppKit/SwiftUI 架構。修改英文編輯策略時，核對數字、名稱、原本的答案語言、輸出格式、關鍵缺漏與非關鍵假設；API 假模型測試只能驗證協定，不能證明真實模型的翻譯品質。

提交 Issue 或 PR 時不要附上金鑰、`.env`、私人原文、剪貼簿或原生偏好設定。使用虛構、可公開的範例。涉及 Services 或取字時，請記錄 macOS 版本、來源軟體版本、是否有輔助使用權限、重現步驟，以及使用哪個入口。

專案包含 MIT 授權。請保留第三方套件的原有授權，勿直接加入授權不相容的程式碼。
