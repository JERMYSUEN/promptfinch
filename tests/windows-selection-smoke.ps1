param([Parameter(Mandatory = $true)][string]$HelperPath)
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
    public static void Stop() {
        if (form != null && !form.IsDisposed) OnUI(delegate { form.Close(); });
        if (thread != null) thread.Join(2000);
    }
}
'@

function Start-Helper([string]$Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $HelperPath
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Could not start the synthetic helper check.' }
    return $process
}

function Read-Once([string]$Arguments = '--read') {
    $process = Start-Helper $Arguments
    try {
        $read = $process.StandardOutput.ReadToEndAsync()
        if (-not $process.WaitForExit(4000)) { throw 'The one-shot selection helper exceeded its time limit.' }
        if (-not $read.Wait(1000)) { throw 'The selection helper output did not close.' }
        return ($read.Result | ConvertFrom-Json)
    } finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(2000) | Out-Null }
        $process.Dispose()
    }
}

$watch = $null
$dummyParent = $null
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
    if (-not $eventLine.Wait(5000)) { throw 'The global right-click watcher did not capture the synthetic selection.' }
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
    $dummyParent.Kill()
    $dummyParent.WaitForExit(2000) | Out-Null
    if (-not $watch.WaitForExit(3500)) { throw 'The watcher remained alive after its parent exited.' }
    Write-Output 'PASS: native selected text, exact Unicode, password rejection, source check, global right-click with host menu, and parent-exit cleanup.'
} finally {
    if ($watch) {
        if (-not $watch.HasExited) { $watch.Kill(); $watch.WaitForExit(2000) | Out-Null }
        $watch.Dispose()
    }
    if ($dummyParent) {
        if (-not $dummyParent.HasExited) { $dummyParent.Kill(); $dummyParent.WaitForExit(2000) | Out-Null }
        $dummyParent.Dispose()
    }
    [PromptFinchSelectionFixture]::Stop()
}
