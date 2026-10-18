// Build on Windows with the .NET Framework compiler (no NuGet dependency):
// %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:exe
//   /out:SelectionReader.exe /reference:WindowsBase.dll
//   /reference:UIAutomationClient.dll /reference:UIAutomationTypes.dll SelectionReader.cs
// Resolve references from %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\WPF\
// or the installed .NET Framework reference assemblies when not on csc's path.
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Automation.Text;

internal static class SelectionReader
{
    private const int Limit = 12000;
    private const int WH_MOUSE_LL = 14;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_QUIT = 0x0012;
    private const long MaxAge = 1500;
    private static readonly object OutputLock = new object();
    private static readonly object PendingLock = new object();
    private static readonly object FocusLock = new object();
    private static readonly AutoResetEvent PendingReady = new AutoResetEvent(false);
    private static readonly HookCallback Hook = MouseHook;
    private static IntPtr hookHandle;
    private static int excludePid;
    private static int ownPid;
    private static long sequence;
    private static volatile bool stopping;
    private static Pending pending;
    private static FocusReference focusedReference;
    private static uint mainThread;

    private sealed class Pending
    {
        internal int X, Y;
        internal IntPtr Window, Focus;
        internal uint Pid, Thread;
        internal long At, Sequence;
        internal AutomationElement Element;
    }
    private sealed class FocusReference
    {
        internal AutomationElement Element;
        internal IntPtr Window, Focus;
        internal uint Pid;
    }
    private sealed class Result
    {
        internal string Text;
        internal string Code;
        internal string Source;
    }

    [StructLayout(LayoutKind.Sequential)] private struct Point { internal int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { internal int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct GuiInfo
    {
        internal uint Size, Flags;
        internal IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        internal Rect CaretRect;
    }
    [StructLayout(LayoutKind.Sequential)] private struct MouseData
    {
        internal Point Point;
        internal uint Mouse, Flags, Time;
        internal UIntPtr Extra;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Message
    {
        internal IntPtr Window;
        internal uint Id;
        internal UIntPtr WParam;
        internal IntPtr LParam;
        internal uint Time;
        internal Point Point;
        internal uint Private;
    }
    private delegate IntPtr HookCallback(int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint thread, ref GuiInfo info);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int type, HookCallback callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr handle);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr handle, int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll")] private static extern int GetMessage(out Message message, IntPtr window, uint minimum, uint maximum);
    [DllImport("user32.dll")] private static extern bool PeekMessage(out Message message, IntPtr window, uint minimum, uint maximum, uint remove);
    [DllImport("user32.dll")] private static extern bool TranslateMessage(ref Message message);
    [DllImport("user32.dll")] private static extern IntPtr DispatchMessage(ref Message message);
    [DllImport("user32.dll")] private static extern bool PostThreadMessage(uint thread, uint message, UIntPtr wparam, IntPtr lparam);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string name);

    [MTAThread]
    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        ownPid = Process.GetCurrentProcess().Id;
        bool watch = false;
        string verification = null;
        for (int index = 0; index < args.Length; index++)
        {
            if (args[index] == "--watch") watch = true;
            else if (args[index] == "--read") { }
            else if (args[index] == "--verify-source" && index + 1 < args.Length) verification = args[++index];
            else if (args[index] == "--exclude-pid" && index + 1 < args.Length)
            {
                if (!Int32.TryParse(args[++index], out excludePid) || excludePid < 1) return Fail("HELPER_ERROR");
            }
            else return Fail("HELPER_ERROR");
        }
        if (verification != null)
        {
            uint pid; long window;
            string[] fields = verification.Split(':');
            if (watch || fields.Length != 2 || !UInt32.TryParse(fields[0], out pid) || pid == 0
                || !Int64.TryParse(fields[1], out window) || window <= 0
                || verification != pid.ToString() + ":" + window.ToString()) return Fail("HELPER_ERROR");
            IntPtr foreground = GetForegroundWindow(); uint currentPid;
            GetWindowThreadProcessId(foreground, out currentPid);
            if (foreground.ToInt64() != window || currentPid != pid) { Write(Error("FOCUS_CHANGED"), null); return 0; }
            try { Console.WriteLine("{\"ok\":true}"); } catch { return 1; }
            return 0;
        }
        if (!watch)
        {
            Result read = Capture(Source(GetForegroundWindow()));
            Write(read, null);
            return 0;
        }
        mainThread = GetCurrentThreadId();
        Message initialMessage;
        PeekMessage(out initialMessage, IntPtr.Zero, 0, 0, 0);
        Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e)
        {
            e.Cancel = true; Stop();
        };
        Thread worker = new Thread(Worker);
        worker.IsBackground = true;
        worker.SetApartmentState(ApartmentState.MTA);
        worker.Start();
        Timer parentTimer = null;
        if (excludePid > 0)
        {
            long launched;
            try { launched = Process.GetProcessById(excludePid).StartTime.ToUniversalTime().Ticks; }
            catch { Stop(); return 0; }
            parentTimer = new Timer(delegate(object state)
            {
                try
                {
                    using (Process parent = Process.GetProcessById(excludePid))
                    {
                        if (parent.HasExited || parent.StartTime.ToUniversalTime().Ticks != launched) Stop();
                    }
                }
                catch { Stop(); }
            }, null, 500, 500);
        }
        hookHandle = SetWindowsHookEx(WH_MOUSE_LL, Hook, GetModuleHandle(null), 0);
        if (hookHandle == IntPtr.Zero) { stopping = true; PendingReady.Set(); return Fail("HELPER_ERROR"); }
        try
        {
            Message message;
            int result;
            while ((result = GetMessage(out message, IntPtr.Zero, 0, 0)) > 0)
            {
                TranslateMessage(ref message); DispatchMessage(ref message);
            }
            if (result < 0) return Fail("HELPER_ERROR");
        }
        finally
        {
            Stop(); if (parentTimer != null) parentTimer.Dispose(); UnhookWindowsHookEx(hookHandle);
        }
        return 0;
    }

    private static IntPtr MouseHook(int code, IntPtr message, IntPtr data)
    {
        // Never query UI Automation, write output, or suppress input in a hook.
        if (code >= 0 && message.ToInt64() == WM_RBUTTONDOWN && !stopping)
        {
            try
            {
                MouseData mouse = (MouseData)Marshal.PtrToStructure(data, typeof(MouseData));
                Pending item = Source(GetForegroundWindow());
                if (item == null) return CallNextHookEx(hookHandle, code, message, data);
                // Copy only an already obtained reference. No UIA call or text
                // access is permitted from this low-level mouse callback.
                lock (FocusLock)
                {
                    if (focusedReference != null && focusedReference.Window == item.Window
                        && focusedReference.Pid == item.Pid && focusedReference.Focus == item.Focus)
                        item.Element = focusedReference.Element;
                }
                long current = Interlocked.Increment(ref sequence);
                item.X = mouse.Point.X; item.Y = mouse.Point.Y; item.At = Now(); item.Sequence = current;
                lock (PendingLock)
                {
                    pending = item;
                }
                PendingReady.Set();
            }
            catch { /* An observation failure must not affect the host menu. */ }
        }
        return CallNextHookEx(hookHandle, code, message, data);
    }

    private static void Worker()
    {
        AutomationFocusChangedEventHandler handler = FocusChanged;
        bool subscribed = false;
        try
        {
            // Focus events provide virtual controls that have no native HWND.
            // Cache metadata and a full reference only; text is read solely in
            // response to the user's explicit right-click action below.
            CacheRequest cache = new CacheRequest();
            cache.TreeScope = TreeScope.Element;
            cache.AutomationElementMode = AutomationElementMode.Full;
            cache.Add(AutomationElement.ProcessIdProperty);
            cache.Add(AutomationElement.ControlTypeProperty);
            cache.Add(AutomationElement.IsPasswordProperty);
            cache.Add(AutomationElement.HasKeyboardFocusProperty);
            cache.Add(AutomationElement.NativeWindowHandleProperty);
            try
            {
                using (cache.Activate())
                {
                    Automation.AddAutomationFocusChangedEventHandler(handler);
                    subscribed = true;
                    FocusChanged(AutomationElement.FocusedElement, null);
                }
            }
            catch { lock (FocusLock) { focusedReference = null; } }
            while (!stopping)
            {
                PendingReady.WaitOne();
                if (stopping) break;
                Pending item;
                lock (PendingLock) { item = pending; pending = null; }
                if (item == null) continue;
                if (item.Sequence != Interlocked.Read(ref sequence) || Now() - item.At > MaxAge) continue;
                Result result;
                // A stuck external UIA provider must not leave a permanent hook.
                using (Timer deadline = new Timer(delegate(object state) { Stop(); }, null, 2200, Timeout.Infinite))
                {
                    result = Capture(item);
                }
                if (result.Text == null || item.Sequence != Interlocked.Read(ref sequence)
                    || Now() - item.At > MaxAge || stopping) continue;
                Write(result, item);
            }
        }
        finally
        {
            lock (FocusLock) { focusedReference = null; }
            // Add and remove on the same long-lived MTA thread. Hook cleanup
            // does not wait on an unresponsive external automation provider.
            if (subscribed) { try { Automation.RemoveAutomationFocusChangedEventHandler(handler); } catch { } }
        }
    }

    private static void FocusChanged(object sender, AutomationFocusChangedEventArgs args)
    {
        try
        {
            if (stopping) return;
            AutomationElement element = sender as AutomationElement;
            Pending source = Source(GetForegroundWindow());
            if (element == null || source == null) { lock (FocusLock) { focusedReference = null; } return; }
            AutomationElement.AutomationElementInformation info = element.Cached;
            bool menu = info.ControlType == ControlType.Menu || info.ControlType == ControlType.MenuItem;
            lock (FocusLock)
            {
                if (menu)
                {
                    // A menu may temporarily own UIA focus. Preserve only the
                    // reference matching this exact native source identity.
                    if (focusedReference != null && (focusedReference.Window != source.Window
                        || focusedReference.Pid != source.Pid || focusedReference.Focus != source.Focus)) focusedReference = null;
                    return;
                }
                focusedReference = null;
                if (info.IsPassword || info.ProcessId != source.Pid || !info.HasKeyboardFocus
                    || info.ControlType == ControlType.Window) return;
                focusedReference = new FocusReference { Element = element, Window = source.Window,
                    Focus = source.Focus, Pid = source.Pid };
            }
        }
        catch { lock (FocusLock) { focusedReference = null; } }
    }

    private static Pending Source(IntPtr window)
    {
        if (window == IntPtr.Zero) return null;
        uint pid;
        uint thread = GetWindowThreadProcessId(window, out pid);
        GuiInfo info = new GuiInfo(); info.Size = (uint)Marshal.SizeOf(typeof(GuiInfo));
        if (pid == 0 || pid == ownPid || pid == excludePid || !GetGUIThreadInfo(thread, ref info)
            || info.Focus == IntPtr.Zero) return null;
        uint focusPid;
        GetWindowThreadProcessId(info.Focus, out focusPid);
        if (focusPid != pid || GetAncestor(info.Focus, 2) != window) return null;
        return new Pending { Window = window, Focus = info.Focus, Thread = thread, Pid = pid };
    }

    private static bool SameSource(Pending source)
    {
        if (source == null || source.Window != GetForegroundWindow()) return false;
        uint pid;
        GetWindowThreadProcessId(source.Window, out pid);
        if (pid != source.Pid) return false;
        GuiInfo info = new GuiInfo(); info.Size = (uint)Marshal.SizeOf(typeof(GuiInfo));
        if (!GetGUIThreadInfo(source.Thread, ref info)) return false;
        if (info.Focus == source.Focus) return true;
        // Native menus may own UIA focus while the original control retains its
        // selection. Permit only a menu owned by the captured source window.
        return (info.Flags & 0x14) != 0 && info.MenuOwner != IntPtr.Zero
            && GetAncestor(info.MenuOwner, 2) == source.Window;
    }

    private static Result Capture(Pending source)
    {
        try
        {
            if (!SameSource(source)) return Error("FOCUS_CHANGED");
            AutomationElement native = AutomationElement.FromHandle(source.Focus);
            if (native == null) return Error("NO_SELECTION");
            if (native.Current.IsPassword) return Error("PASSWORD");
            AutomationElement focused = AutomationElement.FocusedElement;
            bool focusedUsable = IsUsableFocus(focused, source);
            AutomationElement element = source.Element;
            if (element != null && focusedUsable && !Automation.Compare(element, focused)) return Error("FOCUS_CHANGED");
            if (element != null && !focusedUsable && !IsSourceMenu(focused, source)) return Error("FOCUS_CHANGED");
            // Resolve only the captured native focus control when the native
            // context menu has taken UIA focus. Never enumerate a UIA subtree.
            if (element == null) element = focusedUsable ? focused : native;
            if (element == null) return Error("NO_SELECTION");
            AutomationElement.AutomationElementInformation info = element.Current;
            if (info.IsPassword) return Error("PASSWORD");
            // A focused provider in another process is not a proven source.
            if (info.ProcessId != source.Pid) return Error("FOCUS_CHANGED");
            object raw;
            if (!element.TryGetCurrentPattern(TextPattern.Pattern, out raw)) return Error("UNSUPPORTED");
            TextPattern pattern = raw as TextPattern;
            if (pattern == null || pattern.SupportedTextSelection == SupportedTextSelection.None) return Error("UNSUPPORTED");
            TextPatternRange[] ranges = pattern.GetSelection();
            if (ranges == null || ranges.Length != 1) return Error("NO_SELECTION");
            string text = ranges[0].GetText(Limit + 1);
            if (String.IsNullOrWhiteSpace(text) || text.IndexOf('\0') >= 0) return Error("NO_SELECTION");
            if (text.Length > Limit) return Error("TOO_LONG");
            if (!SameSource(source) || native.Current.IsPassword) return Error("FOCUS_CHANGED");
            focused = AutomationElement.FocusedElement;
            if (IsUsableFocus(focused, source) && !Automation.Compare(element, focused)) return Error("FOCUS_CHANGED");
            if (source.Element != null && !IsUsableFocus(focused, source) && !IsSourceMenu(focused, source)) return Error("FOCUS_CHANGED");
            TextPatternRange[] finalRanges = pattern.GetSelection();
            if (finalRanges == null || finalRanges.Length != 1
                || !String.Equals(text, finalRanges[0].GetText(Limit + 1), StringComparison.Ordinal)) return Error("FOCUS_CHANGED");
            return new Result { Text = text, Source = source.Pid.ToString() + ":" + source.Window.ToInt64().ToString() };
        }
        catch { return Error("HELPER_ERROR"); }
    }

    private static bool IsUsableFocus(AutomationElement element, Pending source)
    {
        if (element == null) return false;
        AutomationElement.AutomationElementInformation info = element.Current;
        return info.ProcessId == source.Pid && info.ControlType != ControlType.Menu
            && info.ControlType != ControlType.MenuItem && info.ControlType != ControlType.Window
            && info.HasKeyboardFocus && (info.NativeWindowHandle == 0 || info.NativeWindowHandle == source.Focus.ToInt64());
    }

    private static bool IsSourceMenu(AutomationElement element, Pending source)
    {
        if (element != null)
        {
            AutomationElement.AutomationElementInformation info = element.Current;
            if (info.ProcessId == source.Pid && (info.ControlType == ControlType.Menu || info.ControlType == ControlType.MenuItem)) return true;
        }
        GuiInfo gui = new GuiInfo(); gui.Size = (uint)Marshal.SizeOf(typeof(GuiInfo));
        return GetGUIThreadInfo(source.Thread, ref gui) && (gui.Flags & 0x14) != 0
            && gui.MenuOwner != IntPtr.Zero && GetAncestor(gui.MenuOwner, 2) == source.Window;
    }

    private static Result Error(string code) { return new Result { Code = code }; }
    private static void Stop()
    {
        stopping = true; PendingReady.Set();
        if (mainThread != 0) PostThreadMessage(mainThread, WM_QUIT, UIntPtr.Zero, IntPtr.Zero);
    }
    private static long Now() { return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds; }
    private static int Fail(string code) { Write(Error(code), null); return 1; }
    private static void Write(Result result, Pending item)
    {
        string json = result.Text == null ? "{\"ok\":false,\"code\":" + Quote(result.Code) + "}"
            : "{\"ok\":true,\"text\":" + Quote(result.Text) + ",\"sourceId\":" + Quote(result.Source)
              + (item == null ? "" : ",\"x\":" + item.X + ",\"y\":" + item.Y + ",\"capturedAt\":" + item.At) + "}";
        lock (OutputLock) { try { Console.WriteLine(json); Console.Out.Flush(); } catch { Stop(); } }
    }
    private static string Quote(string value)
    {
        if (value == null) return "null";
        StringBuilder text = new StringBuilder("\"");
        foreach (char character in value)
        {
            if (character == '"') text.Append("\\\"");
            else if (character == '\\') text.Append("\\\\");
            else if (character < 32 || Char.IsSurrogate(character)) text.Append("\\u" + ((int)character).ToString("x4"));
            else text.Append(character);
        }
        return text.Append('"').ToString();
    }
}
