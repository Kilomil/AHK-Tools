#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Mouse", "Screen")

; ── Configuration ──────────────────────────────────────────────
exitColor      := "FF8C00"   ; orange for departure
entryColor     := "00CED1"   ; cyan for arrival
flashColor     := "FFFFFF"   ; white arrival flash
portalMaxSize  := 80         ; max ring radius in pixels
ringWidth      := 14         ; ring thickness in pixels
animFrames     := 8          ; frames per animation
animDuration   := 120        ; total ms per animation

; ── Hotkeys ────────────────────────────────────────────────────
$^XButton1:: TeleportPrev()
$^XButton2:: TeleportNext()
F9:: ExitApp

; ── Build physically-sorted monitor list (left → right) ───────
GetSortedMonitors() {
    monitors := []
    count := MonitorGetCount()
    loop count {
        MonitorGet(A_Index, &L, &T, &R, &B)
        monitors.Push({left: L, top: T, right: R, bottom: B})
    }
    n := monitors.Length
    loop n - 1 {
        i := A_Index
        loop n - i {
            j := A_Index
            if (monitors[j].left > monitors[j + 1].left) {
                tmp := monitors[j]
                monitors[j] := monitors[j + 1]
                monitors[j + 1] := tmp
            }
        }
    }
    return monitors
}

; ── Find which sorted-index the mouse is on ───────────────────
GetCurrentSortedIndex(monitors) {
    MouseGetPos(&mx, &my)
    for idx, mon in monitors {
        if (mx >= mon.left && mx < mon.right && my >= mon.top && my < mon.bottom)
            return idx
    }
    return 1
}

; ── Teleport ──────────────────────────────────────────────────
TeleportPrev() {
    monitors := GetSortedMonitors()
    if (monitors.Length < 2)
        return
    cur := GetCurrentSortedIndex(monitors)
    target := cur - 1
    if (target < 1)
        target := monitors.Length
    DoTeleport(monitors, target)
}

TeleportNext() {
    monitors := GetSortedMonitors()
    if (monitors.Length < 2)
        return
    cur := GetCurrentSortedIndex(monitors)
    target := cur + 1
    if (target > monitors.Length)
        target := 1
    DoTeleport(monitors, target)
}

DoTeleport(monitors, targetIdx) {
    MouseGetPos(&startX, &startY)
    mon := monitors[targetIdx]
    destX := mon.left + (mon.right - mon.left) // 2
    destY := mon.top + (mon.bottom - mon.top) // 2

    PortalShrink(startX, startY)
    DllCall("SetCursorPos", "Int", destX, "Int", destY)
    PortalExpand(destX, destY)
}

; ── Easing (smooth start/stop) ────────────────────────────────
EaseOutCubic(t) {
    t := t - 1.0
    return t * t * t + 1.0
}

EaseInCubic(t) {
    return t * t * t
}

; ── Departure: orange ring shrinks inward ─────────────────────
PortalShrink(cx, cy) {
    global exitColor, portalMaxSize, ringWidth, animFrames, animDuration
    frameDelay := animDuration // animFrames

    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    g.BackColor := exitColor

    loop animFrames {
        t := A_Index / animFrames
        e := EaseInCubic(t)              ; accelerates into nothing

        outerR := Integer(portalMaxSize * (1.0 - e))
        rw     := Integer(ringWidth * (1.0 - e * 0.5))
        alpha  := Integer(240 * (1.0 - e))

        outerR := Max(outerR, 3)
        rw     := Max(rw, 1)
        alpha  := Max(alpha, 10)

        outerD := outerR * 2
        gx := cx - outerR
        gy := cy - outerR

        if (A_Index = 1)
            g.Show("x" gx " y" gy " w" outerD " h" outerD " NoActivate")

        ; Position and size via Win32 for reliable multi-monitor coords
        DllCall("MoveWindow", "Ptr", g.Hwnd, "Int", gx, "Int", gy, "Int", outerD, "Int", outerD, "Int", 1)

        ; Build ring region: outer ellipse minus inner ellipse
        ApplyRingRegion(g.Hwnd, outerD, outerD, rw)
        WinSetTransparent(alpha, g.Hwnd)

        Sleep(frameDelay)
    }
    g.Destroy()
}

; ── Arrival: cyan ring expands outward + white flash ──────────
PortalExpand(cx, cy) {
    global entryColor, flashColor, portalMaxSize, ringWidth, animFrames, animDuration
    frameDelay := animDuration // animFrames

    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    g.BackColor := entryColor

    loop animFrames {
        t := A_Index / animFrames
        e := EaseOutCubic(t)             ; decelerates to rest

        outerR := Integer(portalMaxSize * e)
        rw     := Integer(ringWidth * Max(0.3, e))
        alpha  := Integer(240 * (1.0 - t * 0.7))

        outerR := Max(outerR, 3)
        rw     := Max(rw, 1)
        alpha  := Max(alpha, 10)

        outerD := outerR * 2
        gx := cx - outerR
        gy := cy - outerR

        if (A_Index = 1)
            g.Show("x" gx " y" gy " w" outerD " h" outerD " NoActivate")

        DllCall("MoveWindow", "Ptr", g.Hwnd, "Int", gx, "Int", gy, "Int", outerD, "Int", outerD, "Int", 1)
        ApplyRingRegion(g.Hwnd, outerD, outerD, rw)
        WinSetTransparent(alpha, g.Hwnd)

        Sleep(frameDelay)
    }
    g.Destroy()

    ; White flash burst
    flashR := portalMaxSize // 2
    flashD := flashR * 2
    gf := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    gf.BackColor := flashColor
    gf.Show("x0 y0 w" flashD " h" flashD " NoActivate")
    DllCall("MoveWindow", "Ptr", gf.Hwnd, "Int", cx - flashR, "Int", cy - flashR, "Int", flashD, "Int", flashD, "Int", 1)
    outerRgn := DllCall("CreateEllipticRgn", "Int", 0, "Int", 0, "Int", flashD, "Int", flashD, "Ptr")
    DllCall("SetWindowRgn", "Ptr", gf.Hwnd, "Ptr", outerRgn, "Int", 1)
    WinSetTransparent(90, gf.Hwnd)
    Sleep(30)
    gf.Destroy()
}

; ── Apply a ring-shaped region via Win32 ──────────────────────
; Creates outer ellipse, subtracts inner ellipse → donut/ring
ApplyRingRegion(hwnd, w, h, thickness) {
    innerW := Max(w - thickness * 2, 1)
    innerH := Max(h - thickness * 2, 1)
    offsetX := (w - innerW) // 2
    offsetY := (h - innerH) // 2

    outerRgn := DllCall("CreateEllipticRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr")
    innerRgn := DllCall("CreateEllipticRgn", "Int", offsetX, "Int", offsetY
        , "Int", offsetX + Integer(innerW), "Int", offsetY + Integer(innerH), "Ptr")

    ; RGN_DIFF = 4 → subtract inner from outer
    DllCall("CombineRgn", "Ptr", outerRgn, "Ptr", outerRgn, "Ptr", innerRgn, "Int", 4)
    DllCall("SetWindowRgn", "Ptr", hwnd, "Ptr", outerRgn, "Int", 1)
    DllCall("DeleteObject", "Ptr", innerRgn)
    ; outerRgn is now owned by the window — do not delete
}

; ── Tray ──────────────────────────────────────────────────────
A_TrayMenu.Delete()
A_TrayMenu.Add("Mouse Portal", (*) => "")
A_TrayMenu.Disable("Mouse Portal")
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())

monCount := MonitorGetCount()
TrayTip("Mouse Portal", "Detected " monCount " monitors (sorted left→right)`nCtrl+Thumb1 = prev | Ctrl+Thumb2 = next`nF9 to exit", 1)
