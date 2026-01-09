#Requires AutoHotkey v2.0
#SingleInstance Force

; ========= NEOVIM ONLY =========

IsNvimInWindowsTerminal() {
    if !WinActive("ahk_exe WindowsTerminal.exe")
        return false

    title := WinGetTitle("A")
    return RegExMatch(title, "i)nvim")
}

HotIf (*) => IsNvimInWindowsTerminal()

; ===============================================

; ================= CONFIG ======================
maxKeys := 30
idleMs  := 5000
logFile := A_ScriptDir "\keys.log"

keys := []
idleTimer := 0
modeTimeline := []  ; array of objects: {mode, keyIndex}
modeTimeline.Push({ mode: "NORMAL", keyIndex: 1 })
keyIndex := 0

currentMode := "NORMAL"
pendingOperator := "",  ; "", "c", "d", "y"
opTimerMs := 1000       ; operator window

lastInsertKey := ""
lastInsertTick := 0
comboWindowMs := 1000
lastNormalKey := ""

pendingOperator := "" ; "", "c", "d", "y", "g"
pendingCount := ""  ; "", "2", "10", etc.
pendingMotion := "" ; "", "i", "a", "f", "t", ...

; ===============================================

; ================= RESET TRACKER VARIABLES ======================
resetPendingTrackers() {
  pendingOperator := "" 
  pendingCount := ""  
  pendingMotion := "" 
}
; ===============================================

; ================= OPERATOR TIMEOUT (HARD RESET) ======================
ClearPendingOperator() {
  global pendingOperator
  pendingOperator := ""
}
; ===============================================

; ================= NORMAL -> INSERT DETECTOR ======================
HandleNormalToInsert(key) {
  global currentMode, pendingOperator, opTimerMs, lastNormalKey
  if currentMode != "NORMAL"
    return false

  ; ---- Unambiguous INSERT (single key) ----
  if (key ~= "^[IAO]$") { ; I, A and O
    SetMode("INSERT")
    pendingOperator := ""
    lastNormalKey := ""
    return true
  }

  ; ---- Line / replace variants ----
  if (key = "C" || key = "R") {
    SetMode("INSERT")
    pendingOperator := ""
    lastNormalKey := ""
    return true
  }

  ; ---- Operator starter -----
  if (key = "c") {
    ; detect cc
    if (lastNormalKey = "c") {
      setMode("INSERT")
      pendingOperator := ""
      lastNormalKey := ""
      return true
    }
    pendingOperator := "c"
    lastNormalKey := "c"
    SetTimer(ClearPendingOperator, 0)
    SetTimer(ClearPendingOperator, -opTimerMs)
    return false
  }

  ; ---- Ambiguous i / a ----
  if (key = "i" || key = "a") {
    if (pendingOperator = "d" || pendingOperator = "y") {
      pendingOperator := ""
      lastNormalKey := ""
      return false
    }
    setMode("INSERT")
    pendingOperator := ""
    lastNormalKey := ""
    return true
  }

  ; --- Anything else ---
  pendingOperator := ""
  lastNormalKey := ""
  return false
}

; ==================================================

; ================== INSERT TO NORMAL DETECTOR ==============
HandleInsertToNormal_Immediate(key) {
  global currentMode

  if (currentMode != "INSERT")
    return false

  if (key = "<Esc>" || key = "<C-[>") {
    SetMode("NORMAL")
    return true
  }

  return false
}

; ------------------------ INSERT TO NORMAL COMBO KEYS DETECTOR -------------------------------------
Handle_ToNormal_Combo(key) {
global currentMode, lastInsertKey, lastInsertTick, comboWindowMs, modeTimeline
  if (currentMode != "INSERT")
    return false

  now := A_TickCount

  if (
    (lastInsertKey = "j" && key = "k")
    || (lastInsertKey = "k" && key = "j")
  ) {
    if (now - lastInsertTick <= comboWindowMs) {
      SetMode("NORMAL", keyIndex + 1)
      lastInsertKey := ""
      lastInsertTick := 0
      return true
    }
  }
  ; update tracking
  lastInsertKey := key
  lastInsertTick := now
  return false
}

; ==================================================


; ================== NORMAL TO VISUAL DETECTOR ==============
HandleNormalToVisual(key) {
  global currentMode
  if (currentMode != "NORMAL")
    return false
  if (key = "v" || key = "V" || key = "<C-v>") {
    setMode("VISUAL")
    return true
  }
  return false
}
; ==================================================

; ================== VISUAL TO NORMAL DETECTOR ==============
HandleVisualToNormal(key) {
  global currentMode
  if (currentMode != "VISUAL")
    return false
  if (key = "<Esc>" || key = "v") {
    setMode("NORMAL")
    return true
  }
  return false
}
; ==================================================

; ================== CENTRALIZED MODE SWITCHING ==============

SetMode(newMode, effectiveIndex := "") {
  global currentMode, modeTimeline, keyIndex
  if (currentMode = newMode)
    return
  if (effectiveIndex = "")
    effectiveIndex := keyIndex + 1
  currentMode := newMode
  modeTimeline.Push({ mode: newMode, keyIndex: effectiveIndex })
}

; ==================================================

; outside any function
shiftMap := Map()

shiftMap["1"] := "!"
shiftMap["2"] := "@"
shiftMap["3"] := "#"
shiftMap["4"] := "$"
shiftMap["5"] := "%"
shiftMap["6"] := "^"
shiftMap["7"] := "&"
shiftMap["8"] := "*"
shiftMap["9"] := "("
shiftMap["0"] := ")"
shiftMap["-"] := "_"
shiftMap["="] := "+"
shiftMap["["] := "{"
shiftMap["]"] := "}"
shiftMap["\"] := "|"
shiftMap[";"] := ":"
shiftMap["'"] := '"'
shiftMap[","] := "<"
shiftMap["."] := ">"
shiftMap["/"] := "?"

; ---------- CORE LOGGER ----------
LogKey(char, *) {
    global keys, maxKeys, idleMs, idleTimer, keyIndex

    keyIndex++

    time := FormatTime(, "HH:mm:ss")
    entry := { index: keyIndex, time: time, char: char }
    keys.Push(entry)

    if (keys.Length > maxKeys)
        keys.RemoveAt(1)

    ; reset one-shot timer
    SetTimer(FlushKeys, 0)
    SetTimer(FlushKeys, -idleMs)
}


FlushKeys() {
    global keys, logFile, modeTimeline

    if (keys.Length = 0)
        return

    FileAppend("---- burst ----`n", logFile)

    ; Find starting mode
    startIndex := keys[1].index
    activeMode := "UNKNOWN"

    for m in modeTimeline {
      if (m.keyIndex <= startIndex)
        activeMode := m.mode
      else
        break
    }

    FileAppend("<MODE: " activeMode ">`n", logFile)

    timelinePos := 1
    while (
        timelinePos <= modeTimeline.Length
        && modeTimeline[timelinePos].keyIndex < startIndex
    ) {
        timelinePos++
    }

    for k in keys {
      ; advance mode if needed
      while (
        timelinePos <= modeTimeline.Length && modeTimeline[timelinePos].keyIndex = k.index
      ) {
        activeMode := modeTimeline[timelinePos].mode
        FileAppend("<MODE: " activeMode ">`n", logFile)
        timelinePos++
      }
      FileAppend(k.time " | " k.char "`n", logFile)
    }
    FileAppend("<MODE: " currentMode ">`n", logFile) 
    FileAppend("`n", logFile)

    keys := []   ; reset buffer after flush
    ; lastLoggedMode := ""  ; force mode header next time
}
; ----------------------------------

; ---------- LETTERS ----------
for k in StrSplit("abcdefghijklmnopqrstuvwxyz") {
    Hotkey "~*" k, LogLetter.Bind(k)
}

LogLetter(key, *) {

    shifted := GetKeyState("Shift", "P")
    char := shifted ? StrUpper(key) : key

    ; INSERT or VISUAL -> NORMAL detection
    LogKey(char)
    ; VISUAL exits first
    HandleVisualToNormal(char)
    ; INSERT exits
    Handle_ToNormal_Combo(char)
    ; VISUAL entry
    HandleNormalToVisual(char)
    ; INSERT entry
    HandleNormalToInsert(char)
}
; ---------------------------------

; ---------- NUMBERS & SYMBOLS ----------
for k in StrSplit("1234567890") {
    Hotkey "~*" k, LogPhysical.Bind(k)
}

for k in ["-", "=", "[", "]", "\", ";", "'", ",", ".", "/"] {
    Hotkey "~*" k, LogPhysical.Bind(k)
}

LogPhysical(key, *) {
    global shiftMap
    shifted := GetKeyState("Shift", "P")
    char := shifted ? shiftMap.Get(key, key) : key
    LogKey(char)
    HandleNormalToInsert(char)
}
; ----------------------------------------

; ---------- SPECIAL KEYS ----------
Hotkey "~*Space",     (*) => LogKey("<Space>")
Hotkey "~*Enter",     (*) => LogKey("<Enter>")
Hotkey "~*Backspace", (*) => LogKey("<BS>")
Hotkey "~*Tab",       (*) => LogKey("<Tab>")
Hotkey "~*Ctrl",      (*) => LogKey("<Ctrl>")
Hotkey "~*Alt",       (*) => LogKey("<Alt>")
Hotkey "~*LWin",      (*) => LogKey("<Win>")
Hotkey "~*RWin",      (*) => LogKey("<Win>")

; ---------------------------------
Hotkey "~*Escape", (*) => (
  HandleVisualToNormal("<Esc>"),
  HandleInsertToNormal_Immediate("<Esc>"),
  LogKey("<Esc>")
)


Hotkey "~*^[", (*) => (
  HandleInsertToNormal_Immediate("<C-[>"),
  LogKey("<C-[>")
)

HotIf

