#Requires AutoHotkey v2.0
#SingleInstance Force

; ── Configuration ──────────────────────────────────────────────
cooldownMs := 80  ; minimum milliseconds between clicks to count as intentional

; ── State tracking ─────────────────────────────────────────────
lastClick := Map(
    "XButton1", 0,
    "XButton2", 0,
    "MButton",  0
)

blocked := Map(
    "XButton1", 0,
    "XButton2", 0,
    "MButton",  0
)

; ── Hotkeys (use $ to prevent self-triggering) ─────────────────
$XButton1::    HandleClick("XButton1")
$XButton1 Up:: HandleRelease("XButton1")
$XButton2::    HandleClick("XButton2")
$XButton2 Up:: HandleRelease("XButton2")
$MButton::     HandleClick("MButton")
$MButton Up::  HandleRelease("MButton")

; ── Core logic ─────────────────────────────────────────────────
HandleClick(btn) {
    global cooldownMs, lastClick, blocked
    now := A_TickCount

    if (now - lastClick[btn] < cooldownMs) {
        ; Too fast — likely a hardware bounce, block it
        blocked[btn] := true
        return
    }

    ; Enough time has passed — allow the click
    blocked[btn] := false
    lastClick[btn] := now
    Send("{" btn " Down}")
}

HandleRelease(btn) {
    global blocked
    if blocked[btn] {
        ; The down-press was blocked, so block the release too
        blocked[btn] := false
        return
    }
    Send("{" btn " Up}")
}

; ── Tray menu info ─────────────────────────────────────────────
A_TrayMenu.Delete()
A_TrayMenu.Add("Mouse Debounce (" cooldownMs "ms)", (*) => "")
A_TrayMenu.Disable("Mouse Debounce (" cooldownMs "ms)")
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
TrayTip("Mouse Debounce", "Active — cooldown: " cooldownMs "ms`nF8 to exit", 1)

F8:: ExitApp
