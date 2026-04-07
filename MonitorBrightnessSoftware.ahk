#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Mouse", "Screen")

; ── Configuration ──────────────────────────────────────────────
brightnessStep := 0.05        ; 5% per scroll tick
minBrightness  := 0.05        ; 5% floor (very dark, but not invisible)
maxBrightness  := 1.00        ; 100% = normal

nightlightStep := 0.05        ; 5% per scroll tick
minNightlight  := 0.00        ; 0% = neutral / no tint
maxNightlight  := 1.00        ; 100% = maximum warmth

; Night light color temperature curve (warmth 0→1)
; At max warmth: R stays full, G drops to 75%, B drops to 35%
nlRedMax   := 1.00
nlGreenMin := 0.75
nlBlueMin  := 0.35

; ── State ─────────────────────────────────────────────────────
brightness := Map()            ; per-monitor brightness (1.0 = normal)
overlays   := Map()            ; per-monitor overlay GUI objects
nightlight := Map()            ; per-monitor warmth level (0.0 = off)

; ── Hotkeys ────────────────────────────────────────────────────
; Brightness
$!WheelUp::    AdjustBrightness(brightnessStep)
$!WheelDown::  AdjustBrightness(-brightnessStep)
$!MButton:: {
    ResetMonitor("brightness")
}

; Night light
$^WheelUp::    AdjustNightlight(-nightlightStep)
$^WheelDown::  AdjustNightlight(nightlightStep)
$^MButton:: {
    ResetMonitor("nightlight")
}

F10:: ExitApp

; ══════════════════════════════════════════════════════════════
; BRIGHTNESS — black overlay approach (no 50% floor)
; ══════════════════════════════════════════════════════════════

AdjustBrightness(delta) {
    global brightness, minBrightness, maxBrightness

    monIdx := GetMonitorIndexUnderMouse()
    if !monIdx
        return
    monName := MonitorGetName(monIdx)

    if !brightness.Has(monName)
        brightness[monName] := 1.0

    brightness[monName] := Max(minBrightness, Min(maxBrightness, brightness[monName] + delta))

    UpdateOverlay(monIdx, monName)
    ShowTooltip("☀", brightness[monName])
}

UpdateOverlay(monIdx, monName) {
    global brightness, overlays

    level := brightness.Has(monName) ? brightness[monName] : 1.0

    if (level >= 1.0) {
        ; Full brightness — hide/destroy overlay
        if overlays.Has(monName) {
            overlays[monName].Destroy()
            overlays.Delete(monName)
        }
        return
    }

    ; Calculate alpha: brightness 1.0→0 maps to alpha 0→250
    alpha := Integer((1.0 - level) * 250)
    alpha := Max(0, Min(250, alpha))

    MonitorGet(monIdx, &L, &T, &R, &B)
    w := R - L
    h := B - T

    if !overlays.Has(monName) {
        ; Create a new click-through black overlay
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000")
        g.BackColor := "000000"
        g.MarginX := 0
        g.MarginY := 0
        g.Show("NoActivate Hide")
        overlays[monName] := g
    }

    g := overlays[monName]
    DllCall("MoveWindow", "Ptr", g.Hwnd, "Int", L, "Int", T, "Int", w, "Int", h, "Int", 1)
    DllCall("ShowWindow", "Ptr", g.Hwnd, "Int", 8)  ; SW_SHOWNA (show without activating)
    WinSetTransparent(alpha, g.Hwnd)
}

; ══════════════════════════════════════════════════════════════
; NIGHT LIGHT — gamma ramp color temperature shift
; ══════════════════════════════════════════════════════════════

AdjustNightlight(delta) {
    global nightlight, minNightlight, maxNightlight

    monIdx := GetMonitorIndexUnderMouse()
    if !monIdx
        return
    monName := MonitorGetName(monIdx)

    if !nightlight.Has(monName)
        nightlight[monName] := 0.0

    nightlight[monName] := Max(minNightlight, Min(maxNightlight, nightlight[monName] + delta))

    ApplyNightlight(monName)
    ShowTooltip("🌙", 1.0 - nightlight[monName], "warm")
}

ApplyNightlight(monName) {
    global nightlight, nlRedMax, nlGreenMin, nlBlueMin

    warmth := nightlight.Has(monName) ? nightlight[monName] : 0.0

    ; Interpolate channel multipliers based on warmth
    rMul := nlRedMax
    gMul := 1.0 - (1.0 - nlGreenMin) * warmth    ; 1.0 → 0.75
    bMul := 1.0 - (1.0 - nlBlueMin) * warmth      ; 1.0 → 0.35

    hDC := DllCall("CreateDC", "Str", monName, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
    if !hDC
        return

    ramp := Buffer(1536, 0)

    loop 256 {
        i := A_Index - 1
        base := i * 257
        NumPut("UShort", Integer(Min(base * rMul, 65535)), ramp, i * 2)
        NumPut("UShort", Integer(Min(base * gMul, 65535)), ramp, i * 2 + 512)
        NumPut("UShort", Integer(Min(base * bMul, 65535)), ramp, i * 2 + 1024)
    }

    DllCall("SetDeviceGammaRamp", "Ptr", hDC, "Ptr", ramp)
    DllCall("DeleteDC", "Ptr", hDC)
}

; ══════════════════════════════════════════════════════════════
; SHARED UTILITIES
; ══════════════════════════════════════════════════════════════

GetMonitorIndexUnderMouse() {
    MouseGetPos(&mx, &my)
    count := MonitorGetCount()
    loop count {
        MonitorGet(A_Index, &L, &T, &R, &B)
        if (mx >= L && mx < R && my >= T && my < B)
            return A_Index
    }
    return 0
}

ResetMonitor(mode) {
    global brightness, nightlight

    monIdx := GetMonitorIndexUnderMouse()
    if !monIdx
        return
    monName := MonitorGetName(monIdx)

    if (mode = "brightness") {
        brightness[monName] := 1.0
        UpdateOverlay(monIdx, monName)
        ShowTooltip("☀", 1.0)
    } else {
        nightlight[monName] := 0.0
        ApplyNightlight(monName)
        ShowTooltip("🌙", 1.0, "warm")
    }
}

ShowTooltip(icon, level, mode := "") {
    pct := Round(level * 100)
    filled := Round(pct / 5)
    empty := 20 - filled
    bar := ""
    loop filled
        bar .= "█"
    loop empty
        bar .= "░"

    if (mode = "warm")
        label := (pct = 100) ? "Off" : Round((1.0 - level) * 100) "%"
    else
        label := pct "%"

    ToolTip(icon " " bar " " label)
    SetTimer(HideTooltip, -1500)
}

HideTooltip() {
    ToolTip()
}

; ── SAFETY: Full cleanup on exit ──────────────────────────────
OnExit(CleanupAll)

CleanupAll(*) {
    global overlays, nightlight

    ; Destroy all brightness overlays
    for monName, g in overlays {
        try g.Destroy()
    }

    ; Reset gamma ramps (night light) on all monitors
    count := MonitorGetCount()
    loop count {
        monName := MonitorGetName(A_Index)
        hDC := DllCall("CreateDC", "Str", monName, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
        if !hDC
            continue
        ramp := Buffer(1536, 0)
        loop 256 {
            i := A_Index - 1
            val := i * 257
            NumPut("UShort", val, ramp, i * 2)
            NumPut("UShort", val, ramp, i * 2 + 512)
            NumPut("UShort", val, ramp, i * 2 + 1024)
        }
        DllCall("SetDeviceGammaRamp", "Ptr", hDC, "Ptr", ramp)
        DllCall("DeleteDC", "Ptr", hDC)
    }
}

; ── Tray ──────────────────────────────────────────────────────
A_TrayMenu.Delete()
A_TrayMenu.Add("Monitor Brightness + Night Light", (*) => "")
A_TrayMenu.Disable("Monitor Brightness + Night Light")
A_TrayMenu.Add()
A_TrayMenu.Add("Reset All", (*) => CleanupAll())
A_TrayMenu.Add("Exit", (*) => ExitApp())

TrayTip("Monitor Brightness + Night Light"
    , "Alt+Scroll = brightness`nCtrl+Scroll = night light`nMiddleClick = reset (with modifier)`nF10 to exit"
    , 1)
