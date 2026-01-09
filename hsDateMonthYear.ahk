#Requires AutoHotkey v2.0
#SingleInstance Force


; #HotIf WinActive("ahk_class #32770")
;
; ::ddmm::
; {
;   SendText FormatTime(A_Now, "ddMMMyyyyHHmm")
; }
;
; #HotIf



IsSaveFileDialog() {
  return WinActive("ahk_class CabinetWClass")
}

#HotIf IsSaveFileDialog()

::ddmm::
{
    SendText FormatTime(A_Now, "ddMMMyyyyHHmm")
}

#HotIf

; ---------------------------------------------------
; Save File Dialogue detection
; ---------------------------------------------------
; IsSaveFileDialog() {
;   ; Standard Windows Save/Open dialogs
;   if !WinActive("ahk_class #32770")
;     return false
;
;   ; Filename edit must be focused
;   try {
;     ctrl := ControlGetFocus("A")
;     ; Accept any Edit control, not just Edit1
;     return InStr(ctrl, "Edit")
;   }
;   catch {
;     return false
;   }
; }

; HotIf (*) => IsSaveFileDialog()
; ; HotIfWinActive "ahk_class #32770"
; ; #HotIf IsSaveFileDialog()
; ; ; ---------------------------------------------------
; ; ; Hotstring: ddmm -> ddmmmyyyy
; ; ; ---------------------------------------------------
; ; ::ddmm::
; ; {
; ;   formatted := FormatTime(A_Now, "ddMMMyyyy")
; ;   SendText formatted
; ; }
; ; #HotIf
;
;
;
; ; HotIfWinActive
; HotIf
