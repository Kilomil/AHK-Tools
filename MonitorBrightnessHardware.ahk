#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Mouse", "Screen")

; ── Configuration ──────────────────────────────────────────────
brightnessStep := 10           ; percent per scroll tick (hardware range)
minBrightness  := 0           ; hardware minimum (0%)
maxBrightness  := 100         ; hardware maximum (100%)

nightlightStep := 0.10        ; 5% per scroll tick
minNightlight  := 0.00        ; 0% = neutral / no tint
maxNightlight  := 1.00        ; 100% = maximum warmth

; Night light color temperature curve (warmth 0→1)
nlGreenMin := 0.75
nlBlueMin  := 0.35

; Overlay fallback range (for non-DDC monitors)
overlayMinBrightness := 0.05
overlayStep          := 0.05

; VCP code for brightness
VCP_BRIGHTNESS := 0x10

; ── State ─────────────────────────────────────────────────────
ddcBrightness   := Map()      ; per-HMONITOR: current brightness %
ddcMaxVal       := Map()      ; per-HMONITOR: max brightness value from hardware
ddcOriginal     := Map()      ; per-HMONITOR: original brightness at script start
ddcSupported    := Map()      ; per-HMONITOR: true/false (cached DDC/CI support)
ddcMethod       := Map()      ; per-HMONITOR: "highlevel" or "vcp" (which API works)
overlayLevel    := Map()      ; per-monName: overlay brightness (fallback)
overlays        := Map()      ; per-monName: overlay GUI objects
nightlight      := Map()      ; per-monName: warmth level

; ── Load dxva2.dll ────────────────────────────────────────────
hDxva2 := DllCall("LoadLibrary", "Str", "dxva2.dll", "Ptr")

; ── Hotkeys ────────────────────────────────────────────────────
$!WheelUp::    AdjustBrightness(1)
$!WheelDown::  AdjustBrightness(-1)
$!MButton::    ResetMonitor("brightness")

$^WheelUp::    AdjustNightlight(-nightlightStep)
$^WheelDown::  AdjustNightlight(nightlightStep)
$^MButton::    ResetMonitor("nightlight")

F10:: ExitApp
; F11:: RunDiagnostic()

; ══════════════════════════════════════════════════════════════
; BRIGHTNESS — DDC/CI hardware backlight with overlay fallback
; ══════════════════════════════════════════════════════════════

AdjustBrightness(direction) {
    global brightnessStep

    MouseGetPos(&mx, &my)
    hMon := GetHMonitorFromPoint(mx, my)
    if !hMon
        return

    ; Check DDC/CI support (cached after first attempt)
    if !ddcSupported.Has(hMon)
        ProbeDDC(hMon)

    if ddcSupported[hMon]
        AdjustDDC(hMon, direction * brightnessStep)
    else
        AdjustOverlayBrightness(direction * overlayStep)
}

; ── DDC/CI path ───────────────────────────────────────────────
ProbeDDC(hMon) {
    global ddcSupported, ddcBrightness, ddcOriginal, ddcMethod, ddcMaxVal, VCP_BRIGHTNESS

    pm := GetPhysicalMonitor(hMon)
    if !pm {
        ddcSupported[hMon] := false
        ShowFallbackNotice()
        return
    }
    phys := pm.handle

    ; ── Attempt 1: High-level GetMonitorBrightness ────────────
    minVal := 0, curVal := 0, maxVal := 0
    ok := DllCall("dxva2\GetMonitorBrightness", "Ptr", phys
        , "UInt*", &minVal, "UInt*", &curVal, "UInt*", &maxVal, "Int")

    if (ok && maxVal > 0) {
        DllCall("dxva2\DestroyPhysicalMonitor", "Ptr", phys)
        ddcSupported[hMon] := true
        ddcMethod[hMon] := "highlevel"
        ddcMaxVal[hMon] := maxVal
        ddcBrightness[hMon] := curVal
        ddcOriginal[hMon] := curVal
        return
    }

    ; ── Attempt 2: Low-level VCP code 0x10 (works on AOC etc) ─
    pvt := 0, curVcp := 0, maxVcp := 0
    ok := DllCall("dxva2\GetVCPFeatureAndVCPFeatureReply", "Ptr", phys
        , "UChar", VCP_BRIGHTNESS
        , "UInt*", &pvt, "UInt*", &curVcp, "UInt*", &maxVcp, "Int")

    DllCall("dxva2\DestroyPhysicalMonitor", "Ptr", phys)

    if (ok && maxVcp > 0) {
        ddcSupported[hMon] := true
        ddcMethod[hMon] := "vcp"
        ddcMaxVal[hMon] := maxVcp
        ddcBrightness[hMon] := curVcp
        ddcOriginal[hMon] := curVcp
        return
    }

    ; ── Both failed — overlay fallback ────────────────────────
    ddcSupported[hMon] := false
    ShowFallbackNotice()
}

AdjustDDC(hMon, delta) {
    global ddcBrightness, ddcMaxVal, ddcMethod, VCP_BRIGHTNESS

    if !ddcBrightness.Has(hMon)
        return

    maxVal := ddcMaxVal.Has(hMon) ? ddcMaxVal[hMon] : 100
    newVal := Integer(Max(0, Min(maxVal, ddcBrightness[hMon] + delta)))
    ddcBrightness[hMon] := newVal

    pm := GetPhysicalMonitor(hMon)
    if !pm
        return
    phys := pm.handle

    method := ddcMethod.Has(hMon) ? ddcMethod[hMon] : "highlevel"

    if (method = "vcp")
        DllCall("dxva2\SetVCPFeature", "Ptr", phys, "UChar", VCP_BRIGHTNESS, "UInt", newVal, "Int")
    else
        DllCall("dxva2\SetMonitorBrightness", "Ptr", phys, "UInt", newVal, "Int")

    DllCall("dxva2\DestroyPhysicalMonitor", "Ptr", phys)

    ShowTooltip("☀", newVal / maxVal)
}

; ── Overlay fallback path (non-DDC monitors) ──────────────────
AdjustOverlayBrightness(delta) {
    global overlayLevel, overlayMinBrightness

    monIdx := GetMonitorIndexUnderMouse()
    if !monIdx
        return
    monName := MonitorGetName(monIdx)

    if !overlayLevel.Has(monName)
        overlayLevel[monName] := 1.0

    overlayLevel[monName] := Max(overlayMinBrightness, Min(1.0, overlayLevel[monName] + delta))
    UpdateOverlay(monIdx, monName)
    ShowTooltip("☀", overlayLevel[monName], "", " (sw)")
}

UpdateOverlay(monIdx, monName) {
    global overlayLevel, overlays

    level := overlayLevel.Has(monName) ? overlayLevel[monName] : 1.0

    if (level >= 1.0) {
        if overlays.Has(monName) {
            overlays[monName].Destroy()
            overlays.Delete(monName)
        }
        return
    }

    alpha := Integer((1.0 - level) * 250)
    alpha := Max(0, Min(250, alpha))

    MonitorGet(monIdx, &L, &T, &R, &B)
    w := R - L
    h := B - T

    if !overlays.Has(monName) {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000")
        g.BackColor := "000000"
        g.MarginX := 0
        g.MarginY := 0
        g.Show("NoActivate Hide")
        overlays[monName] := g
    }

    g := overlays[monName]
    DllCall("MoveWindow", "Ptr", g.Hwnd, "Int", L, "Int", T, "Int", w, "Int", h, "Int", 1)
    DllCall("ShowWindow", "Ptr", g.Hwnd, "Int", 8)
    WinSetTransparent(alpha, g.Hwnd)
}

ShowFallbackNotice() {
    static shown := false
    if !shown {
        shown := true
        ToolTip("⚠ DDC/CI not supported — using overlay fallback")
        SetTimer(HideTooltip, -3000)
    }
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
    global nightlight, nlGreenMin, nlBlueMin

    warmth := nightlight.Has(monName) ? nightlight[monName] : 0.0

    rMul := 1.0
    gMul := 1.0 - (1.0 - nlGreenMin) * warmth
    bMul := 1.0 - (1.0 - nlBlueMin) * warmth

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
; DIAGNOSTIC (F11) — shows exactly where DDC/CI fails
; ══════════════════════════════════════════════════════════════

RunDiagnostic() {
    global VCP_BRIGHTNESS

    MouseGetPos(&mx, &my)
    monIdx := GetMonitorIndexUnderMouse()
    monName := monIdx ? MonitorGetName(monIdx) : "N/A"

    hMon := GetHMonitorFromPoint(mx, my)
    info := "── Monitor Diagnostic ──`n"
    info .= "Mouse: " mx ", " my "`n"
    info .= "Monitor index: " monIdx "`n"
    info .= "Monitor name: " monName "`n"
    info .= "HMONITOR: " Format("0x{:X}", hMon) "`n`n"

    if !hMon {
        MsgBox(info "FAILED: Could not get HMONITOR")
        return
    }

    ; Step 1: GetNumberOfPhysicalMonitors
    numMon := 0
    ok1 := DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt*", &numMon, "Int")
    err1 := A_LastError
    info .= "GetNumberOfPhysicalMonitors: " (ok1 ? "OK" : "FAIL") " (count=" numMon ", err=" err1 ")`n"

    if (!ok1 || numMon < 1) {
        MsgBox(info "`nFAILED: No physical monitors found")
        return
    }

    ; Step 2: GetPhysicalMonitorsFromHMONITOR
    structSize := A_PtrSize + 128 * 2
    buf := Buffer(structSize * numMon, 0)
    ok2 := DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt", numMon, "Ptr", buf, "Int")
    err2 := A_LastError
    phys := NumGet(buf, 0, "Ptr")
    physName := StrGet(buf.Ptr + A_PtrSize, 128, "UTF-16")
    info .= "GetPhysicalMonitors: " (ok2 ? "OK" : "FAIL") " (handle=" Format("0x{:X}", phys) ", err=" err2 ")`n"
    info .= "Physical monitor name: " physName "`n"
    info .= "(Note: handle=0x0 may still be valid on some drivers)`n`n"

    if !ok2 {
        MsgBox(info "FAILED: GetPhysicalMonitors call returned error")
        return
    }

    ; Step 3: Try high-level GetMonitorBrightness (proceed even with handle=0)
    minVal := 0, curVal := 0, maxVal := 0
    ok3 := DllCall("dxva2\GetMonitorBrightness", "Ptr", phys
        , "UInt*", &minVal, "UInt*", &curVal, "UInt*", &maxVal, "Int")
    err3 := A_LastError
    info .= "GetMonitorBrightness: " (ok3 ? "OK" : "FAIL") " (min=" minVal " cur=" curVal " max=" maxVal " err=" err3 ")`n"

    ; Step 4: Try low-level GetVCPFeature (VCP 0x10)
    pvt := 0, curVcp := 0, maxVcp := 0
    ok4 := DllCall("dxva2\GetVCPFeatureAndVCPFeatureReply", "Ptr", phys
        , "UChar", VCP_BRIGHTNESS
        , "UInt*", &pvt, "UInt*", &curVcp, "UInt*", &maxVcp, "Int")
    err4 := A_LastError
    info .= "GetVCPFeature(0x10): " (ok4 ? "OK" : "FAIL") " (cur=" curVcp " max=" maxVcp " err=" err4 ")`n"

    ; Step 5: Try GetMonitorCapabilities
    caps := 0, colorTemps := 0
    ok5 := DllCall("dxva2\GetMonitorCapabilities", "Ptr", phys
        , "UInt*", &caps, "UInt*", &colorTemps, "Int")
    err5 := A_LastError
    info .= "GetMonitorCapabilities: " (ok5 ? "OK" : "FAIL") " (caps=" Format("0x{:X}", caps) " err=" err5 ")`n"

    DllCall("dxva2\DestroyPhysicalMonitor", "Ptr", phys)

    ; Summary
    info .= "`n── Result ──`n"
    if ok3
        info .= "✓ High-level API works — use SetMonitorBrightness"
    else if ok4
        info .= "✓ Low-level VCP works — use SetVCPFeature"
    else
        info .= "✗ Both APIs failed — overlay fallback needed"

    MsgBox(info, "DDC/CI Diagnostic")
}

; ══════════════════════════════════════════════════════════════
; PHYSICAL MONITOR HELPERS (DDC/CI)
; ══════════════════════════════════════════════════════════════

GetHMonitorFromPoint(x, y) {
    ; MONITOR_DEFAULTTONEAREST = 2
    return DllCall("MonitorFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "UInt", 2, "Ptr")
}

GetPhysicalMonitor(hMon) {
    numMon := 0
    ok := DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt*", &numMon, "Int")
    if (!ok || numMon < 1)
        return false

    ; PHYSICAL_MONITOR struct = Ptr (handle) + 128 WCHARs (name) = 8 + 256 = 264 bytes (x64)
    structSize := A_PtrSize + 128 * 2
    buf := Buffer(structSize * numMon, 0)

    ok := DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR", "Ptr", hMon, "UInt", numMon, "Ptr", buf, "Int")
    if !ok
        return false

    ; Return the handle — do NOT null-check it, 0 can be valid on some drivers
    return {handle: NumGet(buf, 0, "Ptr"), valid: true}
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
    global ddcBrightness, ddcOriginal, ddcSupported, overlayLevel, nightlight

    if (mode = "brightness") {
        MouseGetPos(&mx, &my)
        hMon := GetHMonitorFromPoint(mx, my)
        if !hMon
            return

        if (ddcSupported.Has(hMon) && ddcSupported[hMon]) {
            ; Restore to original hardware brightness
            origVal := ddcOriginal.Has(hMon) ? ddcOriginal[hMon] : 100
            maxVal := ddcMaxVal.Has(hMon) ? ddcMaxVal[hMon] : 100
            method := ddcMethod.Has(hMon) ? ddcMethod[hMon] : "highlevel"
            ddcBrightness[hMon] := origVal
            pm := GetPhysicalMonitor(hMon)
            if pm {
                if (method = "vcp")
                    DllCall("dxva2\SetVCPFeature", "Ptr", pm.handle, "UChar", VCP_BRIGHTNESS, "UInt", origVal, "Int")
                else
                    DllCall("dxva2\SetMonitorBrightness", "Ptr", pm.handle, "UInt", origVal, "Int")
                DllCall("dxva2\DestroyPhysicalMonitor", "Ptr", pm.handle)
            }
            ShowTooltip("☀", origVal / maxVal)
        } else {
            monIdx := GetMonitorIndexUnderMouse()
            if !monIdx
                return
            monName := MonitorGetName(monIdx)
            overlayLevel[monName] := 1.0
            UpdateOverlay(monIdx, monName)
            ShowTooltip("☀", 1.0)
        }
    } else {
        monIdx := GetMonitorIndexUnderMouse()
        if !monIdx
            return
        monName := MonitorGetName(monIdx)
        nightlight[monName] := 0.0
        ApplyNightlight(monName)
        ShowTooltip("🌙", 1.0, "warm")
    }
}

ShowTooltip(icon, level, mode := "", suffix := "") {
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

    ToolTip(icon " " bar " " label suffix)
    SetTimer(HideTooltip, -1500)
}

HideTooltip() {
    ToolTip()
}

; ── SAFETY: Full cleanup on exit ──────────────────────────────
OnExit(CleanupAll)

CleanupAll(*) {
    global overlays, ddcOriginal, ddcSupported

    ; Destroy all overlay windows
    for monName, g in overlays {
        try g.Destroy()
    }

    ; Restore DDC/CI monitors to original brightness
    for hMon, origVal in ddcOriginal {
        try {
            method := ddcMethod.Has(hMon) ? ddcMethod[hMon] : "highlevel"
            pm := GetPhysicalMonitor(hMon)
            if pm {
                if (method = "vcp")
                    DllCall("dxva2\SetVCPFeature", "Ptr", pm.handle, "UChar", VCP_BRIGHTNESS, "UInt", origVal, "Int")
                else
                    DllCall("dxva2\SetMonitorBrightness", "Ptr", pm.handle, "UInt", origVal, "Int")
                DllCall("dxva2\DestroyPhysicalMonitor", "Ptr", pm.handle)
            }
        }
    }

    ; Reset gamma ramps (night light)
    count := MonitorGetCount()
    loop count {
        try {
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

    ; Free library
    if hDxva2
        DllCall("FreeLibrary", "Ptr", hDxva2)
}

; ── Tray ──────────────────────────────────────────────────────
A_TrayMenu.Delete()
A_TrayMenu.Add("Monitor Brightness (DDC/CI) + Night Light", (*) => "")
A_TrayMenu.Disable("Monitor Brightness (DDC/CI) + Night Light")
A_TrayMenu.Add()
A_TrayMenu.Add("Reset All", (*) => CleanupAll())
A_TrayMenu.Add("Exit", (*) => ExitApp())

TrayTip("Monitor Brightness (DDC/CI)"
    , "Alt+Scroll = hardware brightness`nCtrl+Scroll = night light`nMiddleClick+modifier = reset`nF10 to exit"
    , 1)
