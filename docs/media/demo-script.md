# PromptFinch manual-workspace demo

Production status: **first edition complete**. This 72-second edited walkthrough uses actual native-app captures and an actual model result. It is not a continuous screen recording. The silent MP4 contains burned-in English captions; matching English and Traditional Chinese SRT files are supplied separately.

[MP4](promptfinch-demo.mp4) · [GIF preview](demo.gif) · [Cover image](demo-thumbnail.png) · [English subtitles](demo.en.srt) · [Traditional Chinese subtitles](demo.zh-TW.srt)

## Recorded scope

The recording covers the English manual workspace, a synthetic Chinese request, Writing as the task, Claude as the optional target-model hint, an actual `deepseek-flash` response, separate improvement notes, successful copy feedback, manual paste into a TextEdit test document, and the four native interface languages.

The companion right-click action menu and replacement inside an IDE are **not included in this film**. Automated right-click opened TextEdit's own menu but did not reliably capture PromptFinch's companion menu. No simulated menu or IDE replacement footage is substituted. This is a manual-workspace demo, not a recording of the selection-assistant workflow.

## Actual synthetic input

> 請撰寫 ACME-42 的產品更新通知，對象是既有用戶，語氣友善專業，介紹新增快速搜尋功能。不要承諾上線日期。答案請用繁體中文，限制在 180 個中文字以內，產品名稱「ACME-42」必須逐字保留。

The actual model result was checked against the input. It retains ACME-42, existing users, a friendly and professional tone, the quick-search feature, no launch-date promise, the 180-Chinese-character limit, and a Traditional Chinese answer. These are properties of the captured response, not a guarantee for every model response.

## Final 72-second sequence

| Time | Actual footage | English caption summary | 繁體中文字幕摘要 |
| --- | --- | --- | --- |
| 00:00–00:06 | Title card | PromptFinch. Select. Refine. Paste. | PromptFinch。選取、整理、貼上。 |
| 00:06–00:10 | Empty English manual workspace | A manual workspace for clearer English prompts. | 用工作台整理更清楚的英文 Prompt。 |
| 00:10–00:18 | Close-up of the original Chinese request | Start with your goal, tone, and constraints. Include the answer language and exact strings to preserve. | 輸入目的、語氣與限制，也要指定答案語言和必須保留的固定字串。 |
| 00:18–00:26 | Writing task and Claude target-model hint | Choose a task and an optional target-model hint. The hint does not switch the backend generation model. | 選擇用途與選用的目標模型提示。這個提示不會切換後端實際使用的生成模型。 |
| 00:26–00:30 | Actual completed generation in the workspace | This is an actual result from deepseek-flash. | 這是 deepseek-flash 實際生成的結果。 |
| 00:30–00:37 | Close-up of the actual English result | Check the answer language, exact strings, audience, tone, limits, and exclusions. | 確認答案語言、固定字串、對象、語氣、字數限制和禁止事項都有保留。 |
| 00:37–00:44 | Separate improvement notes | Copy includes only the prompt. Review improvement notes separately. | 複製只包含 Prompt。優化說明另外顯示，方便檢查。 |
| 00:44–00:48 | Copy action and success message | Copy the prompt and check the success message. | 複製 Prompt，並確認成功訊息。 |
| 00:48–00:55 | Actual manual paste into a TextEdit test document | Paste into a test document. This edits instructions; it does not perform the task. | 手動貼入測試文件。這一步整理指令，不會執行原始任務。 |
| 00:55–01:04 | Native Settings language switching | Four native interface languages: Traditional Chinese, English, Japanese, and Korean. Interface and answer language are separate. | 原生介面支援繁體中文、英文、日文與韓文。介面語言與答案語言分開設定。 |
| 01:04–01:12 | End card with mode information and repository | Live uses your model API. Mock demonstrates the workflow only. Source on GitHub. | 真正優化使用自己的模型 API。Mock 僅示範操作流程。原始碼位於 GitHub。 |

End-card URL: <https://github.com/JERMYSUEN/promptfinch>

## Editing and mode disclosure

- The footage contains actual app captures, assembled into an edited walkthrough. The full loading sequence was not recorded. The cut from input to result does not represent generation latency; do not describe it as an instant response or uninterrupted operation.
- The demonstrated English result came from a real configured `deepseek-flash` request. Live mode sends the submitted input to the configured provider. The native status or an accurate live-mode label should remain visible.
- The end card mentions mock as a separate option. Mock is not the source of the demonstrated English result and does not translate or semantically optimize text.
- Claude in the target-model field describes the intended downstream model. The actual generation model remains `deepseek-flash`.
- No task was executed and no chat message was sent. The paste destination was a synthetic TextEdit test document, not an IDE input field.
- Interface switching does not translate the model's improvement or assumption notes; those are currently requested in Traditional Chinese.

## Subtitle assets

- `demo.en.srt`: 72-second English captions for burning into this edit.
- `demo.zh-TW.srt`: matching Traditional Chinese captions for an optional external subtitle track.

The files contain captions and explanation, not generated prompt text. Retiming is required if the final edit changes. The main film's omitted right-click and IDE-replacement workflow can be added later only after successful actual recording.
