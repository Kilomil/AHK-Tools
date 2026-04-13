#Requires AutoHotkey v2.0
#SingleInstance Force

; ── Configuration ──────────────────────────────────────────────
; Watchlist: display name → process name patterns (comma-separated)
; These always appear at the top when running
watchlist := Map()
  watchlist["Unity"]    := "Unity.exe,Unity Hub.exe,Unity Editor.exe"
  watchlist["Rider"]    := "rider64.exe,rider.exe,JetBrains.Rider.exe"
  watchlist["Fork"]     := "Fork.exe"
; watchlist["Explorer"] := "explorer.exe"
; watchlist["Edge"]     := "msedge.exe"
; watchlist["Brave"]    := "brave.exe"
  watchlist["Charles"]  := "charles.exe"
; watchlist["Chrome"]   := "chrome.exe"
; watchlist["Discord"]  := "Discord.exe"
  watchlist["Slack"]    := "slack.exe"
; watchlist["Teams"]    := "ms-teams.exe,Teams.exe"
  watchlist["Spotify"]  := "Spotify.exe"
; watchlist["Steam"]    := "steam.exe,steamwebhelper.exe"
  watchlist["VS Code"]  := "Code.exe"
  watchlist["Greenshot"]  := "Greenshot.exe"

; Colors — warm sepia dark theme
guiBg       := "2A2118"      ; dark warm brown background
guiText     := "E0CEAF"      ; warm cream text
listBg      := "231C14"      ; slightly darker for list rows
searchBg    := "3A2F22"      ; search box background
btnBg       := "4A3C2A"      ; button background
btnKillBg   := "6B3A2A"      ; kill button (muted warm red)
btnNukeBg   := "6B4A2A"      ; kill all button (muted amber)
accentText  := "C8A96E"      ; golden accent for stars and status
dimText     := "8A7A60"      ; muted text for status bar

; ── Hotkeys ────────────────────────────────────────────────────
$^+Escape:: ToggleKiller()

; Fix Ctrl+Backspace in Edit controls (AHK eats it and inserts junk)
#HotIf WinActive("Process Killer ahk_class AutoHotkeyGUI")
^Backspace:: {
    global searchBox
    if !searchBox
        return
    ; Send Ctrl+Shift+Left to select the previous word, then delete it
    SendInput("^+{Left}{Delete}")
}
#HotIf

; ── State ──────────────────────────────────────────────────────
killerGui := ""
isOpen := false
listView := ""
searchBox := ""
statusBar := ""
showAllBox := ""

; ══════════════════════════════════════════════════════════════
; GUI
; ══════════════════════════════════════════════════════════════

ToggleKiller() {
    global isOpen
    if isOpen
        CloseKiller()
    else
        OpenKiller()
}

OpenKiller() {
    global killerGui, isOpen, listView, searchBox, statusBar, showAllBox, watchlist

    killerGui := Gui("+AlwaysOnTop -MinimizeBox", "Process Killer")
    killerGui.BackColor := guiBg
    killerGui.SetFont("s10 c" guiText, "Segoe UI")
    killerGui.OnEvent("Close", (*) => CloseKiller())
    killerGui.OnEvent("Escape", (*) => CloseKiller())

    ; Search bar
    killerGui.AddText("x10 y12 w50 h24 +0x200", "Filter:")
    searchBox := killerGui.AddEdit("x65 y10 w250 h26 Background" searchBg " c" guiText)
    searchBox.OnEvent("Change", (*) => RefreshList())
    ; Apply dark theme immediately so border is dark from the start
    DllCall("uxtheme\SetWindowTheme", "Ptr", searchBox.Hwnd, "Str", "DarkMode_CFD", "Ptr", 0)

    ; Show-all-processes checkbox. Defaults to checked when the watchlist is empty.
    defaultChecked := (watchlist.Count = 0) ? 1 : 0
    showAllBox := killerGui.AddCheckbox("x325 y13 w190 h22 Background" guiBg " c" guiText " Checked" defaultChecked
        , "Show all processes")
    showAllBox.OnEvent("Click", (*) => RefreshList())

    ; Custom buttons with hover/click effects
    killerGui.SetFont("s9 c" guiText " Bold", "Segoe UI")

    btnRefresh := killerGui.AddText("x525 y10 w80 h26 +0x200 +Center Background" btnBg, "  Refresh  ")
    btnRefresh.OnEvent("Click", (*) => RefreshList())
    SetupBtnHover(btnRefresh, btnBg)

    btnKill := killerGui.AddText("x615 y10 w105 h26 +0x200 +Center Background" btnKillBg, "  Kill Selected  ")
    btnKill.OnEvent("Click", (*) => KillSelected())
    SetupBtnHover(btnKill, btnKillBg)

    btnKillAll := killerGui.AddText("x730 y10 w110 h26 +0x200 +Center Background" btnNukeBg, "  Kill All Shown  ")
    btnKillAll.OnEvent("Click", (*) => KillAllShown())
    SetupBtnHover(btnKillAll, btnNukeBg)

    ; ListView
    killerGui.SetFont("s10 c" guiText " Norm", "Segoe UI")
    listView := killerGui.AddListView("x10 y45 w830 h420 Grid Multi +LV0x20 -Hdr Background" listBg " c" guiText
        , ["", "Process", "Title", "Memory (MB)"])

    listView.ModifyCol(1, 30)      ; icon/watchlist marker
    listView.ModifyCol(2, 210)     ; process name
    listView.ModifyCol(3, 440)     ; window title
    listView.ModifyCol(4, 150)     ; memory

    ; Custom header row (since native headers resist theming)
    killerGui.SetFont("s9 c" accentText " Bold", "Segoe UI")
    killerGui.AddText("x10 y45 w30 h20 +0x200 Background" searchBg, "")
    killerGui.AddText("x40 y45 w210 h20 +0x200 Background" searchBg, "  Process")
    killerGui.AddText("x250 y45 w440 h20 +0x200 Background" searchBg, "  Title")
    memHeader := killerGui.AddText("x690 y45 w150 h20 +0x200 Background" searchBg, "  Memory (MB)  ↓")
    memHeader.OnEvent("Click", (*) => ToggleMemSort())

    ; Shift ListView down to make room for custom header
    listView.Move(, 65,, 400)

    ; Double-click to kill
    listView.OnEvent("DoubleClick", (*) => KillSelected())

    ; Middle-click to instantly kill the row under the cursor
    OnMessage(0x208, KillOnMiddleClick)  ; WM_MBUTTONUP

    ; Status bar
    killerGui.SetFont("s9 c" dimText, "Segoe UI")
    statusBar := killerGui.AddText("x10 y472 w830 h22", "")

    killerGui.Show("w850 h500")

    ; Dark title bar
    val := 1
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", killerGui.Hwnd, "UInt", 20, "Int*", &val, "UInt", 4)

    ; Dark scrollbar for the ListView
    DllCall("uxtheme\SetWindowTheme", "Ptr", listView.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

    ; Register buttons for hover tracking
    global hoverBtns
    hoverBtns := [btnRefresh, btnKill, btnKillAll]
    SetTimer(TrackBtnHover, 16)

    isOpen := true
    RefreshList()
}

ToggleMemSort() {
    global sortDescending
    sortDescending := !sortDescending
    RefreshList()
}

; ── Button hover/click effects ────────────────────────────────
; Lightens the background on hover, darkens on click
SetupBtnHover(ctrl, baseColor) {
    hoverColor := LightenColor(baseColor, 30)
    clickColor := LightenColor(baseColor, 60)

    ctrl.baseColor := baseColor
    ctrl.hoverColor := hoverColor
    ctrl.clickColor := clickColor
}

; Lighten a hex color by a flat amount per channel
LightenColor(hexColor, amount) {
    r := Min(255, Integer("0x" SubStr(hexColor, 1, 2)) + amount)
    g := Min(255, Integer("0x" SubStr(hexColor, 3, 2)) + amount)
    b := Min(255, Integer("0x" SubStr(hexColor, 5, 2)) + amount)
    return Format("{:02X}{:02X}{:02X}", r, g, b)
}

DarkenColor(hexColor, amount) {
    r := Max(0, Integer("0x" SubStr(hexColor, 1, 2)) - amount)
    g := Max(0, Integer("0x" SubStr(hexColor, 3, 2)) - amount)
    b := Max(0, Integer("0x" SubStr(hexColor, 5, 2)) - amount)
    return Format("{:02X}{:02X}{:02X}", r, g, b)
}

; ── Hover tracking via mouse messages ─────────────────────────
; We use a timer that checks if the mouse is over any button
hoverBtns := []
hoverTimer := ""
currentHover := ""
currentClick := false

TrackBtnHover() {
    global hoverBtns, currentHover, currentClick

    MouseGetPos(,, &winUnder, &ctrlUnder, 2)  ; 2 = get HWND

    newHover := ""
    for _, btn in hoverBtns {
        if (ctrlUnder = btn.Hwnd) {
            newHover := btn
            break
        }
    }

    clicking := GetKeyState("LButton", "P")

    if (newHover != currentHover || clicking != currentClick) {
        ; Restore old button
        if (currentHover != "" && currentHover != newHover) {
            try currentHover.Opt("Background" currentHover.baseColor)
            try currentHover.Redraw()
        }

        ; Apply new state
        if (newHover != "") {
            if clicking {
                try newHover.Opt("Background" newHover.clickColor)
            } else {
                try newHover.Opt("Background" newHover.hoverColor)
            }
            try newHover.Redraw()
        }

        currentHover := newHover
        currentClick := clicking
    }
}

CloseKiller() {
    global killerGui, isOpen, hoverBtns, currentHover
    SetTimer(TrackBtnHover, 0)  ; stop hover tracking
    hoverBtns := []
    currentHover := ""
    try OnMessage(0x208, KillOnMiddleClick, 0)  ; unregister middle-click handler
    if killerGui {
        killerGui.Destroy()
        killerGui := ""
    }
    isOpen := false
}

; ══════════════════════════════════════════════════════════════
; PROCESS SCANNING
; ══════════════════════════════════════════════════════════════

; PID lookup: row number → PID (since PID column is hidden)
rowPidMap := Map()
sortDescending := true         ; current sort direction for memory column

RefreshList() {
    global listView, searchBox, statusBar, showAllBox, watchlist, rowPidMap, sortDescending

    if !listView
        return

    filter := searchBox.Value
    showAll := showAllBox ? showAllBox.Value : 0
    listView.Delete()
    rowPidMap := Map()

    ; Build PID → window title map (matches Task Manager's "main window" selection)
    ; Task Manager picks the unowned, visible top-level window — same as .NET's Process.MainWindowHandle
    pidTitles := Map()
    for hwnd in WinGetList() {
        try {
            ; Skip owned windows (dialogs, tool windows, secondary popups like "Addressables Report")
            if DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")   ; GW_OWNER = 4
                continue
            ; Skip non-visible windows
            if !DllCall("IsWindowVisible", "Ptr", hwnd)
                continue
            title := WinGetTitle("ahk_id " hwnd)
            if (title = "")
                continue
            pid := WinGetPID("ahk_id " hwnd)
            if !pidTitles.Has(pid)
                pidTitles[pid] := title
        }
    }

    ; Get all running processes via Win32 snapshot (much faster than WMI)
    processes := Map()
    TH32CS_SNAPPROCESS := 0x2
    hSnap := DllCall("CreateToolhelp32Snapshot", "UInt", TH32CS_SNAPPROCESS, "UInt", 0, "Ptr")
    if (hSnap != -1) {
        ; PROCESSENTRY32W struct layout differs by architecture
        ; x64: ULONG_PTR is 8 bytes + 4 bytes padding before it = different offsets
        ; x86: ULONG_PTR is 4 bytes, no padding
        if (A_PtrSize = 8) {
            peSize := 568
            nameOffset := 44
        } else {
            peSize := 556
            nameOffset := 36
        }

        pe := Buffer(peSize, 0)
        NumPut("UInt", peSize, pe, 0)

        ok := DllCall("Process32FirstW", "Ptr", hSnap, "Ptr", pe, "Int")
        while ok {
            pid := NumGet(pe, 8, "UInt")
            name := StrGet(pe.Ptr + nameOffset, 260, "UTF-16")

            if (pid != 0) {
                ; Get memory via OpenProcess + GetProcessMemoryInfo
                memMB := 0.0
                PROCESS_QUERY_LIMITED := 0x1000
                hProc := DllCall("OpenProcess", "UInt", PROCESS_QUERY_LIMITED, "Int", 0, "UInt", pid, "Ptr")
                if hProc {
                    pmcSize := 8 + A_PtrSize * 9
                    pmc := Buffer(pmcSize, 0)
                    NumPut("UInt", pmcSize, pmc, 0)
                    if DllCall("psapi\GetProcessMemoryInfo", "Ptr", hProc, "Ptr", pmc, "UInt", pmcSize, "Int")
                        memMB := Round(NumGet(pmc, 8 + A_PtrSize, "UPtr") / 1048576, 1)
                    DllCall("CloseHandle", "Ptr", hProc)
                }

                if !processes.Has(name)
                    processes[name] := []
                processes[name].Push({pid: pid, mem: memMB})
            }

            NumPut("UInt", peSize, pe, 0)
            ok := DllCall("Process32NextW", "Ptr", hSnap, "Ptr", pe, "Int")
        }
        DllCall("CloseHandle", "Ptr", hSnap)
    }

    ; Collect all rows into an array for sorting
    rows := []

    ; ── Watchlist items (starred) ─────────────────────────────
    for friendlyName, patterns in watchlist {
        patternList := StrSplit(patterns, ",")
        for _, pattern in patternList {
            pattern := Trim(pattern)
            if !processes.Has(pattern)
                continue

            if (filter != "") {
                if !InStr(friendlyName, filter) && !InStr(pattern, filter)
                    continue
            }

            for _, info in processes[pattern] {
                title := pidTitles.Has(info.pid) ? pidTitles[info.pid] : ""
                rows.Push({star: "★", friendly: friendlyName, proc: pattern, title: title, mem: info.mem, pid: info.pid})
            }
            processes.Delete(pattern)
        }
    }

    ; ── Other processes (when "show all" is checked, or when filter is active) ─
    if (showAll || filter != "") {
        for procName, instances in processes {
            if (filter != "" && !InStr(procName, filter))
                continue
            for _, info in instances {
                title := pidTitles.Has(info.pid) ? pidTitles[info.pid] : ""
                rows.Push({star: "", friendly: "", proc: procName, title: title, mem: info.mem, pid: info.pid})
            }
        }
    }

    ; ── Sort by memory (descending by default) ────────────────
    SortRowsByMemory(rows, sortDescending)

    ; ── Add sorted rows to ListView ───────────────────────────
    totalMem := 0.0
    for idx, r in rows {
        rowNum := listView.Add("", r.star, r.proc, r.title, r.mem)
        rowPidMap[rowNum] := r.pid
        totalMem += r.mem
    }

    statusBar.Value := rows.Length " processes  |  " Round(totalMem, 0) " MB total  |  Middle/Double-click to kill  |  Ctrl+Shift+Esc to toggle"
}

SortRowsByMemory(rows, descending) {
    ; Simple insertion sort by .mem
    n := rows.Length
    loop n - 1 {
        i := A_Index + 1
        key := rows[i]
        j := i - 1
        while (j >= 1) {
            if (descending ? rows[j].mem < key.mem : rows[j].mem > key.mem) {
                rows[j + 1] := rows[j]
                j--
            } else
                break
        }
        rows[j + 1] := key
    }
}


; ══════════════════════════════════════════════════════════════
; KILL ACTIONS
; ══════════════════════════════════════════════════════════════

KillSelected() {
    global listView, rowPidMap

    if !listView
        return

    killed := 0
    row := 0
    loop {
        row := listView.GetNext(row)
        if !row
            break

        if !rowPidMap.Has(row)
            continue

        pid := rowPidMap[row]
        try {
            RunWait('taskkill /F /PID ' pid,, "Hide")
            killed++
        }
    }

    if (killed > 0) {
        ShowKillTooltip(killed)
        Sleep(300)
        RefreshList()
    }
}

KillAllShown() {
    global listView, rowPidMap

    if !listView
        return

    pids := []
    loop listView.GetCount() {
        procName := listView.GetText(A_Index, 2)

        ; Safety: never kill explorer without it being explicitly filtered
        if (procName = "explorer.exe")
            continue

        if rowPidMap.Has(A_Index)
            pids.Push(rowPidMap[A_Index])
    }

    if (pids.Length = 0)
        return

    pidArgs := ""
    for _, pid in pids
        pidArgs .= " /PID " pid
    try RunWait('taskkill /F' pidArgs,, "Hide")

    ShowKillTooltip(pids.Length)
    Sleep(300)
    RefreshList()
}

; Middle-click on a row kills it instantly (no selection needed)
KillOnMiddleClick(wParam, lParam, msg, hwnd) {
    global listView, rowPidMap
    if !listView || hwnd != listView.Hwnd
        return

    x := lParam & 0xFFFF
    if (x & 0x8000)                   ; sign-extend
        x -= 0x10000
    y := (lParam >> 16) & 0xFFFF
    if (y & 0x8000)
        y -= 0x10000

    ; LVHITTESTINFO: POINT(x,y) + UINT flags + int iItem + int iSubItem
    hti := Buffer(16 + 2 * A_PtrSize, 0)
    NumPut("Int", x, hti, 0)
    NumPut("Int", y, hti, 4)
    SendMessage(0x1012, 0, hti.Ptr, , "ahk_id " listView.Hwnd)  ; LVM_HITTEST
    row := NumGet(hti, 12, "Int") + 1  ; iItem is 0-based; listView rows are 1-based

    if (row < 1 || !rowPidMap.Has(row))
        return

    pid := rowPidMap[row]
    try {
        RunWait('taskkill /F /PID ' pid,, "Hide")
        ShowKillTooltip(1)
        SetTimer(() => RefreshList(), -200)
    }
}

ShowKillTooltip(count) {
    ToolTip("💀 Killed " count " process" (count > 1 ? "es" : ""))
    SetTimer(HideTooltip, -2000)
}

HideTooltip() {
    ToolTip()
}

; ── Tray ──────────────────────────────────────────────────────
A_TrayMenu.Delete()
A_TrayMenu.Add("Process Killer", (*) => "")
A_TrayMenu.Disable("Process Killer")
A_TrayMenu.Add()
A_TrayMenu.Add("Open", (*) => OpenKiller())
A_TrayMenu.Add("Exit", (*) => ExitApp())

TrayTip("Process Killer", "Ctrl+Shift+Esc to open`nDouble-click to kill", 1)
