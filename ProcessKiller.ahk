#Requires AutoHotkey v2.0
#SingleInstance Force

; ── Configuration ──────────────────────────────────────────────
; Favorites are loaded from / saved to this file.
; Format: one entry per line, "FriendlyName=proc1.exe,proc2.exe"
favoritesFile := A_AppData "\ProcessKiller\favorites.ini"

; Default favorites — seeded on first run when no file exists yet
defaultWatchlist := Map()
  defaultWatchlist["Unity"]     := "Unity.exe,Unity Hub.exe,Unity Editor.exe"
  defaultWatchlist["Rider"]     := "rider64.exe,rider.exe,JetBrains.Rider.exe"
  defaultWatchlist["Fork"]      := "Fork.exe"
  defaultWatchlist["Charles"]   := "charles.exe"
  defaultWatchlist["Slack"]     := "slack.exe"
  defaultWatchlist["Spotify"]   := "Spotify.exe"
  defaultWatchlist["VS Code"]   := "Code.exe"
  defaultWatchlist["Greenshot"] := "Greenshot.exe"

; Active watchlist — loaded from disk below
watchlist := Map()
LoadFavorites()

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
clearBtn := ""
btnRefresh := ""
btnKill := ""
btnKillAll := ""
favHeader := ""
procHeader := ""
titleHeader := ""
memHeader := ""

; ══════════════════════════════════════════════════════════════
; FAVORITES PERSISTENCE
; ══════════════════════════════════════════════════════════════

LoadFavorites() {
    global watchlist, defaultWatchlist, favoritesFile
    watchlist := Map()

    if !FileExist(favoritesFile) {
        ; First run — seed with defaults and write them to disk
        for name, patterns in defaultWatchlist
            watchlist[name] := patterns
        SaveFavorites()
        return
    }

    try {
        content := FileRead(favoritesFile, "UTF-8")
        for line in StrSplit(content, "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue
            eq := InStr(line, "=")
            if !eq
                continue
            friendly := Trim(SubStr(line, 1, eq - 1))
            patterns := Trim(SubStr(line, eq + 1))
            if (friendly != "" && patterns != "")
                watchlist[friendly] := patterns
        }
    }
}

SaveFavorites() {
    global watchlist, favoritesFile
    dir := RegExReplace(favoritesFile, "\\[^\\]+$")
    if !DirExist(dir)
        DirCreate(dir)

    content := "; Process Killer favorites`n; Format: FriendlyName=proc1.exe,proc2.exe`n`n"
    for friendly, patterns in watchlist
        content .= friendly "=" patterns "`n"

    try FileDelete(favoritesFile)
    FileAppend(content, favoritesFile, "UTF-8")
}

IsFavorite(procName) {
    global watchlist
    for _, patterns in watchlist {
        for _, p in StrSplit(patterns, ",") {
            if (Trim(p) = procName)
                return true
        }
    }
    return false
}

AddFavorite(procName) {
    global watchlist
    if IsFavorite(procName)
        return
    ; Use process name without .exe as friendly name; ensure uniqueness
    friendly := RegExReplace(procName, "i)\.exe$")
    base := friendly, n := 2
    while watchlist.Has(friendly)
        friendly := base " (" n++ ")"
    watchlist[friendly] := procName
    SaveFavorites()
    RefreshList()
}

RemoveFavorite(procName) {
    global watchlist
    toDelete := []
    for friendly, patterns in watchlist {
        remaining := []
        for _, p in StrSplit(patterns, ",") {
            p := Trim(p)
            if (p != "" && p != procName)
                remaining.Push(p)
        }
        if remaining.Length = 0
            toDelete.Push(friendly)
        else {
            joined := ""
            for _, p in remaining
                joined .= (joined = "" ? "" : ",") p
            watchlist[friendly] := joined
        }
    }
    for _, f in toDelete
        watchlist.Delete(f)
    SaveFavorites()
    RefreshList()
}

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

    killerGui := Gui("+AlwaysOnTop -MinimizeBox +Resize +MinSize850x500", "Process Killer")
    killerGui.BackColor := guiBg
    killerGui.SetFont("s10 c" guiText, "Segoe UI")
    killerGui.OnEvent("Close", (*) => CloseKiller())
    killerGui.OnEvent("Escape", (*) => CloseKiller())
    killerGui.OnEvent("Size", OnGuiSize)

    ; Search bar
    killerGui.AddText("x10 y12 w50 h24 +0x200", "Filter:")
    searchBox := killerGui.AddEdit("x65 y10 w224 h26 Background" searchBg " c" guiText)
    searchBox.OnEvent("Change", OnSearchChange)
    ; Apply dark theme immediately so border is dark from the start
    DllCall("uxtheme\SetWindowTheme", "Ptr", searchBox.Hwnd, "Str", "DarkMode_CFD", "Ptr", 0)

    ; Clear button — placed just right of the search box, only visible when there is text
    global clearBtn
    clearBtn := killerGui.AddText("x291 y10 w24 h26 +0x200 +Center Background" btnBg " c" accentText " Hidden", "✕")
    clearBtn.OnEvent("Click", (*) => ClearSearch())
    SetupBtnHover(clearBtn, btnBg)

    ; Show-all-processes checkbox. Defaults to checked when the watchlist is empty.
    defaultChecked := (watchlist.Count = 0) ? 1 : 0
    showAllBox := killerGui.AddCheckbox("x325 y13 w190 h22 Background" guiBg " c" guiText " Checked" defaultChecked
        , "Show all processes")
    showAllBox.OnEvent("Click", (*) => RefreshList())

    ; Custom buttons with hover/click effects
    global btnRefresh, btnKill, btnKillAll
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
    ; LV0x10020 = LVS_EX_FULLROWSELECT (0x20) | LVS_EX_DOUBLEBUFFER (0x10000) — double buffering kills cell flicker
    listView := killerGui.AddListView("x10 y45 w830 h420 Grid Multi +LV0x10020 -Hdr Background" listBg " c" guiText
        , ["", "Process", "Title", "Memory (MB)"])

    listView.ModifyCol(1, 30)      ; icon/watchlist marker
    listView.ModifyCol(2, 210)     ; process name
    listView.ModifyCol(3, 440)     ; window title
    listView.ModifyCol(4, 125)     ; memory — leaves room for the vertical scrollbar so horizontal one never appears

    ; Custom header row (since native headers resist theming) — all clickable for sort
    killerGui.SetFont("s9 c" accentText " Bold", "Segoe UI")
    global favHeader, procHeader, titleHeader, memHeader
    favHeader   := killerGui.AddText("x10 y45 w30 h20 +0x200 +Center Background" searchBg, "")
    procHeader  := killerGui.AddText("x40 y45 w210 h20 +0x200 Background" searchBg, "  Process")
    titleHeader := killerGui.AddText("x250 y45 w440 h20 +0x200 Background" searchBg, "  Title")
    memHeader   := killerGui.AddText("x690 y45 w150 h20 +0x200 Background" searchBg, "  Memory (MB)")
    favHeader.OnEvent("Click",   (*) => SetSort("fav"))
    procHeader.OnEvent("Click",  (*) => SetSort("proc"))
    titleHeader.OnEvent("Click", (*) => SetSort("title"))
    memHeader.OnEvent("Click",   (*) => SetSort("mem"))
    UpdateHeaderIndicators()

    ; Shift ListView down to make room for custom header
    listView.Move(, 65,, 400)

    ; Single-click on star column to toggle favorite
    listView.OnEvent("Click", OnListClick)

    ; Double-click to kill (but not on star column)
    listView.OnEvent("DoubleClick", (*) => KillSelected())

    ; Right-click → context menu (add/remove favorite, kill)
    listView.OnEvent("ContextMenu", OnListContextMenu)

    ; Middle-click to instantly kill the row under the cursor
    OnMessage(0x208, KillOnMiddleClick)  ; WM_MBUTTONUP

    ; Fat resize borders
    OnMessage(0x84, OnNcHitTest)  ; WM_NCHITTEST

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
    hoverBtns := [btnRefresh, btnKill, btnKillAll, clearBtn]
    SetTimer(TrackBtnHover, 16)

    isOpen := true
    RefreshList()

    ; Auto-check "Show all" on open when favorites exist but none are running
    if (showAllBox && !showAllBox.Value && listView.GetCount() = 0 && watchlist.Count > 0) {
        showAllBox.Value := 1
        RefreshList()
    }
}

OnSearchChange(*) {
    global clearBtn, searchBox
    if clearBtn
        clearBtn.Visible := (searchBox.Value != "")
    RefreshList()
}

ClearSearch() {
    global searchBox, clearBtn
    searchBox.Value := ""
    if clearBtn
        clearBtn.Visible := false
    try searchBox.Focus()
    RefreshList()
}

; Switch active sort column or flip direction if already active
SetSort(col) {
    global sortColumn, sortDescending
    if (col = sortColumn) {
        sortDescending := !sortDescending
    } else {
        sortColumn := col
        ; Sensible defaults: numeric/favorites descending, text ascending
        sortDescending := (col = "mem" || col = "fav")
    }
    UpdateHeaderIndicators()
    RefreshList()
}

; Rewrite header labels so only the active sort column shows an arrow
UpdateHeaderIndicators() {
    global sortColumn, sortDescending, favHeader, procHeader, titleHeader, memHeader
    arrow := sortDescending ? " ↓" : " ↑"

    if favHeader
        favHeader.Value   := (sortColumn = "fav")   ? "★" arrow : ""
    if procHeader
        procHeader.Value  := "  Process"  ((sortColumn = "proc")  ? arrow : "")
    if titleHeader
        titleHeader.Value := "  Title"    ((sortColumn = "title") ? arrow : "")
    if memHeader
        memHeader.Value   := "  Memory (MB)" ((sortColumn = "mem") ? arrow : "")
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
    try OnMessage(0x84, OnNcHitTest, 0)        ; unregister resize border handler
    if killerGui {
        killerGui.Destroy()
        killerGui := ""
    }
    isOpen := false
}

OnGuiSize(thisGui, minMax, w, h) {
    global listView, searchBox, statusBar, showAllBox, clearBtn
    global btnRefresh, btnKill, btnKillAll
    global favHeader, procHeader, titleHeader, memHeader

    if (minMax = -1)  ; minimized
        return

    margin := 10
    lvW := w - 2 * margin

    ; Reposition buttons anchored to right edge
    if btnKillAll
        btnKillAll.Move(w - margin - 110, 10)
    if btnKill
        btnKill.Move(w - margin - 220, 10)
    if btnRefresh
        btnRefresh.Move(w - margin - 305, 10)

    ; ListView fill available space
    lvH := h - 100  ; top bar + status bar
    if listView {
        listView.Move(margin, 65, lvW, lvH)
        ; Adjust column widths proportionally
        colStar := 30
        colProc := 210
        colMem := 125
        colTitle := lvW - colStar - colProc - colMem - 25  ; 25 for scrollbar
        listView.ModifyCol(1, colStar)
        listView.ModifyCol(2, colProc)
        listView.ModifyCol(3, colTitle)
        listView.ModifyCol(4, colMem)
    }

    ; Custom header row — stretch to match ListView width
    if favHeader
        favHeader.Move(margin, 45, 30)
    if procHeader
        procHeader.Move(margin + 30, 45, 210)
    if titleHeader {
        colTitle := lvW - 30 - 210 - 150 - 25
        titleHeader.Move(margin + 240, 45, colTitle)
    }
    if memHeader
        memHeader.Move(w - margin - 175, 45, 150)

    ; Status bar at bottom
    if statusBar
        statusBar.Move(margin, h - 28, lvW)
}

; ── Fat resize borders (WM_NCHITTEST override) ───────────────
; Default border is ~4px; this makes it ~20px for easy grabbing
OnNcHitTest(wParam, lParam, msg, hwnd) {
    global killerGui
    if !killerGui || hwnd != killerGui.Hwnd
        return

    static HTLEFT := 10, HTRIGHT := 11, HTTOP := 12, HTTOPLEFT := 13
    static HTTOPRIGHT := 14, HTBOTTOM := 15, HTBOTTOMLEFT := 16, HTBOTTOMRIGHT := 17

    border := 30  ; px — ~7x default

    x := lParam & 0xFFFF
    if (x & 0x8000)
        x -= 0x10000
    y := (lParam >> 16) & 0xFFFF
    if (y & 0x8000)
        y -= 0x10000

    ; Get window rect in screen coords
    rect := Buffer(16)
    DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
    wL := NumGet(rect, 0, "Int"), wT := NumGet(rect, 4, "Int")
    wR := NumGet(rect, 8, "Int"), wB := NumGet(rect, 12, "Int")

    left   := (x - wL) < border
    right  := (wR - x) < border
    top    := (y - wT) < border
    bottom := (wB - y) < border

    if (top && left)
        return HTTOPLEFT
    if (top && right)
        return HTTOPRIGHT
    if (bottom && left)
        return HTBOTTOMLEFT
    if (bottom && right)
        return HTBOTTOMRIGHT
    if left
        return HTLEFT
    if right
        return HTRIGHT
    if top
        return HTTOP
    if bottom
        return HTBOTTOM
}

; ══════════════════════════════════════════════════════════════
; PROCESS SCANNING
; ══════════════════════════════════════════════════════════════

; PID lookup: row number → PID (since PID column is hidden)
rowPidMap := Map()
sortColumn := "mem"            ; active sort column: "fav" | "proc" | "title" | "mem"
sortDescending := true         ; current sort direction

RefreshList() {
    global listView, searchBox, statusBar, showAllBox, watchlist, rowPidMap, sortColumn, sortDescending

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

    ; ── Sort by the active column ─────────────────────────────
    SortRows(rows, sortColumn, sortDescending)

    ; ── Add sorted rows to ListView ───────────────────────────
    totalMem := 0.0
    for idx, r in rows {
        rowNum := listView.Add("", r.star, r.proc, r.title, r.mem)
        rowPidMap[rowNum] := r.pid
        totalMem += r.mem
    }

    statusBar.Value := rows.Length " processes  |  " Round(totalMem, 0) " MB total  |  Middle/Double-click to kill  |  Ctrl+Shift+Esc to toggle"
}

; Generic insertion sort on rows by the given column.
; column: "fav" | "proc" | "title" | "mem"
SortRows(rows, column, descending) {
    n := rows.Length
    loop n - 1 {
        i := A_Index + 1
        key := rows[i]
        j := i - 1
        while (j >= 1) {
            cmp := CompareRows(rows[j], key, column)
            if (descending ? cmp < 0 : cmp > 0) {
                rows[j + 1] := rows[j]
                j--
            } else
                break
        }
        rows[j + 1] := key
    }
}

; Returns negative / 0 / positive depending on a<b, a=b, a>b for the chosen column.
CompareRows(a, b, column) {
    switch column {
        case "mem":
            return (a.mem < b.mem) ? -1 : (a.mem > b.mem) ? 1 : 0
        case "fav":
            ; Non-empty star ranks above empty
            av := a.star != "" ? 1 : 0
            bv := b.star != "" ? 1 : 0
            return av - bv
        case "proc":
            return StrCompare(a.proc, b.proc, false)
        case "title":
            return StrCompare(a.title, b.title, false)
    }
    return 0
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

    killerGui.Opt("+OwnDialogs")
    result := MsgBox("Kill " pids.Length " process" (pids.Length > 1 ? "es" : "") "?`n`nThis cannot be undone.",
        "Confirm Kill All", "YesNo Icon! T10")
    if (result != "Yes")
        return

    pidArgs := ""
    for _, pid in pids
        pidArgs .= " /PID " pid
    try RunWait('taskkill /F' pidArgs,, "Hide")

    ShowKillTooltip(pids.Length)
    Sleep(300)
    RefreshList()
}

; Single-click handler — toggle favorite when clicking star column
OnListClick(lv, rowIndex) {
    if (rowIndex = 0)
        return

    ; Get click position relative to ListView client area
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "Ptr", pt)
    DllCall("ScreenToClient", "Ptr", lv.Hwnd, "Ptr", pt)
    relX := NumGet(pt, 0, "Int")

    ; First column is 30px wide — only toggle if click lands there
    if (relX < 0 || relX > 30)
        return

    procName := lv.GetText(rowIndex, 2)
    if (procName = "")
        return

    if IsFavorite(procName)
        RemoveFavorite(procName)
    else
        AddFavorite(procName)
}

; Right-click context menu on a row — add/remove favorite, kill
OnListContextMenu(lv, itemIndex, isRightClick, x, y) {
    if (itemIndex = 0)
        return
    procName := lv.GetText(itemIndex, 2)
    if (procName = "")
        return

    m := Menu()
    if IsFavorite(procName)
        m.Add("Remove '" procName "' from favorites", (*) => RemoveFavorite(procName))
    else
        m.Add("Add '" procName "' to favorites", (*) => AddFavorite(procName))
    m.Add()
    m.Add("Kill", (*) => KillSelected())
    m.Show(x, y)
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
A_IconTip := "Process Killer"

; Left-click tray icon to open/toggle
OnMessage(0x404, OnTrayClick)  ; AHK_NOTIFYICON
OnTrayClick(wParam, lParam, *) {
    if (lParam = 0x202)  ; WM_LBUTTONUP
        ToggleKiller()
}

TrayTip("Process Killer", "Ctrl+Shift+Esc to open`nDouble-click to kill", 1)
