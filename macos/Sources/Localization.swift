import Foundation

enum UILanguage: String, CaseIterable, Identifiable {
    case traditionalChinese = "zh-TW"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    static let preferenceKey = "interfaceLanguage"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
    var column: Int { Self.allCases.firstIndex(of: self)! }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .traditionalChinese
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
}

// App UI only: never translate user input, generated prompts or model-provided notes.
enum L10n {
    enum Key: CaseIterable {
        case pasteRequested
        case pasteRequestedRestored
        case pasteRequestedNewCopy
        case pasteRequestedRestoreFailed
        case unsafeTargetCopied
        case pastePermissionCopied
        case clipboardUnavailable
        case providerInvalid
        case providerEmpty
        case providerTooLong
        case providerIncompleteText
        case providerUnsafeJSON
        case providerNoResult
        case providerTimeout
        case providerNetwork
        case serviceFailure
        case workspaceTitle
        case workspaceIntro
        case settings
        case memoryOnly
        case original
        case purpose
        case general
        case writing
        case analysis
        case coding
        case summary
        case marketing
        case targetPlaceholder
        case readClipboard
        case clear
        case generating
        case generate
        case privacy
        case copyablePrompt
        case copy
        case mockResult
        case generatedBy
        case modelService
        case resultPlaceholder
        case improvements
        case assumptions
        case cancel
        case originalChanged
        case purposeChanged
        case targetChanged
        case settingsTitle
        case interfaceLanguage
        case languageHelp
        case modelSettingsHelp
        case usingDemo
        case configFile
        case chooseEnv
        case editModelConfig
        case reloadConfig
        case useDemo
        case globalShortcut
        case permissionGranted
        case permissionMissing
        case permissionHelp
        case openAccessibility
        case recheckPermission
        case selectionHeading
        case showFloatingButton
        case showRightClickMenu
        case explicitActionHelp
        case autoPaste
        case selectionHelp
        case runtime
        case chooseNode
        case localPrivacy
        case done
        case chooseConfigTitle
        case chooseNodeTitle
        case missingTemplate
        case connecting
        case mockMode
        case incompleteConfig
        case liveMode
        case configuredModel
        case emptyClipboard
        case refining
        case mockNotice
        case mockPanelNotice
        case promptReady
        case promptComplete
        case cannotConnect
        case autoPasteOffCopied
        case copyFailedPanel
        case manualPasteHelp
        case unknownTarget
        case changedTarget
        case unsafePasteCopied
        case unsafePasteCopyFailed
        case changedTargetCopied
        case unsafePasteFailed
        case copied
        case copyFailed
        case copiedClipboard
        case cancelled
        case copiedPromptOnly
        case copyFailedWorkspace
        case configLoaded
        case shortcutOccupied
        case permissionNeeded
        case openWorkspace
        case readSelection
        case generateClipboard
        case settingsMenu
        case quit
        case services
        case quitApp
        case edit
        case undo
        case cut
        case paste
        case selectAll
        case selectFirst
        case permissionActive
        case emptyInput
        case inputTooLong
        case invalidTarget
        case incompatibleService
        case backendVersionMismatch
        case backendInstanceMismatch
        case badServiceResponse
        case invalidResult
        case unknownBackend
        case backendStartFailed
        case backendStartTimeout
        case unmanagedBackend
        case invalidBackendLink
        case incompleteBundle
        case seedMismatch
        case missingBackendID
        case invalidBackendID
        case invalidBackendFile
        case backendHashMismatch
        case missingNode
        case missingEnv
        case invalidNode
        case selectionPermission
        case noSelection
        case selectionExpired
        case accessibilityWarming
        case accessibilityEnabled
        case actionMenu
        case convert
        case convertTooltip
        case englishPrompt
        case pasteBack
        case converting
        case close
        case networkError
        case requestTimeout
        case providerAuth
        case providerQuota
        case providerSettings
        case providerUnavailable
        case providerJSON
        case providerSetup
        case providerTruncated
        case serviceBusy
    }

    static var language: UILanguage { UILanguage.load() }
    static let translations: [Key: [String]] = [
        .pasteRequested: ["已送出貼上操作，請確認來源文字；正在還原剪貼簿。", "Paste requested. Check the source text. Restoring the clipboard…", "貼り付け操作を送信しました。元のテキストを確認してください。クリップボードを復元中です。", "붙여넣기를 요청했습니다. 원래 텍스트를 확인하세요. 클립보드를 복원하는 중입니다."],
        .pasteRequestedRestored: ["已送出貼上操作；原剪貼簿已還原。請確認來源文字。", "Paste requested; the original clipboard was restored. Check the source text.", "貼り付け操作を送信し、元のクリップボードを復元しました。元のテキストを確認してください。", "붙여넣기를 요청하고 원래 클립보드를 복원했습니다. 원래 텍스트를 확인하세요."],
        .pasteRequestedNewCopy: ["已送出貼上操作，並保留你較新的剪貼簿內容。請確認來源文字。", "Paste requested. Your newer clipboard content was kept. Check the source text.", "貼り付け操作を送信しました。新しくコピーした内容は保持しています。元のテキストを確認してください。", "붙여넣기를 요청했습니다. 새로 복사한 클립보드 내용은 유지했습니다. 원래 텍스트를 확인하세요."],
        .pasteRequestedRestoreFailed: ["已送出貼上操作，但剪貼簿還原失敗。請確認來源文字與剪貼簿。", "Paste requested, but clipboard restoration failed. Check the source text and clipboard.", "貼り付け操作を送信しましたが、クリップボードの復元に失敗しました。元のテキストとクリップボードを確認してください。", "붙여넣기를 요청했지만 클립보드 복원에 실패했습니다. 원래 텍스트와 클립보드를 확인하세요."],
        .unsafeTargetCopied: ["無法安全確認貼回位置，已複製 Prompt，請手動 ⌘V。", "Cannot safely verify the paste target. The prompt was copied; paste manually with ⌘V.", "貼り付け先を安全に確認できません。プロンプトをコピーしました。⌘V で手動貼り付けしてください。", "붙여넣을 위치를 안전하게 확인할 수 없습니다. 프롬프트를 복사했으니 ⌘V로 직접 붙여넣으세요."],
        .pastePermissionCopied: ["缺少輔助使用權限，已複製 Prompt，請手動 ⌘V。", "Accessibility permission is missing. The prompt was copied; paste manually with ⌘V.", "アクセシビリティ権限がありません。プロンプトをコピーしました。⌘V で手動貼り付けしてください。", "손쉬운 사용 권한이 없습니다. 프롬프트를 복사했으니 ⌘V로 직접 붙여넣으세요."],
        .clipboardUnavailable: ["無法安全準備剪貼簿，已停止貼回。請檢查剪貼簿，並自行複製結果。", "Cannot safely prepare the clipboard. Paste-back stopped. Check the clipboard and copy the result manually.", "クリップボードを安全に準備できないため、貼り付けを停止しました。クリップボードを確認し、結果を手動でコピーしてください。", "클립보드를 안전하게 준비할 수 없어 붙여넣기를 중단했습니다. 클립보드를 확인하고 결과를 직접 복사하세요."],
        .providerInvalid: ["模型回傳的內容不完整或格式不符；沒有使用部分結果。請重新優化。", "The model returned incomplete or invalid content; no partial result was used. Try refining again.", "モデルの応答が不完全または形式不正です。部分的な結果は使いませんでした。再度改善を実行してください。", "모델 응답이 불완전하거나 형식이 올바르지 않습니다. 부분 결과는 사용하지 않았습니다. 다시 최적화하세요."],
        .providerEmpty: ["模型服務沒有回傳內容，請稍後再試。", "The model service returned no content. Try again later.", "モデルサービスから内容が返されませんでした。後で再試行してください。", "모델 서비스에서 내용을 반환하지 않았습니다. 나중에 다시 시도하세요."],
        .providerTooLong: ["模型回應過長，請縮短輸入後再試。", "The model response is too long. Shorten the input and retry.", "モデルの応答が長すぎます。入力を短くして再試行してください。", "모델 응답이 너무 깁니다. 입력을 줄인 후 다시 시도하세요."],
        .providerIncompleteText: ["模型沒有回傳完整文字結果；沒有使用部分結果。請重新優化。", "The model did not return a complete text result; no partial result was used. Try refining again.", "モデルが完全なテキストを返しませんでした。部分的な結果は使いませんでした。再度改善を実行してください。", "모델이 완전한 텍스트 결과를 반환하지 않았습니다. 부분 결과는 사용하지 않았습니다. 다시 최적화하세요."],
        .providerUnsafeJSON: ["模型回傳的 JSON 無法安全解析；沒有使用部分結果。請重新優化。", "The model JSON could not be safely parsed; no partial result was used. Try refining again.", "モデルの JSON を安全に解析できませんでした。部分的な結果は使いませんでした。再度改善を実行してください。", "모델 JSON을 안전하게 해석할 수 없습니다. 부분 결과는 사용하지 않았습니다. 다시 최적화하세요."],
        .providerNoResult: ["模型沒有回傳可用結果。請重新優化。", "The model returned no usable result. Try refining again.", "モデルが使用可能な結果を返しませんでした。再度改善を実行してください。", "모델이 사용할 수 있는 결과를 반환하지 않았습니다. 다시 최적화하세요."],
        .providerTimeout: ["模型回應逾時，請稍後再試或縮短 Prompt。", "The model response timed out. Try later or shorten the prompt.", "モデルの応答がタイムアウトしました。後で再試行するか、プロンプトを短くしてください。", "모델 응답 시간이 초과되었습니다. 나중에 다시 시도하거나 프롬프트를 줄이세요."],
        .providerNetwork: ["無法連線到模型服務，請檢查伺服器網路與 LLM_BASE_URL。", "Cannot connect to the model service. Check the server network and LLM_BASE_URL.", "モデルサービスに接続できません。サーバーのネットワークと LLM_BASE_URL を確認してください。", "모델 서비스에 연결할 수 없습니다. 서버 네트워크와 LLM_BASE_URL을 확인하세요."],
        .serviceFailure: ["服務暫時無法完成請求，請稍後再試。", "The service cannot complete the request right now. Try again later.", "サービスが現在リクエストを完了できません。後で再試行してください。", "서비스가 지금 요청을 완료할 수 없습니다. 나중에 다시 시도하세요."],
        .workspaceTitle: ["多語言原文 → 英文 Prompt", "Multilingual input → English prompt", "多言語の入力 → 英語のプロンプト", "다국어 입력 → 영어 프롬프트"],
        .workspaceIntro: ["可選取或貼上任何語言的文字。生成指令一律使用英文；原文指定的答案語言會保留，已是英文的指令會直接整理。", "Select or paste text in any language. Prompts are written in English; the requested answer language is preserved. English input is refined directly.", "どの言語のテキストでも選択・貼り付けできます。プロンプトは英語で作成し、指定された回答言語は保持します。英語の入力はそのまま改善します。", "어떤 언어의 텍스트든 선택하거나 붙여넣으세요. 프롬프트는 영어로 작성하며, 지정한 답변 언어는 유지합니다. 영어 입력은 바로 다듬습니다."],
        .settings: ["設定", "Settings", "設定", "설정"],
        .memoryOnly: ["內容僅在記憶體中保留", "Content stays in memory only", "内容はメモリ内にのみ保持します", "내용은 메모리에만 보관됩니다"],
        .original: ["原始需求", "Original request", "元の依頼", "원본 요청"],
        .purpose: ["用途", "Purpose", "用途", "용도"],
        .general: ["通用", "General", "汎用", "일반"],
        .writing: ["寫作", "Writing", "文章作成", "글쓰기"],
        .analysis: ["分析", "Analysis", "分析", "분석"],
        .coding: ["程式開發", "Coding", "コード開発", "코딩"],
        .summary: ["摘要", "Summarization", "要約", "요약"],
        .marketing: ["行銷", "Marketing", "マーケティング", "마케팅"],
        .targetPlaceholder: ["目標模型（選填，例如 Claude）", "Target model (optional, e.g. Claude)", "対象モデル（任意、例：Claude）", "대상 모델(선택 사항, 예: Claude)"],
        .readClipboard: ["讀取剪貼簿", "Read clipboard", "クリップボードを読み込む", "클립보드 읽기"],
        .clear: ["清除", "Clear", "クリア", "지우기"],
        .generating: ["生成中…", "Generating…", "生成中…", "생성 중…"],
        .generate: ["生成英文 Prompt", "Generate English prompt", "英語のプロンプトを生成", "영어 프롬프트 생성"],
        .privacy: ["執行生成或轉換後才會傳至你設定的模型服務；不保存需求或結果。", "Text is sent to your configured model service only when you generate or convert. Requests and results are not saved.", "生成・変換を実行したときだけ、設定したモデルサービスにテキストを送信します。依頼や結果は保存しません。", "생성 또는 변환을 실행할 때만 설정한 모델 서비스로 텍스트를 보냅니다. 요청과 결과는 저장하지 않습니다."],
        .copyablePrompt: ["可複製的 Prompt", "Prompt ready to copy", "コピーできるプロンプト", "복사할 프롬프트"],
        .copy: ["複製", "Copy", "コピー", "복사"],
        .mockResult: ["示範結果 · 未經語意優化", "Demo result · Not semantically refined", "デモ結果 · 意味の改善は未実施", "데모 결과 · 의미 최적화 없음"],
        .generatedBy: ["生成來源：%@", "Generated by: %@", "生成元：%@", "생성 모델: %@"],
        .modelService: ["模型服務", "Model service", "モデルサービス", "모델 서비스"],
        .resultPlaceholder: ["英文 Prompt 會顯示在這裡。\n\n只會整理指令，不會代你執行原始任務。", "Your English prompt will appear here.\n\nThis refines instructions; it does not perform the original task.", "英語のプロンプトがここに表示されます。\n\n指示を改善するツールです。元のタスクは実行しません。", "영어 프롬프트가 여기에 표시됩니다.\n\n지시문을 다듬을 뿐, 원래 작업을 수행하지는 않습니다."],
        .improvements: ["優化重點與假設", "Improvements and assumptions", "改善点と仮定", "개선 사항 및 가정"],
        .assumptions: ["非關鍵假設（獨立說明，不另附於 Prompt）", "Non-critical assumptions (separate from the prompt)", "重要度の低い仮定（プロンプトとは別に表示）", "비핵심 가정(프롬프트와 별도로 표시)"],
        .cancel: ["取消", "Cancel", "キャンセル", "취소"],
        .originalChanged: ["原始需求已變更，請重新生成；右側仍是上次結果。", "The request has changed. Generate again; the previous result is still shown.", "依頼が変更されました。再生成してください。前の結果が表示されています。", "요청이 변경되었습니다. 다시 생성하세요. 이전 결과가 표시되어 있습니다."],
        .purposeChanged: ["用途已變更，請重新生成；右側仍是上次結果。", "The purpose has changed. Generate again; the previous result is still shown.", "用途が変更されました。再生成してください。前の結果が表示されています。", "용도가 변경되었습니다. 다시 생성하세요. 이전 결과가 표시되어 있습니다."],
        .targetChanged: ["目標模型已變更，請重新生成；右側仍是上次結果。", "The target model has changed. Generate again; the previous result is still shown.", "対象モデルが変更されました。再生成してください。前の結果が表示されています。", "대상 모델이 변경되었습니다. 다시 생성하세요. 이전 결과가 표시되어 있습니다."],
        .settingsTitle: ["模型與取字設定", "Model and selection settings", "モデルとテキスト選択の設定", "모델 및 텍스트 선택 설정"],
        .interfaceLanguage: ["介面語言", "Interface language", "表示言語", "인터페이스 언어"],
        .languageHelp: ["立即套用並記住選擇；不改變生成 Prompt 或原文指定的答案語言。", "Applied immediately and remembered. This does not change the prompt language or the requested answer language.", "すぐに反映し、選択を記憶します。プロンプトの言語や指定された回答言語は変更しません。", "즉시 적용되며 선택을 기억합니다. 프롬프트 언어나 지정한 답변 언어는 바꾸지 않습니다."],
        .modelSettingsHelp: ["使用伺服器 .env 設定 DeepSeek 或其他相容模型。金鑰由 Node.js 後端讀取，不會複製進 App。", "Configure DeepSeek or another compatible model in a server .env file. The Node.js backend reads the key; it is not copied into the app.", "サーバーの .env ファイルで DeepSeek などの互換モデルを設定します。キーは Node.js バックエンドが読み取り、App にはコピーしません。", "서버 .env 파일에서 DeepSeek 또는 호환 모델을 설정하세요. 키는 Node.js 백엔드가 읽으며 앱에 복사하지 않습니다."],
        .usingDemo: ["目前使用示範模式", "Currently using demo mode", "現在はデモモードです", "현재 데모 모드 사용 중"],
        .configFile: ["設定檔：%@", "Config file: %@", "設定ファイル：%@", "설정 파일: %@"],
        .chooseEnv: ["選擇 .env…", "Choose .env…", ".env を選択…", ".env 선택…"],
        .editModelConfig: ["建立 / 編輯模型設定", "Create / edit model config", "モデル設定を作成・編集", "모델 설정 만들기 / 편집"],
        .reloadConfig: ["重新載入設定", "Reload settings", "設定を再読み込み", "설정 다시 불러오기"],
        .useDemo: ["使用示範模式", "Use demo mode", "デモモードを使用", "데모 모드 사용"],
        .globalShortcut: ["全域快捷鍵：⌥⌘P", "Global shortcut: ⌥⌘P", "グローバルショートカット：⌥⌘P", "전역 단축키: ⌥⌘P"],
        .permissionGranted: ["輔助使用權限已開啟。", "Accessibility permission is enabled.", "アクセシビリティ権限は有効です。", "손쉬운 사용 권한이 활성화되어 있습니다."],
        .permissionMissing: ["快捷鍵與浮動按鈕尚未取得輔助使用權限。", "The shortcut and floating button need Accessibility permission.", "ショートカットとフローティングボタンにはアクセシビリティ権限が必要です。", "단축키와 플로팅 버튼에는 손쉬운 사용 권한이 필요합니다."],
        .permissionHelp: ["%@ 右鍵「服務」不需要這項權限。少數軟體不提供選取文字，可改用剪貼簿。", "%@ The Services menu does not need this permission. If an app cannot expose selected text, use the clipboard.", "%@ 「サービス」メニューにはこの権限は不要です。選択テキストを取得できない App ではクリップボードを使ってください。", "%@ 서비스 메뉴에는 이 권한이 필요하지 않습니다. 앱에서 선택한 텍스트를 읽을 수 없다면 클립보드를 사용하세요."],
        .openAccessibility: ["開啟輔助使用設定", "Open Accessibility settings", "アクセシビリティ設定を開く", "손쉬운 사용 설정 열기"],
        .recheckPermission: ["重新檢查權限", "Check permission again", "権限を再確認", "권한 다시 확인"],
        .selectionHeading: ["一鍵轉換（IDE 輸入框適用）", "One-click conversion (for IDE inputs)", "ワンクリック変換（IDE 入力欄対応）", "원클릭 변환(IDE 입력란 지원)"],
        .showFloatingButton: ["選取文字後顯示浮動按鈕", "Show a floating button after selecting text", "テキスト選択後にフローティングボタンを表示", "텍스트 선택 후 플로팅 버튼 표시"],
        .showRightClickMenu: ["選取文字後按右鍵顯示操作選單", "Show an action menu when right-clicking selected text", "選択テキストの右クリック時に操作メニューを表示", "선택한 텍스트를 우클릭하면 작업 메뉴 표시"],
        .explicitActionHelp: ["只有點選「轉為英文 Prompt」才會生成；原軟體的右鍵選單仍保留。", "Generation starts only when you choose “Convert to English prompt”. The app's original context menu stays available.", "「英語のプロンプトに変換」を選んだときだけ生成します。元の App の右クリックメニューも使えます。", "“영어 프롬프트로 변환”을 선택해야 생성됩니다. 원래 앱의 우클릭 메뉴도 사용할 수 있습니다."],
        .autoPaste: ["生成後自動貼回選取位置", "Automatically paste back to the selection", "生成後に選択位置へ自動貼り付け", "생성 후 선택 위치에 자동 붙여넣기"],
        .selectionHelp: ["選取可讀取的文字後按右鍵，再點選「轉為英文 Prompt」，才會關閉原選單並生成附近的結果浮窗，依設定貼回選取處。未選取文字時，原右鍵選單保持正常。需要輔助使用權限。", "Select readable text, right-click, then choose “Convert to English prompt”. Only then does the original menu close and a nearby result panel appear, with paste-back based on your setting. Right-clicking without a selection works normally. Accessibility permission is required.", "取得可能なテキストを選択し、右クリックして「英語のプロンプトに変換」を選びます。その後、元のメニューが閉じ、近くに結果が表示されます。設定に応じて選択位置へ貼り付けます。未選択時の右クリックは通常どおりです。アクセシビリティ権限が必要です。", "읽을 수 있는 텍스트를 선택하고 우클릭한 뒤 “영어 프롬프트로 변환”을 선택하세요. 그때 원래 메뉴가 닫히고 근처에 결과 창이 나타나며, 설정에 따라 선택 위치에 붙여넣습니다. 선택하지 않은 상태의 우클릭은 평소대로 작동합니다. 손쉬운 사용 권한이 필요합니다."],
        .runtime: ["執行環境：Node.js 22 以上", "Runtime: Node.js 22 or later", "実行環境：Node.js 22 以降", "실행 환경: Node.js 22 이상"],
        .chooseNode: ["指定 Node 執行檔…", "Choose Node executable…", "Node 実行ファイルを指定…", "Node 실행 파일 선택…"],
        .localPrivacy: ["本機服務固定使用 127.0.0.1:3210；原本網頁工作台的 3000 埠仍可獨立使用。只保存介面語言、設定檔位置、操作偏好、用途和目標模型，不保存原文、結果或剪貼簿紀錄。", "The local service uses 127.0.0.1:3210; the browser workspace can still use port 3000 independently. Only language, config paths, operation preferences, purpose and target model are saved. Input, results and clipboard history are not saved.", "ローカルサービスは 127.0.0.1:3210 を使用し、ブラウザー版はポート 3000 で別に利用できます。保存するのは表示言語、設定パス、操作設定、用途、対象モデルのみです。入力・結果・クリップボード履歴は保存しません。", "로컬 서비스는 127.0.0.1:3210을 사용하며 브라우저 작업 공간은 3000 포트에서 별도로 사용할 수 있습니다. 언어, 설정 경로, 동작 설정, 용도와 대상 모델만 저장합니다. 입력, 결과와 클립보드 기록은 저장하지 않습니다."],
        .done: ["完成", "Done", "完了", "완료"],
        .chooseConfigTitle: ["選擇模型設定檔（.env）", "Choose model config (.env)", "モデル設定ファイルを選択（.env）", "모델 설정 파일 선택(.env)"],
        .chooseNodeTitle: ["選擇 Node.js 執行檔", "Choose Node.js executable", "Node.js 実行ファイルを選択", "Node.js 실행 파일 선택"],
        .missingTemplate: ["缺少設定範本，請重新建置。", "The config template is missing. Rebuild the app.", "設定テンプレートがありません。App を再ビルドしてください。", "설정 템플릿이 없습니다. 앱을 다시 빌드하세요."],
        .connecting: ["正在連接本機服務…", "Connecting to the local service…", "ローカルサービスに接続中…", "로컬 서비스에 연결 중…"],
        .mockMode: ["示範模式 · 原文未經優化", "Demo mode · Input is not refined", "デモモード · 入力は未改善", "데모 모드 · 입력 최적화 없음"],
        .incompleteConfig: ["模型設定未完成", "Model setup is incomplete", "モデル設定が未完了です", "모델 설정이 완료되지 않았습니다"],
        .liveMode: ["模型模式 · %@", "Model mode · %@", "モデルモード · %@", "모델 모드 · %@"],
        .configuredModel: ["已設定模型", "Configured model", "設定済みモデル", "설정된 모델"],
        .emptyClipboard: ["剪貼簿沒有文字，請先複製需求。", "The clipboard has no text. Copy your request first.", "クリップボードにテキストがありません。先に依頼をコピーしてください。", "클립보드에 텍스트가 없습니다. 먼저 요청을 복사하세요."],
        .refining: ["正在整理英文 Prompt…", "Refining your English prompt…", "英語のプロンプトを改善中…", "영어 프롬프트를 다듬는 중…"],
        .mockNotice: ["示範模式：只顯示固定範本，原文未經語意優化，也未貼回來源輸入框。請設定模型後再使用。", "Demo mode: a fixed template is shown. Your input is not semantically refined or pasted back. Configure a model to use real generation.", "デモモード：固定テンプレートを表示します。入力の意味は改善せず、元の入力欄にも貼り付けません。実際の生成にはモデルを設定してください。", "데모 모드: 고정 템플릿을 표시합니다. 입력의 의미를 다듬거나 원래 입력란에 붙여넣지 않습니다. 실제 생성에는 모델 설정이 필요합니다."],
        .mockPanelNotice: ["示範模式：這不是生成結果；請在設定中完成模型設定。", "Demo mode: this is not a generated result. Configure a model in Settings.", "デモモード：これは生成結果ではありません。設定でモデルを設定してください。", "데모 모드: 실제 생성 결과가 아닙니다. 설정에서 모델을 구성하세요."],
        .promptReady: ["英文 Prompt 已完成，可以複製使用。", "Your English prompt is ready to copy.", "英語のプロンプトをコピーできます。", "영어 프롬프트를 복사할 수 있습니다."],
        .promptComplete: ["英文 Prompt 已完成。", "English prompt complete.", "英語のプロンプトが完成しました。", "영어 프롬프트가 완성되었습니다."],
        .cannotConnect: ["無法連接本機後端，請在設定中重新啟動。", "Cannot connect to the local backend. Restart it in Settings.", "ローカルバックエンドに接続できません。設定から再起動してください。", "로컬 백엔드에 연결할 수 없습니다. 설정에서 다시 시작하세요."],
        .autoPasteOffCopied: ["英文 Prompt 已完成並複製；自動貼回已關閉，請自行 ⌘V。", "The English prompt is ready and copied. Auto paste-back is off; press ⌘V to paste.", "英語のプロンプトをコピーしました。自動貼り付けは無効です。⌘V で貼り付けてください。", "영어 프롬프트를 복사했습니다. 자동 붙여넣기가 꺼져 있으므로 ⌘V로 붙여넣으세요."],
        .copyFailedPanel: ["英文 Prompt 已完成，但複製失敗；請在結果窗選取文字後按 ⌘C。", "The prompt is ready, but copying failed. Select the text in the result panel and press ⌘C.", "プロンプトは完成しましたが、コピーに失敗しました。結果ウィンドウのテキストを選択して ⌘C を押してください。", "프롬프트는 완성되었지만 복사에 실패했습니다. 결과 창에서 텍스트를 선택하고 ⌘C를 누르세요."],
        .manualPasteHelp: ["已複製；自動貼回已關閉，可按「貼回原文」或自行 ⌘V。", "Copied. Auto paste-back is off; choose “Paste back” or press ⌘V.", "コピーしました。自動貼り付けは無効です。「元の位置に貼り付け」または ⌘V を使ってください。", "복사했습니다. 자동 붙여넣기가 꺼져 있습니다. “원래 위치에 붙여넣기” 또는 ⌘V를 사용하세요."],
        .unknownTarget: ["無法確認來源輸入框與選取位置", "Cannot confirm the source field and selection", "元の入力欄と選択位置を確認できません", "원래 입력란과 선택 위치를 확인할 수 없습니다"],
        .changedTarget: ["來源輸入框或選取內容已改變", "The source field or selection has changed", "元の入力欄または選択内容が変わりました", "원래 입력란 또는 선택 내용이 변경되었습니다"],
        .unsafePasteCopied: ["%@，為避免貼錯位置，Prompt 已複製，請自行 ⌘V。", "%@. To avoid pasting in the wrong place, the prompt was copied. Press ⌘V to paste.", "%@。誤った場所への貼り付けを避けるため、コピーしました。⌘V で貼り付けてください。", "%@. 잘못된 위치에 붙여넣지 않도록 프롬프트를 복사했습니다. ⌘V로 붙여넣으세요."],
        .unsafePasteCopyFailed: ["%@，且複製失敗；請在結果窗選取文字後按 ⌘C。", "%@. Copying also failed; select the result text and press ⌘C.", "%@。コピーにも失敗しました。結果のテキストを選択して ⌘C を押してください。", "%@. 복사에도 실패했습니다. 결과 텍스트를 선택하고 ⌘C를 누르세요."],
        .changedTargetCopied: ["來源輸入框或選取內容已改變；為避免貼錯位置，已複製，請自行 ⌘V。", "The source field or selection changed. The prompt was copied to avoid an unsafe paste; press ⌘V.", "元の入力欄または選択内容が変わりました。誤った貼り付けを避けるためコピーしました。⌘V を使ってください。", "원래 입력란 또는 선택 내용이 변경되었습니다. 안전하지 않은 붙여넣기를 피하려고 복사했습니다. ⌘V를 사용하세요."],
        .unsafePasteFailed: ["無法安全貼回且複製失敗；請在結果窗選取文字後按 ⌘C。", "Cannot paste back safely, and copying failed. Select the result text and press ⌘C.", "安全に貼り付けられず、コピーにも失敗しました。結果のテキストを選択して ⌘C を押してください。", "안전하게 붙여넣을 수 없고 복사에도 실패했습니다. 결과 텍스트를 선택하고 ⌘C를 누르세요."],
        .copied: ["已複製 Prompt。", "Prompt copied.", "プロンプトをコピーしました。", "프롬프트를 복사했습니다."],
        .copyFailed: ["複製失敗，請選取結果後按 ⌘C。", "Copy failed. Select the result and press ⌘C.", "コピーに失敗しました。結果を選択して ⌘C を押してください。", "복사에 실패했습니다. 결과를 선택하고 ⌘C를 누르세요."],
        .copiedClipboard: ["已複製到剪貼簿。", "Copied to clipboard.", "クリップボードにコピーしました。", "클립보드에 복사했습니다."],
        .cancelled: ["已取消生成。", "Generation cancelled.", "生成をキャンセルしました。", "생성을 취소했습니다."],
        .copiedPromptOnly: ["已複製 Prompt，未包含優化說明。", "Prompt copied without the improvement notes.", "改善点の説明を含めず、プロンプトだけをコピーしました。", "개선 설명을 제외하고 프롬프트만 복사했습니다."],
        .copyFailedWorkspace: ["複製失敗，請在結果區選取文字後按 ⌘C。", "Copy failed. Select text in the result area and press ⌘C.", "コピーに失敗しました。結果欄のテキストを選択して ⌘C を押してください。", "복사에 실패했습니다. 결과 영역에서 텍스트를 선택하고 ⌘C를 누르세요."],
        .configLoaded: ["模型設定已載入。", "Model settings loaded.", "モデル設定を読み込みました。", "모델 설정을 불러왔습니다."],
        .shortcutOccupied: ["⌥⌘P 已被其他程式佔用，請改用右鍵「服務」或剪貼簿。", "⌥⌘P is in use by another app. Use Services or the clipboard instead.", "⌥⌘P は別の App が使用しています。「サービス」またはクリップボードを使ってください。", "다른 앱에서 ⌥⌘P를 사용 중입니다. 서비스 메뉴 또는 클립보드를 사용하세요."],
        .permissionNeeded: ["浮動按鈕與 ⌥⌘P 未生效：請在「系統設定 → 輔助使用」允許 PromptFinch，授權後自動生效。", "The floating button and ⌥⌘P need permission. Allow PromptFinch in System Settings → Accessibility; they will activate automatically.", "フローティングボタンと ⌥⌘P には権限が必要です。システム設定 → アクセシビリティで PromptFinch を許可すると自動的に有効になります。", "플로팅 버튼과 ⌥⌘P에는 권한이 필요합니다. 시스템 설정 → 손쉬운 사용에서 PromptFinch를 허용하면 자동으로 활성화됩니다."],
        .openWorkspace: ["開啟 PromptFinch", "Open PromptFinch", "PromptFinch を開く", "PromptFinch 열기"],
        .readSelection: ["讀取選取文字  ⌥⌘P", "Read selected text  ⌥⌘P", "選択テキストを読み込む  ⌥⌘P", "선택한 텍스트 읽기  ⌥⌘P"],
        .generateClipboard: ["從剪貼簿生成英文 Prompt", "Generate English prompt from clipboard", "クリップボードから英語のプロンプトを生成", "클립보드에서 영어 프롬프트 생성"],
        .settingsMenu: ["設定…", "Settings…", "設定…", "설정…"],
        .quit: ["結束", "Quit", "終了", "종료"],
        .services: ["服務", "Services", "サービス", "서비스"],
        .quitApp: ["結束 PromptFinch", "Quit PromptFinch", "PromptFinch を終了", "PromptFinch 종료"],
        .edit: ["編輯", "Edit", "編集", "편집"],
        .undo: ["復原", "Undo", "取り消す", "실행 취소"],
        .cut: ["剪下", "Cut", "切り取り", "잘라내기"],
        .paste: ["貼上", "Paste", "貼り付け", "붙여넣기"],
        .selectAll: ["全選", "Select All", "すべて選択", "모두 선택"],
        .selectFirst: ["請先選取要優化的文字。", "Select text to refine first.", "先に改善するテキストを選択してください。", "먼저 다듬을 텍스트를 선택하세요."],
        .permissionActive: ["輔助使用權限已開啟，浮動按鈕與 ⌥⌘P 已生效。", "Accessibility permission is enabled. The floating button and ⌥⌘P are active.", "アクセシビリティ権限が有効になり、フローティングボタンと ⌥⌘P が使えます。", "손쉬운 사용 권한이 활성화되었습니다. 플로팅 버튼과 ⌥⌘P를 사용할 수 있습니다."],
        .emptyInput: ["請先選取文字或貼上原始需求。", "Select text or paste your original request first.", "先にテキストを選択するか、元の依頼を貼り付けてください。", "먼저 텍스트를 선택하거나 원본 요청을 붙여넣으세요."],
        .inputTooLong: ["需求最多 12,000 字，請縮短後再試。", "The request can contain up to 12,000 UTF-16 units. Shorten it and try again.", "依頼は最大 12,000 UTF-16 単位です。短くして再試行してください。", "요청은 최대 12,000 UTF-16 단위입니다. 줄인 후 다시 시도하세요."],
        .invalidTarget: ["目標模型請使用 80 字以內的單行文字。", "Use a single line of up to 80 characters for the target model.", "対象モデルは 80 文字以内の 1 行で入力してください。", "대상 모델은 80자 이내의 한 줄로 입력하세요."],
        .incompatibleService: ["3210 連接埠上的服務不相容，請先關閉佔用此埠的程式。", "The service on port 3210 is incompatible. Close the app using that port.", "ポート 3210 のサービスは互換性がありません。このポートを使用する App を終了してください。", "3210 포트의 서비스가 호환되지 않습니다. 해당 포트를 사용하는 앱을 종료하세요."],
        .backendVersionMismatch: ["本機後端版本與 App 不一致。請關閉 App，重新執行後端更新指令。", "The backend version does not match the app. Close the app and run the backend update again.", "バックエンドと App のバージョンが一致しません。App を終了し、バックエンドを再更新してください。", "백엔드와 앱 버전이 일치하지 않습니다. 앱을 닫고 백엔드를 다시 업데이트하세요."],
        .backendInstanceMismatch: ["3210 的服務不是此 App 本次啟動的後端。為避免連到舊程序，請先結束佔用該埠的服務再重試。", "The service on port 3210 was not started by this app session. Stop that service before retrying.", "ポート 3210 のサービスは今回の App が起動したものではありません。そのサービスを停止してから再試行してください。", "3210 포트의 서비스는 이번 앱 실행에서 시작한 백엔드가 아닙니다. 해당 서비스를 중지하고 다시 시도하세요."],
        .badServiceResponse: ["本機服務回應異常，請重試。", "The local service returned an unexpected response. Try again.", "ローカルサービスの応答が異常です。再試行してください。", "로컬 서비스에서 예상하지 못한 응답을 받았습니다. 다시 시도하세요."],
        .invalidResult: ["結果不是有效的英文 Prompt 回應，請重新生成。", "The response is not a valid English prompt. Generate again.", "応答が有効な英語のプロンプトではありません。再生成してください。", "유효한 영어 프롬프트 응답이 아닙니다. 다시 생성하세요."],
        .unknownBackend: ["無法確認目前後端由此 App 啟動；請重新啟動助手。", "Cannot confirm this app started the backend. Restart PromptFinch.", "この App がバックエンドを起動したか確認できません。PromptFinch を再起動してください。", "이 앱이 백엔드를 시작했는지 확인할 수 없습니다. PromptFinch를 다시 시작하세요."],
        .backendStartFailed: ["本機後端未能啟動。請確認 Node.js 22 以上、設定檔格式正確，且 3210 埠未被其他程式佔用。", "The backend could not start. Check Node.js 22 or later, the config format, and that port 3210 is free.", "バックエンドを起動できません。Node.js 22 以降、設定ファイルの形式、ポート 3210 が空いていることを確認してください。", "백엔드를 시작하지 못했습니다. Node.js 22 이상인지, 설정 형식이 올바른지, 3210 포트가 비어 있는지 확인하세요."],
        .backendStartTimeout: ["本機後端啟動逾時，請重新啟動工具。", "The backend startup timed out. Restart the app.", "バックエンドの起動がタイムアウトしました。App を再起動してください。", "백엔드 시작 시간이 초과되었습니다. 앱을 다시 시작하세요."],
        .unmanagedBackend: ["外部後端 current 路徑不是本工具管理的版本連結；為保護檔案，沒有覆蓋它。", "The backend current path is not a managed version link. It was not overwritten to protect your files.", "バックエンドの current パスは管理対象のバージョンリンクではありません。ファイル保護のため上書きしませんでした。", "백엔드 current 경로가 앱에서 관리하는 버전 링크가 아닙니다. 파일 보호를 위해 덮어쓰지 않았습니다."],
        .invalidBackendLink: ["外部後端版本連結格式不正確，未啟動未知程式碼。", "The backend version link is invalid. Unknown code was not started.", "バックエンドのバージョンリンクが無効です。不明なコードは起動しませんでした。", "백엔드 버전 링크가 올바르지 않습니다. 알 수 없는 코드는 실행하지 않았습니다."],
        .incompleteBundle: ["應用程式套件不完整，請重新安裝。", "The app bundle is incomplete. Reinstall the app.", "App バンドルが不完全です。再インストールしてください。", "앱 번들이 불완전합니다. 앱을 다시 설치하세요."],
        .seedMismatch: ["初次安裝後端版本核對失敗。", "The initial backend version check failed.", "初回インストール時のバックエンドのバージョン確認に失敗しました。", "최초 백엔드 설치 버전 확인에 실패했습니다."],
        .missingBackendID: ["後端版本標記遺失，請重新建置或更新後端。", "The backend version marker is missing. Rebuild or update the backend.", "バックエンドのバージョン識別子がありません。再ビルドまたは更新してください。", "백엔드 버전 표시가 없습니다. 다시 빌드하거나 업데이트하세요."],
        .invalidBackendID: ["後端版本標記格式不正確。", "The backend version marker is invalid.", "バックエンドのバージョン識別子が無効です。", "백엔드 버전 표시 형식이 올바르지 않습니다."],
        .invalidBackendFile: ["後端檔案不完整或包含未知連結：%@。", "A backend file is missing or contains an unknown link: %@.", "バックエンドファイルが不完全、または不明なリンクを含みます：%@。", "백엔드 파일이 불완전하거나 알 수 없는 링크를 포함합니다: %@."],
        .backendHashMismatch: ["外部後端內容與版本識別不符，請重新執行安全更新。", "The backend content does not match its version ID. Run the safe update again.", "バックエンドの内容とバージョン ID が一致しません。安全な更新を再実行してください。", "백엔드 내용이 버전 ID와 일치하지 않습니다. 안전한 업데이트를 다시 실행하세요."],
        .missingNode: ["找不到 Node.js。請安裝 Node.js 22 以上，或在設定中指定執行檔。", "Node.js was not found. Install Node.js 22 or later, or choose its executable in Settings.", "Node.js が見つかりません。22 以降をインストールするか、設定で実行ファイルを指定してください。", "Node.js를 찾을 수 없습니다. Node.js 22 이상을 설치하거나 설정에서 실행 파일을 지정하세요."],
        .missingEnv: ["找不到所選 .env 設定檔，請在設定中重新選擇。", "The selected .env file was not found. Choose it again in Settings.", "選択した .env ファイルが見つかりません。設定で再選択してください。", "선택한 .env 파일을 찾을 수 없습니다. 설정에서 다시 선택하세요."],
        .invalidNode: ["本機後端無法啟動，請確認指定的 Node.js 執行檔有效。", "The backend cannot start. Check that the selected Node.js executable is valid.", "バックエンドを起動できません。指定した Node.js 実行ファイルを確認してください。", "백엔드를 시작할 수 없습니다. 지정한 Node.js 실행 파일이 유효한지 확인하세요."],
        .selectionPermission: ["快捷鍵取字需要「輔助使用」權限。可在設定中開啟；也可使用右鍵「服務」或手動貼上。", "Reading a selection with the shortcut needs Accessibility permission. Enable it in Settings, or use Services or manual paste.", "ショートカットで選択テキストを読み込むにはアクセシビリティ権限が必要です。設定で有効にするか、「サービス」または手動貼り付けを使ってください。", "단축키로 선택한 텍스트를 읽으려면 손쉬운 사용 권한이 필요합니다. 설정에서 허용하거나 서비스 메뉴 또는 수동 붙여넣기를 사용하세요."],
        .noSelection: ["目前沒有可讀取的選取文字。此軟體若不支援取字，請複製後從選單列讀取剪貼簿。", "No readable text is selected. If the app does not support text selection access, copy it and use the clipboard menu.", "読み取れる選択テキストがありません。取得に非対応の App ではコピーして、メニューからクリップボードを読み込んでください。", "읽을 수 있는 선택 텍스트가 없습니다. 텍스트 읽기를 지원하지 않는 앱이라면 복사한 뒤 메뉴에서 클립보드를 읽으세요."],
        .selectionExpired: ["選取內容已變更或無法核對。請重新選取，再按右鍵。", "The selection changed or could not be verified. Select again and right-click.", "選択内容が変わったか、確認できませんでした。再選択して右クリックしてください。", "선택 내용이 변경되었거나 확인할 수 없습니다. 다시 선택하고 우클릭하세요."],
        .accessibilityWarming: ["文字輔助功能正在啟動。請等 2 秒，再重新選取並按右鍵。", "Text accessibility is starting. Wait 2 seconds, then select again and right-click.", "テキストのアクセシビリティ機能を起動中です。2 秒待ってから再選択し、右クリックしてください。", "텍스트 접근성 기능을 시작하는 중입니다. 2초 후 다시 선택하고 우클릭하세요."],
        .accessibilityEnabled: ["已啟用此程式的文字輔助功能。請等 2 秒，再重新選取並按右鍵。", "Text accessibility was enabled for this app. Wait 2 seconds, then select again and right-click.", "この App のテキストアクセシビリティを有効にしました。2 秒待ってから再選択し、右クリックしてください。", "이 앱의 텍스트 접근성 기능을 켰습니다. 2초 후 다시 선택하고 우클릭하세요."],
        .actionMenu: ["PromptFinch操作選單", "PromptFinch action menu", "PromptFinch 操作メニュー", "PromptFinch 작업 메뉴"],
        .convert: ["轉為英文 Prompt", "Convert to English prompt", "英語のプロンプトに変換", "영어 프롬프트로 변환"],
        .convertTooltip: ["點選後才會傳送選取文字並生成英文 Prompt", "Selected text is sent and an English prompt generated only when clicked", "クリックしたときだけ選択テキストを送信し、英語のプロンプトを生成します", "클릭할 때만 선택한 텍스트를 보내고 영어 프롬프트를 생성합니다"],
        .englishPrompt: ["英文 Prompt", "English prompt", "英語のプロンプト", "영어 프롬프트"],
        .pasteBack: ["貼回原文", "Paste back", "元の位置に貼り付け", "원래 위치에 붙여넣기"],
        .converting: ["正在轉為英文 Prompt…", "Converting to English prompt…", "英語のプロンプトに変換中…", "영어 프롬프트로 변환 중…"],
        .close: ["關閉", "Close", "閉じる", "닫기"],
        .networkError: ["無法完成網路連線，請檢查本機服務與網路後再試。", "The network request failed. Check the local service and your connection, then retry.", "通信に失敗しました。ローカルサービスとネットワークを確認し、再試行してください。", "네트워크 요청에 실패했습니다. 로컬 서비스와 연결을 확인한 뒤 다시 시도하세요."],
        .requestTimeout: ["模型請求逾時，請稍後再試或調整 LLM_TIMEOUT_MS。", "The model request timed out. Retry later or adjust LLM_TIMEOUT_MS.", "モデルへのリクエストがタイムアウトしました。後で再試行するか、LLM_TIMEOUT_MS を調整してください。", "모델 요청 시간이 초과되었습니다. 나중에 다시 시도하거나 LLM_TIMEOUT_MS를 조정하세요."],
        .providerAuth: ["模型服務拒絕授權，請檢查伺服器的 API 金鑰與模型權限。", "The model service rejected authorization. Check the server API key and model access.", "モデルサービスが認証を拒否しました。サーバーの API キーとモデル権限を確認してください。", "모델 서비스가 인증을 거부했습니다. 서버 API 키와 모델 권한을 확인하세요."],
        .providerQuota: ["模型服務暫時超過用量或頻率限制，請稍後再試並檢查帳戶額度。", "The model service reached a usage or rate limit. Retry later and check your account balance.", "モデルサービスの利用量または頻度制限に達しました。後で再試行し、アカウントの残高を確認してください。", "모델 서비스의 사용량 또는 요청 빈도 제한에 도달했습니다. 나중에 다시 시도하고 계정 잔액을 확인하세요."],
        .providerSettings: ["模型服務不接受目前設定，請檢查 LLM_BASE_URL、LLM_MODEL 與 LLM_JSON_MODE。", "The model service rejected the settings. Check LLM_BASE_URL, LLM_MODEL and LLM_JSON_MODE.", "モデルサービスが設定を受け付けません。LLM_BASE_URL、LLM_MODEL、LLM_JSON_MODE を確認してください。", "모델 서비스가 현재 설정을 거부했습니다. LLM_BASE_URL, LLM_MODEL, LLM_JSON_MODE를 확인하세요."],
        .providerUnavailable: ["模型服務暫時無法使用，請稍後再試。", "The model service is temporarily unavailable. Try again later.", "モデルサービスを一時的に利用できません。後で再試行してください。", "모델 서비스를 일시적으로 사용할 수 없습니다. 나중에 다시 시도하세요."],
        .providerJSON: ["模型服務回應不是有效 JSON，請檢查服務網址。", "The model service returned invalid JSON. Check the service URL.", "モデルサービスの応答が有効な JSON ではありません。サービス URL を確認してください。", "모델 서비스 응답이 유효한 JSON이 아닙니다. 서비스 URL을 확인하세요."],
        .providerSetup: ["模型模式尚未設定完成。請在伺服器 .env 設定 LLM_API_KEY 與 LLM_MODEL，或將 OPTIMIZER_MODE 改為 mock 後重新啟動。", "Model setup is incomplete. Set LLM_API_KEY and LLM_MODEL in the server .env, or use OPTIMIZER_MODE=mock and restart.", "モデル設定が未完了です。サーバーの .env に LLM_API_KEY と LLM_MODEL を設定するか、OPTIMIZER_MODE=mock にして再起動してください。", "모델 설정이 완료되지 않았습니다. 서버 .env에 LLM_API_KEY와 LLM_MODEL을 설정하거나 OPTIMIZER_MODE=mock으로 바꾸고 다시 시작하세요."],
        .providerTruncated: ["模型回應被截斷，沒有使用部分結果。請縮短 Prompt 或調整模型服務的輸出上限後再試。", "The model response was truncated; no partial result was used. Shorten the prompt or adjust the output limit, then retry.", "モデル応答が途中で切れたため、部分的な結果は使いませんでした。プロンプトを短くするか出力上限を調整し、再試行してください。", "모델 응답이 잘려 부분 결과는 사용하지 않았습니다. 프롬프트를 줄이거나 출력 제한을 조정한 뒤 다시 시도하세요."],
        .serviceBusy: ["目前正在處理其他優化，請稍後再試。", "Other requests are being processed. Try again shortly.", "他の依頼を処理中です。少し待って再試行してください。", "다른 요청을 처리 중입니다. 잠시 후 다시 시도하세요."],
    ]

    static func text(_ key: Key, _ arguments: CVarArg..., language: UILanguage? = nil) -> String {
        render(key, arguments: arguments, language: language ?? self.language)
    }

    private static func render(_ key: Key, arguments: [CVarArg], language: UILanguage) -> String {
        let template = translations[key]![language.column]
        return arguments.isEmpty ? template : String(format: template, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    // Retain visible status messages when switching language, including inserted filenames.
    // Only our known UI templates are matched; unrelated model or system text is left intact.
    static func relocalize(_ message: String, from source: UILanguage, to target: UILanguage = language) -> String {
        guard !message.isEmpty, source != target else { return message }
        for key in Key.allCases {
            let template = translations[key]![source.column]
            if template == message { return text(key, language: target) }
            guard template.contains("%@") else { continue }
            let pattern = "^" + NSRegularExpression.escapedPattern(for: template)
                .replacingOccurrences(of: "%@", with: "(.*?)") + "$"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) else { continue }
            let arguments: [CVarArg] = (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: message) else { return nil }
                let value = String(message[range])
                return relocalize(value, from: source, to: target)
            }
            return render(key, arguments: arguments, language: target)
        }
        return message
    }

    static func errorDescription(_ error: Error) -> String {
        if let network = error as? URLError {
            if network.code == .cannotConnectToHost { return text(.cannotConnect) }
            if network.code == .timedOut { return text(.requestTimeout) }
            if network.code != .cancelled { return text(.networkError) }
        }
        return relocalize(error.localizedDescription, from: .traditionalChinese)
    }
}
