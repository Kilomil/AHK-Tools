#Requires AutoHotkey v2.0
#SingleInstance Force
; Ctrl+Shift+V -> Save clipboard content to Desktop\Pasted Files
^+v:: {
    folder := A_Desktop "\Pasted Files"
    if !DirExist(folder)
        DirCreate(folder)
    timestamp := FormatTime(, "yyyy-MM-dd_HHmmss")
    ; --- Try image first (bitmap on clipboard) ---
    if DllCall("IsClipboardFormatAvailable", "UInt", 2) {   ; CF_BITMAP = 2
        outPath := folder "\" timestamp ".png"
        SaveClipboardImage(outPath)
        OpenAndSelectFile(outPath)
        return
    }
    ; --- Fall back to text ---
    txt := A_Clipboard
    if (txt != "") {
        outPath := folder "\" timestamp ".txt"
        FileAppend(txt, outPath, "UTF-8")
        TrayTip("Pasted Files", "Text saved: " outPath)
        OpenAndSelectFile(outPath)
        return
    }
    TrayTip("Pasted Files", "Clipboard is empty or unsupported format.")
}
; ---------------------------------------------------------------
; Open the parent folder and highlight the saved file.
;  - If the folder is already open in Explorer: focus the window
;    and select the file via Shell COM.
;  - Otherwise: run  explorer /select,"<path>"  which does both.
; ---------------------------------------------------------------
OpenAndSelectFile(filePath) {
    SplitPath(filePath, &fileName, &folderPath)
    folderPath := RTrim(folderPath, "\")
    try {
        shell := ComObject("Shell.Application")
        windows := shell.Windows()
        for win in windows {
            try {
                url := win.LocationURL
                if (url = "")
                    continue
                decoded := RTrim(UrlToPath(url), "\")
                if (decoded = folderPath) {             ; = is case-insensitive in AHK v2
                    DllCall("SetForegroundWindow", "Ptr", win.HWND)
                    ; Select (highlight) the file inside the already-open window
                    try {
                        fv := win.Document              ; IShellFolderViewDual
                        item := fv.Folder.ParseName(fileName)
                        if (item) {
                            ; 0x1D = SVSI_SELECT | SVSI_DESELECTOTHERS | SVSI_ENSUREVISIBLE | SVSI_FOCUSED
                            fv.SelectItem(item, 0x1D)
                        }
                    }
                    return
                }
            }
        }
    }
    ; No existing window – explorer /select opens the folder AND highlights the file
    Run('explorer.exe /select,"' filePath '"')
}
; Convert a file:/// URL to a local path
; e.g. "file:///C:/Foo%20Bar" -> "C:\Foo Bar"
UrlToPath(url) {
    url := RegExReplace(url, "^file:///", "")
    url := StrReplace(url, "/", "\")
    while RegExMatch(url, "%([0-9A-Fa-f]{2})", &m)
        url := StrReplace(url, m[0], Chr("0x" m[1]))
    return url
}
; ---------------------------------------------------------------
; Grab the CF_BITMAP from the clipboard and save it as PNG
; using GDI+ (no external dependencies).
; ---------------------------------------------------------------
SaveClipboardImage(filePath) {
    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    pToken := 0
    si := Buffer(24, 0)
    NumPut("UInt", 1, si, 0)
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &pToken, "Ptr", si, "Ptr", 0)
    if !DllCall("OpenClipboard", "Ptr", 0) {
        DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
        return
    }
    hBitmap := DllCall("GetClipboardData", "UInt", 2, "Ptr")
    if !hBitmap {
        DllCall("CloseClipboard")
        DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
        return
    }
    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP"
        , "Ptr", hBitmap, "Ptr", 0, "Ptr*", &pBitmap)
    DllCall("CloseClipboard")
    encoderCLSID := GetEncoderCLSID("image/png")
    DllCall("gdiplus\GdipSaveImageToFile"
        , "Ptr", pBitmap, "WStr", filePath, "Ptr", encoderCLSID, "Ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
    TrayTip("Pasted Files", "Image saved: " filePath)
}
; ---------------------------------------------------------------
; Enumerate GDI+ image encoders and return the CLSID Buffer
; for the given MIME type (e.g. "image/png").
;  stride = 76 (x86) / 104 (x64)
; ---------------------------------------------------------------
GetEncoderCLSID(mimeType) {
    numEncoders := 0
    size := 0
    DllCall("gdiplus\GdipGetImageEncodersSize"
        , "UInt*", &numEncoders, "UInt*", &size)
    buf := Buffer(size, 0)
    DllCall("gdiplus\GdipGetImageEncoders"
        , "UInt", numEncoders, "UInt", size, "Ptr", buf)
    stride  := (A_PtrSize = 8) ? 104 : 76
    mimeOff := 32 + A_PtrSize * 4
    loop numEncoders {
        base := stride * (A_Index - 1)
        pMime := NumGet(buf, base + mimeOff, "Ptr")
        if (StrGet(pMime, "UTF-16") = mimeType) {
            clsid := Buffer(16, 0)
            DllCall("RtlMoveMemory", "Ptr", clsid, "Ptr", buf.Ptr + base, "UInt", 16)
            return clsid
        }
    }
    return 0
}