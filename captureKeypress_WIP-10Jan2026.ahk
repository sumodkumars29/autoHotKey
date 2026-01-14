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
pendingCtrl := false

OPERATORS := Map(
  "c", true,
  "d", true,
  "y", true,
  "g", true
)

DIRECT_MOTIONS := Map(
  "h", true, "j", true, "k", true, "l", true,
  "w", true, "b", true, "e", true, "G", true,
  "W", true, "B", true, "E", true,
  "$", true, "^", true, "0", true
)

MOTION_STARTERS := Map(
  "i", true, "a", true,
  "f", true, "F", true,
  "t", true, "T", true,
  "s", true, "g", true
)

IMMEDIATE_INSERT := Map(
  "i", true, "I", true,
  "a", true, "A", true,
  "o", true, "O", true,
  "C", true, "R", true, "r", true
)

COUNTS := Map(
  "0", true, "1", true, "2", true, "3", true, "4", true,
  "5", true, "6", true, "7", true, "8", true, "9", true
)

; MOTION_COMPLETIONS := Map(
;   "i", Array("w","W","b","B","(",")","{","}","[","]","<",">","`"","'","``"),
;   "a", Array("w","W","b","B","(",")","{","}","[","]","<",">","`"","'","``")
; )


MOTION_COMPLETIONS := Map(
  "i", Map("w",1,"W",1,"b",1,"B",1,"p",1,"s",1,"(",1,")",1,"{",1,"}",1,"[",1,"]",1,">",1,"<",1,"`"",1,"'",1,"``",1),
  "a", Map("w",1,"W",1,"b",1,"B",1,"p",1,"s",1,"(",1,")",1,"{",1,"}",1,"[",1,"]",1,">",1,"<",1,"`"",1,"'",1,"``",1),
  "g", Map("0",1,"^",1,"_",1,"$",1,"g",1,"j",1,"k",1,"e",1,"E",1,"w",1,"W",1,"o",1)
)
; ===============================================

; ================= RESET TRACKER VARIABLES ======================
resetPendingTrackers() {
  global pendingOperator, pendingCount, pendingMotion
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

; ================= NORMAL -> INSERT DETECTOR ======================; ========= NORMAL/INSERT MODE TRACKING (FROZEN v1.0) =========
; Last reviewed: [10 Jan 2026]
; Coverage: ~95% of personal use cases
; Known exclusions: Insert-mode helpers (completion, registers),
;                   g operators beyond gi/gI (handled separately),
;                   Virtual replace (to be handled with Replace modes)

HandleNormalToInsert(key) {
  global currentMode, pendingOperator, pendingCount, pendingMotion, pendingCtrl
  global OPERATORS, COUNTS, DIRECT_MOTIONS, IMMEDIATE_INSERT, MOTION_STARTERS, MOTION_COMPLETIONS

  if currentMode != "NORMAL"
    return FALSE

  if (key = "<Esc>" || key = "<C-[>") {
    resetPendingTrackers()
    return FALSE
  }

  if (key = "<C-o>") {
    resetPendingTrackers()
    return FALSE
  }

  if (key = "d" && pendingOperator = "d") {
    resetPendingTrackers()
    return FALSE
   }

  ; --------------- -IMMEDIATE INSERT (no pending operator) ----------------
  if (pendingOperator = "" && IMMEDIATE_INSERT.Has(key)) {
    SetMode("INSERT")
    resetPendingTrackers()
    return TRUE
  }

  if (key = "c" && pendingMotion = "" && pendingOperator = "c") {
    SetMode("INSERT")
    resetPendingTrackers()
    return TRUE
   }

  ; if the motion is this - >  g{i, I}
  if (pendingOperator = "g" && (key = "i" || key = "I")) {
    SetMode("INSERT")
    resetPendingTrackers()
    return TRUE
  }


  ; ---------------- COMPLETE PENDING MOTION ----------------
  ; cfx / ctx / cix / cax / cFx / cTx -> this key completes the motion and triggers INSERT mode

  ; if (pendingOperator != "" && pendingMotion = "s") {
  ;   resetPendingTrackers()
  ;   return FALSE
  ; }

  if (pendingMotion != "") {
    if (pendingOperator = "c") {
      ; for i and a
      if (MOTION_COMPLETIONS.Has(pendingMotion) && MOTION_COMPLETIONS[pendingMotion].Has(key)) {
      ; if (MOTION_COMPLETIONS.Has(pendingMotion)) {
      ;   for _, v in MOTION_COMPLETIONS[pendingMotion]{
      ;     if (v = key) {
        SetMode("INSERT")
        resetPendingTrackers()
        return TRUE
        }
      else if (pendingMotion = 'f' || pendingMotion = 'F' || pendingMotion = 't' || pendingMotion = 'T'){
        ; for f, F, t and T
        SetMode("INSERT")
        resetPendingTrackers()
        return FALSE
      }
    }
    ; d / y / g operators -> no INSERT
    resetPendingTrackers()
    return FALSE
  }

; ---------------- MOTION STARTERS (NEED ONE MORE KEY) ----------------
  if (MOTION_STARTERS.Has(key) && pendingOperator != "") {
    pendingMotion := key
    return FALSE
  }



  ; ---------------- OPERATOR START ----------------
  if (OPERATORS.Has(key)) {
    pendingOperator := key
    pendingCount := ""
    pendingMotion := ""
    return FALSE
  }

  ; ---------------- COUNT ACCUMULTION ----------------
  if (COUNTS.Has(key)) {
    ; bare 0 is motion, not count
    if (key != 0 || pendingCount != "") {
      pendingCount .= key
      return FALSE
    }
    ; else fall through -> treat 0 as motion
  }

  ; ---------------- DIRECT MOTIONS ----------------
  if (DIRECT_MOTIONS.Has(key)) {
    if (pendingOperator = "c") {
      SetMode("INSERT")
        resetPendingTrackers()
        return TRUE
    }

    ; d/y/g motions
    resetPendingTrackers()
    return FALSE
  }

  ; ---------------- FALLBACK ----------------
  resetPendingTrackers()
  return FALSE
}

; ==================================================

; ================== INSERT/VISUAL TO NORMAL DETECTOR ==============
Handle_ToNormal_Immediate(key) {
  global currentMode

  if (currentMode != "INSERT" && currentMode != "VISUAL")
    return false

  if (key = "<Esc>" || key = "<C-[>" || key = "<C-c>") {
    SetMode("NORMAL")
    return true
  }

  if (currentMode = "VISUAL" && key = "v") {
    SetMode("NORMAL")
    return true
  }

  return false
}

; ------------------------ INSERT TO NORMAL COMBO KEYS DETECTOR -------------------------------------
Handle_InsertToNormal_Combo(key) {
global currentMode, lastInsertKey, lastInsertTick, comboWindowMs, modeTimeline
  if (currentMode != "INSERT")
    return false

  now := A_TickCount

  if ( lastInsertKey = "j" && key = "k") {
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

; ------------------------ VISUAL TO NORMAL COMBO KEYS DETECTOR -------------------------------------
Handle_VisualToNormal_Combo(key) {
global currentMode, lastInsertKey, lastInsertTick, comboWindowMs, modeTimeline
  if (currentMode != "VISUAL")
    return false

  now := A_TickCount

  if (lastInsertKey = "k" && key = "j") {
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
; HandleVisualToNormal(key) {
;   global currentMode
;   if (currentMode != "VISUAL")
;     return false
;   if (key = "<Esc>" || key = "v") {
;     setMode("NORMAL")
;     return true
;   }
;   return false
; }
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
shiftMap["``"] := "~"

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
    ; to NORMAL from INSERT or VISUAL
    if (Handle_ToNormal_Immediate(char))
      return
    ; VISUAL to NORMAL combo
    if (Handle_VisualToNormal_Combo(char))
      return
    ; INSERT to NORMAL combo
    if (Handle_InsertToNormal_Combo(char))
      return
    ;NORMAL to VISUAL
    if (HandleNormalToVisual(char))
      return
    ; NORMAL to INSERT
    if (HandleNormalToInsert(char))
      return

}
; ---------------------------------

; ---------- NUMBERS & SYMBOLS ----------
for k in StrSplit("1234567890") {
    Hotkey "~*" k, LogPhysical.Bind(k)
}

for k in ["-", "=", "[", "]", "\", ";", "'", ",", ".", "/", "``"] {
    Hotkey "~*" k, LogPhysical.Bind(k)
}

LogPhysical(key, *) {
    global shiftMap
    shifted := GetKeyState("Shift", "P")
    char := shifted ? shiftMap.Get(key, key) : key
    LogKey(char)
    if (HandleNormalToVisual(char))
      return
    if (HandleNormalToInsert(char))
      return
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
  LogKey("<Esc>"),
  if (Handle_ToNormal_Immediate("<Esc>"))
    return
  ; HandleInsertToNormal_Immediate("<Esc>"),
)


Hotkey "~*^[", (*) => (
  ; HandleInsertToNormal_Immediate("<C-[>"),
  LogKey("<C-[>"),
  if (Handle_ToNormal_Immediate("<C-[>"))
    return
)

Hotkey "~*^c", (*) => (
  ; HandleInsertToNormal_Immediate("<C-[>"),
  LogKey("<C-c>"),
  if (Handle_ToNormal_Immediate("<C-c>"))
    return
)

Hotkey "~*^o", (*) => (
  ; HandleInsertToNormal_Immediate("<C-[>"),
  LogKey("<C-o>"),
  if (HandleNormalToInsert("<C-o>"))
    return
)

HotIf

