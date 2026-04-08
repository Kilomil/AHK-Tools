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
        return
    }
    ; --- Fall back to text ---
    txt := A_Clipboard
    if (txt != "") {
        outPath := folder "\" timestamp ".txt"
        FileAppend(txt, outPath, "UTF-8")
        TrayTip("Pasted Files", "Text saved: " outPath)
        return
    }
    TrayTip("Pasted Files", "Clipboard is empty or unsupported format.")
}
; ---------------------------------------------------------------
; Grab the CF_BITMAP from the clipboard and save it as PNG
; using GDI+ (no external dependencies).
; ---------------------------------------------------------------
SaveClipboardImage(filePath) {
    ; --- Load & start GDI+ ---
    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    pToken := 0
    si := Buffer(24, 0)
    NumPut("UInt", 1, si, 0)                       ; GdiplusVersion = 1
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &pToken, "Ptr", si, "Ptr", 0)
    ; --- Open clipboard and get HBITMAP ---
    if !DllCall("OpenClipboard", "Ptr", 0) {
        DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
        return
    }
    hBitmap := DllCall("GetClipboardData", "UInt", 2, "Ptr")   ; CF_BITMAP
    if !hBitmap {
        DllCall("CloseClipboard")
        DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
        return
    }
    ; --- Create GDI+ Bitmap from HBITMAP ---
    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP"
        , "Ptr", hBitmap, "Ptr", 0, "Ptr*", &pBitmap)
    DllCall("CloseClipboard")
    ; --- Look up the PNG encoder CLSID ---
    encoderCLSID := GetEncoderCLSID("image/png")
    ; --- Save to file ---
    DllCall("gdiplus\GdipSaveImageToFile"
        , "Ptr", pBitmap, "WStr", filePath, "Ptr", encoderCLSID, "Ptr", 0)
    ; --- Cleanup ---
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
    TrayTip("Pasted Files", "Image saved: " filePath)
}
; ---------------------------------------------------------------
; Enumerate GDI+ image encoders and return the CLSID Buffer
; for the given MIME type (e.g. "image/png").
;
; ImageCodecInfo layout  (x86 / x64):
;   0  : Clsid           16 bytes
;  16  : FormatID        16 bytes
;  32  : CodecName       ptr
;  32+1p: DllName        ptr
;  32+2p: FormatDesc     ptr
;  32+3p: FileExt        ptr
;  32+4p: MimeType       ptr
;  32+5p: Flags          4 bytes
;  ...  : (Version, SigCount, SigSize, SigPattern, SigMask)
;
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
    stride    := (A_PtrSize = 8) ? 104 : 76
    mimeOff   := 32 + A_PtrSize * 4            ; offset to MimeType pointer
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
