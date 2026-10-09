import AppKit
import Foundation

guard CommandLine.arguments.count == 4,
      let rawPID = Int32(CommandLine.arguments[1]) else {
    fputs("用法錯誤：需要 PID、bundle ID 與執行檔路徑。\n", stderr)
    exit(2)
}

let bundleID = CommandLine.arguments[2]
let expectedExecutable = URL(fileURLWithPath: CommandLine.arguments[3]).standardizedFileURL
guard let app = NSRunningApplication(processIdentifier: pid_t(rawPID)),
      app.bundleIdentifier == bundleID,
      app.executableURL?.standardizedFileURL == expectedExecutable else {
    fputs("執行中的程序與指定 App 不符；未送出退出要求。\n", stderr)
    exit(3)
}

if app.isTerminated { exit(0) }
guard app.terminate() else {
    fputs("macOS 未接受此 App 的正常退出要求。\n", stderr)
    exit(4)
}

let deadline = Date().addingTimeInterval(8)
while Date() < deadline {
    if NSRunningApplication(processIdentifier: pid_t(rawPID))?.isTerminated != false { exit(0) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
fputs("App 尚未正常結束；未強制終止。\n", stderr)
exit(5)
