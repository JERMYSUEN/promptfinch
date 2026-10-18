param([Parameter(Mandatory = $true)][string]$HelperPath, [string]$ChromePath = '')
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This synthetic UI Automation smoke check requires Windows.' }
$HelperPath = (Resolve-Path $HelperPath).Path

# This fixture owns its own synthetic controls and never reads the clipboard,
# an existing editor, browser content, credentials or a running CLI session.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
public static class PromptFinchSelectionFixture {
    private static Form form;
    private static RichTextBox normal;
    private static TextBox password;
    private static Thread thread;
    private static readonly ManualResetEvent ready = new ManualResetEvent(false);
    public static volatile bool MenuOpened;
    public const string Expected = "Synthetic ACME-42 request. Preserve Cafe\u0301 and answer in Japanese.";
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    public static void Start() {
        thread = new Thread(delegate() {
            form = new Form(); form.Text = "PromptFinch synthetic selection fixture";
            form.StartPosition = FormStartPosition.Manual; form.Location = new Point(180, 140);
            form.Size = new Size(640, 300); form.TopMost = true;
            normal = new RichTextBox(); normal.Location = new Point(20, 20); normal.Size = new Size(570, 120);
            normal.Text = Expected; normal.HideSelection = false;
            normal.ContextMenuStrip = new ContextMenuStrip(); normal.ContextMenuStrip.Items.Add("Synthetic fixture action");
            normal.ContextMenuStrip.Opened += delegate { MenuOpened = true; };
            password = new TextBox(); password.Location = new Point(20, 170); password.Size = new Size(450, 30);
            password.UseSystemPasswordChar = true; password.Text = "SYNTHETIC_PASSWORD_MUST_NOT_BE_CAPTURED";
            form.Controls.Add(normal); form.Controls.Add(password);
            form.Shown += delegate { ready.Set(); };
            Application.Run(form);
        });
        thread.SetApartmentState(ApartmentState.STA); thread.IsBackground = true; thread.Start();
        if (!ready.WaitOne(5000)) throw new Exception("Synthetic form did not become ready.");
    }
    private static void OnUI(Action action) { form.Invoke(action); }
    public static void SelectNormal() {
        OnUI(delegate { normal.ContextMenuStrip.Close(); form.Activate(); SetForegroundWindow(form.Handle); normal.Focus(); normal.SelectAll(); });
    }
    public static void SelectPassword() {
        OnUI(delegate { normal.ContextMenuStrip.Close(); form.Activate(); SetForegroundWindow(form.Handle); password.Focus(); password.SelectAll(); });
    }
    public static void RightClickNormal() {
        MenuOpened = false;
        OnUI(delegate {
            normal.ContextMenuStrip.Close(); form.Activate(); SetForegroundWindow(form.Handle); normal.Focus(); normal.SelectAll();
            Point point = normal.PointToScreen(new Point(14, 14)); SetCursorPos(point.X, point.Y);
            mouse_event(0x0008, 0, 0, 0, UIntPtr.Zero); mouse_event(0x0010, 0, 0, 0, UIntPtr.Zero);
        });
    }
    public static void Hide() { OnUI(delegate { normal.ContextMenuStrip.Close(); form.Hide(); }); }
    public static void RightClickWindow(IntPtr window) {
        SetForegroundWindow(window);
        Rect rect;
        if (!GetWindowRect(window, out rect)) throw new Exception("The synthetic browser window is unavailable.");
        SetCursorPos(rect.Left + 60, rect.Top + 80);
        mouse_event(0x0008, 0, 0, 0, UIntPtr.Zero); mouse_event(0x0010, 0, 0, 0, UIntPtr.Zero);
    }
    public static void Stop() {
        if (form != null && !form.IsDisposed) OnUI(delegate { form.Close(); });
        if (thread != null) thread.Join(2000);
    }
}
'@

function Start-Helper([string]$Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $HelperPath
    $info.Arguments = "$Arguments --diagnostics"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Could not start the synthetic helper check.' }
    $process | Add-Member -NotePropertyName SmokeDiagnostics -NotePropertyValue ($process.StandardError.ReadToEndAsync())
    return $process
}

# The fixture host may itself be an STA COM provider. A blocking Wait() or
# WaitForExit() on PowerShell's STA can prevent UIA from obtaining the control,
# even though the visible WinForms UI has its own thread and message loop.
function Wait-TaskWithMessages($Task, [int]$Milliseconds) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    while (-not $Task.IsCompleted -and [DateTime]::UtcNow -lt $deadline) {
        [System.Windows.Forms.Application]::DoEvents()
        [System.Threading.Thread]::Sleep(10)
    }
    return $Task.IsCompleted
}

function Wait-ProcessWithMessages($Process, [int]$Milliseconds) {
    $deadline = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    while (-not $Process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        [System.Windows.Forms.Application]::DoEvents()
        [System.Threading.Thread]::Sleep(10)
    }
    return $Process.HasExited
}

function Show-HelperDiagnostics($Process) {
    if ($Process.SmokeDiagnostics -and (Wait-TaskWithMessages $Process.SmokeDiagnostics 1000)) {
        $diagnostic = $Process.SmokeDiagnostics.Result
        if ($diagnostic) { [Console]::Error.WriteLine($diagnostic.TrimEnd()) }
    }
}

function Read-Once([string]$Arguments = '--read') {
    $process = Start-Helper $Arguments
    try {
        $read = $process.StandardOutput.ReadToEndAsync()
        if (-not (Wait-ProcessWithMessages $process 4000)) { throw 'The one-shot selection helper exceeded its time limit.' }
        if (-not (Wait-TaskWithMessages $read 1000)) { throw 'The selection helper output did not close.' }
        return ($read.Result | ConvertFrom-Json)
    } finally {
        if (-not $process.HasExited) { $process.Kill(); Wait-ProcessWithMessages $process 2000 | Out-Null }
        Show-HelperDiagnostics $process
        $process.Dispose()
    }
}

$watch = $null
$dummyParent = $null
$browser = $null
$browserRoot = $null
try {
    [PromptFinchSelectionFixture]::Start()
    [PromptFinchSelectionFixture]::SelectNormal()
    Start-Sleep -Milliseconds 200
    $normal = Read-Once
    if (-not $normal.ok -or $normal.text -cne [PromptFinchSelectionFixture]::Expected) {
        throw 'The focused synthetic text selection was not preserved exactly.'
    }
    if ($normal.sourceId -notmatch '^[1-9][0-9]*:[1-9][0-9]*$') { throw 'The native source identity is missing.' }
    $verified = Read-Once "--verify-source $($normal.sourceId)"
    if (-not $verified.ok) { throw 'The active synthetic source could not be verified.' }

    [PromptFinchSelectionFixture]::SelectPassword()
    Start-Sleep -Milliseconds 100
    $password = Read-Once
    if ($password.ok -or $password.code -ne 'PASSWORD' -or $password.PSObject.Properties.Name -contains 'text') {
        throw 'The synthetic password control was not rejected safely.'
    }

    # A separate live process stands in for Electron for parent-lifetime checks;
    # excluding this PowerShell PID would exclude the fixture's own source UI.
    $parentInfo = New-Object System.Diagnostics.ProcessStartInfo
    $parentInfo.FileName = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $parentInfo.Arguments = '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"'
    $parentInfo.UseShellExecute = $false
    $parentInfo.CreateNoWindow = $true
    $dummyParent = [System.Diagnostics.Process]::Start($parentInfo)
    $watch = Start-Helper "--watch --exclude-pid $($dummyParent.Id)"
    $eventLine = $watch.StandardOutput.ReadLineAsync()
    Start-Sleep -Milliseconds 600
    [PromptFinchSelectionFixture]::RightClickNormal()
    if (-not (Wait-TaskWithMessages $eventLine 5000)) { throw 'The global right-click watcher did not capture the synthetic selection.' }
    $event = $eventLine.Result | ConvertFrom-Json
    if (-not $event.ok -or $event.text -cne [PromptFinchSelectionFixture]::Expected -or $event.sourceId -ne $normal.sourceId) {
        throw 'The right-click event did not preserve the captured synthetic source.'
    }
    if (-not ($event.x -is [int] -or $event.x -is [long]) -or -not ($event.y -is [int] -or $event.y -is [long]) -or $event.capturedAt -le 0) {
        throw 'The right-click event is missing bounded native coordinates and time.'
    }
    $menuDeadline = [DateTime]::UtcNow.AddSeconds(1)
    while (-not [PromptFinchSelectionFixture]::MenuOpened -and [DateTime]::UtcNow -lt $menuDeadline) { Start-Sleep -Milliseconds 20 }
    if (-not [PromptFinchSelectionFixture]::MenuOpened) { throw 'The watcher prevented the host context menu from opening.' }

    if ($ChromePath) {
        $ChromePath = (Resolve-Path $ChromePath).Path
        [PromptFinchSelectionFixture]::Hide()
        $browserRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('promptfinch-uia-browser-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $browserRoot | Out-Null
        $htmlPath = Join-Path $browserRoot 'selection.html'
        $expectedJson = [PromptFinchSelectionFixture]::Expected | ConvertTo-Json -Compress
        $html = @"
<!doctype html><meta charset="utf-8"><title>PromptFinch synthetic virtual selection</title>
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
<style>body{margin:0}textarea{position:fixed;left:20px;top:20px;width:800px;height:400px;padding:12px;font:20px/1.5 sans-serif}</style>
<textarea id="prompt" aria-label="Synthetic prompt fixture" autofocus></textarea>
<script>const field=document.getElementById('prompt');field.value=$expectedJson;
const selected=()=>document.activeElement===field&&field.selectionStart===0&&field.selectionEnd===field.value.length;
field.addEventListener('contextmenu',()=>{document.title=selected()?'PromptFinch virtual menu with selection':'PromptFinch virtual menu without selection'});
setTimeout(()=>{field.focus();field.select();document.title=selected()?'PromptFinch virtual selection ready':'PromptFinch virtual selection missing'},300)</script>
"@
        [System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding($false)))
        $browserInfo = New-Object System.Diagnostics.ProcessStartInfo
        $browserInfo.FileName = $ChromePath
        $fileUrl = ([Uri]$htmlPath).AbsoluteUri
        $profile = Join-Path $browserRoot 'profile'
        $browserInfo.Arguments = "--app=`"$fileUrl`" --user-data-dir=`"$profile`" --window-position=100,100 --window-size=900,600 --force-renderer-accessibility --no-first-run --no-default-browser-check --disable-background-networking --disable-component-update --disable-sync"
        $browserInfo.UseShellExecute = $false
        $browser = [System.Diagnostics.Process]::Start($browserInfo)
        $browserDeadline = [DateTime]::UtcNow.AddSeconds(12)
        while (-not $browser.HasExited -and $browser.MainWindowHandle -eq [IntPtr]::Zero -and [DateTime]::UtcNow -lt $browserDeadline) {
            Start-Sleep -Milliseconds 100
            $browser.Refresh()
        }
        if ($browser.HasExited -or $browser.MainWindowHandle -eq [IntPtr]::Zero) { throw 'The isolated synthetic Chrome fixture did not open a native window.' }
        $selectionDeadline = [DateTime]::UtcNow.AddSeconds(5)
        while ($browser.MainWindowTitle -notlike '*PromptFinch virtual selection ready*' -and [DateTime]::UtcNow -lt $selectionDeadline) {
            [System.Windows.Forms.Application]::DoEvents()
            [System.Threading.Thread]::Sleep(20)
            $browser.Refresh()
        }
        if ($browser.MainWindowTitle -notlike '*PromptFinch virtual selection ready*') { throw 'The isolated Chromium textarea did not confirm its complete synthetic selection.' }
        # Give the subscribed UIA focus event time to deliver its metadata-only
        # reference before the context menu takes focus. No content polling.
        Start-Sleep -Milliseconds 300
        $chromeLine = $watch.StandardOutput.ReadLineAsync()
        [PromptFinchSelectionFixture]::RightClickWindow($browser.MainWindowHandle)
        $capturedChrome = Wait-TaskWithMessages $chromeLine 5000
        $chromeMenuDeadline = [DateTime]::UtcNow.AddSeconds(1)
        do {
            [System.Windows.Forms.Application]::DoEvents()
            [System.Threading.Thread]::Sleep(20)
            $browser.Refresh()
        } while ($browser.MainWindowTitle -notlike '*PromptFinch virtual menu with selection*' -and [DateTime]::UtcNow -lt $chromeMenuDeadline)
        if ($browser.MainWindowTitle -notlike '*PromptFinch virtual menu with selection*') { throw 'The synthetic browser right-click did not preserve the selected textarea content.' }
        if (-not $capturedChrome) { throw 'The watcher did not capture the Chromium virtual text selection.' }
        $chrome = $chromeLine.Result | ConvertFrom-Json
        if (-not $chrome.ok -or $chrome.text -cne [PromptFinchSelectionFixture]::Expected) {
            throw 'The Chromium virtual text selection was not preserved exactly.'
        }
        Write-Output 'PASS: isolated headed Chrome virtual textarea selection through the right-click watcher (synthetic offline page only).'
    }
    $dummyParent.Kill()
    Wait-ProcessWithMessages $dummyParent 2000 | Out-Null
    if (-not (Wait-ProcessWithMessages $watch 3500)) { throw 'The watcher remained alive after its parent exited.' }
    Write-Output 'PASS: native selected text, exact Unicode, password rejection, source check, global right-click with host menu, and parent-exit cleanup.'
} finally {
    if ($browser) {
        if (-not $browser.HasExited) {
            $browser.CloseMainWindow() | Out-Null
            if (-not (Wait-ProcessWithMessages $browser 3000)) { $browser.Kill(); Wait-ProcessWithMessages $browser 2000 | Out-Null }
        }
        $browser.Dispose()
    }
    if ($watch) {
        if (-not $watch.HasExited) { $watch.Kill(); Wait-ProcessWithMessages $watch 2000 | Out-Null }
        Show-HelperDiagnostics $watch
        $watch.Dispose()
    }
    if ($dummyParent) {
        if (-not $dummyParent.HasExited) { $dummyParent.Kill(); Wait-ProcessWithMessages $dummyParent 2000 | Out-Null }
        $dummyParent.Dispose()
    }
    [PromptFinchSelectionFixture]::Stop()
    if ($browserRoot -and (Test-Path $browserRoot)) { Remove-Item -LiteralPath $browserRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
