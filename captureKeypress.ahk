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

; ===============================================

; ================= OPERATOR TIMEOUT (HARD RESET) ======================
ClearPendingOperator() {
  global pendingOperator
  pendingOperator := ""
}
; ===============================================

; ================= NORMAL -> INSERT DETECTOR ======================
HandleNormalToInsert(key) {
  global currentMode, pendingOperator, opTimerMs

  if (currentMode != "NORMAL")
    return false
  
  
  ; --- Operator starters ---
  if (key = "c" || key = "d"|| key = "y") {
    pendingOperator := key
    SetTimer(ClearPendingOperator, 0)
    SetTimer(ClearPendingOperator, -opTimerMs)
    return
  }

  ; --- Strong INSERT key (unambiguous) ---
  if (key ~= "^[IAOS]$" || key = "o" || key = "s") {
    SetMode("INSERT")
    pendingOperator := ""
    return true
  }

  ; --- Ambiguous INSERT keys (i / a) ---
  if (key = "i" || key = "a") {
    if (pendingOperator = "d" || pendingOperator = "y") {
      ; di / yi / da / ya -> NOT INSERT
      pendingOperator := ""
      return false
    }

    ; i / a / ci / ca -> INSERT
    SetMode("INSERT")
    pendingOperator := ""
    return true
  }

  ; --- Any other key clears operator ---
  pendingOperator := ""
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
    Handle_ToNormal_Combo(char)
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
  HandleInsertToNormal_Immediate("<Esc>"),
  LogKey("<Esc>")
)


Hotkey "~*^[", (*) => (
  HandleInsertToNormal_Immediate("<C-[>"),
  LogKey("<C-[>")
)

HotIf

