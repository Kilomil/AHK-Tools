#Requires AutoHotkey v2.0
#SingleInstance Force

clickInterval := 100  ; milliseconds between clicks
isClicking := false

F6:: {
    global isClicking
    isClicking := !isClicking
    if isClicking {
        ToolTip("Auto-clicker ON")
        SetTimer(DoClick, clickInterval)
    } else {
        SetTimer(DoClick, 0)
        ToolTip("Auto-clicker OFF")
        SetTimer(HideTooltip, 1000)
    }
}

DoClick() {
    Click
}

HideTooltip() {
    ToolTip()
    SetTimer(HideTooltip, 0)
}

F7:: ExitApp
