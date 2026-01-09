#Requires AutoHotKey v2.0
#SingleInstance Force
Persistent

; ============================================
; WINDOW INSPECTOR FOR GLAZEWM DEBUGGING
; ============================================

; Hotkey: Ctrl + Alt + w

^!w::
{
  try {
    title := WinGetTitle("A")
    class := WinGetClass("A")
    process := WinGetProcessName("A")
    hwnd := WinGetID("A")

    MsgBox(
      "Active Window Info: `n`n"
      . "Title    : " title "`n"
      . "Class    : " class "`n"
      . "Process  : " process "`n"
      . "HWND     : " hwnd,
      "Window Inspector",
      "Iconi"
    )
  } catch Error as e {
    MsgBox("Failed to query active window.`n" e.Message)
  }
}

; Optional: exit hotkey
^!q::ExitApp
