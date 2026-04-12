#Requires AutoHotkey v2.0
#SingleInstance Force

^+c:: {
    path := GetSelectedFilePath()
    if path {
        A_Clipboard := path
        ToolTip("Copied: " path)
        SetTimer(HideTooltip, 2000)
    } else {
        ; No file selected — pass the hotkey through to other apps
        Send("^+c")
    }
}

GetSelectedFilePath() {
    hwnd := WinGetID("A")
    winClass := WinGetClass("A")

    ; Handle Explorer windows and Desktop
    if (winClass ~= "^(CabinetWClass|ExploreWClass|Progman|WorkerW)$") {
        for window in ComObject("Shell.Application").Windows {
            if (winClass ~= "^(Progman|WorkerW)$") {
                ; Desktop
                if (window.HWND = 0)
                    continue
                try {
                    if (window.Document.Folder.Self.Path = A_Desktop
                        || window.Document.Folder.Self.Path = A_Desktop "\..\Public\Desktop") {
                        items := window.Document.SelectedItems
                        if (items.Count > 0)
                            return items.Item(0).Path
                    }
                }
                continue
            }
            ; Regular Explorer window
            try {
                if (window.HWND = hwnd) {
                    items := window.Document.SelectedItems
                    if (items.Count > 0)
                        return items.Item(0).Path
                }
            }
        }
    }

    ; Handle common file dialogs (Open/Save dialogs)
    if (winClass = "#32770") {
        try {
            ctrl := ControlGetFocus("A")
            if (ctrl ~= "SysListView") {
                ; Get the folder path from the address bar area
                folderPath := ControlGetText("ToolbarWindow323", "A")
                if !folderPath {
                    ; Try the edit field for the file name
                    fileName := ControlGetText("Edit1", "A")
                    if fileName
                        return fileName
                }
            }
        }
    }

    return ""
}

HideTooltip() {
    ToolTip()
    SetTimer(HideTooltip, 0)
}
