#Requires AutoHotkey v2.0
#SingleInstance Force
;22Jan
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
idleMs := 5000
logFile := A_ScriptDir "\keys.log"

keys := []
idleTimer := 0
modeTimeline := []  ; array of objects: {mode, keyIndex}
modeTimeline.Push({ mode: "NORMAL", keyIndex: 1 })
keyIndex := 0

currentMode := "NORMAL"
opTimerMs := 1000       ; operator window

lastInsertKey := ""
lastInsertTick := 0
comboWindowMs := 1000
lastNormalKey := ""

pendingOperator := "" ; "", "c", "d", "y", "g"
pendingCount := ""  ; "", "2", "10", etc.
pendingMotion := "" ; "", "i", "a", "f", "t", ...
pendingCtrl := false

visualType := ""  ; "CHAR" | "LINE" | "BLOCK"
visualPendingMotion := "" ; "", "i", "a", "f", "t", ...
visualPendingCount := "" ; "", "2", "10", etc.

OPERATORS := Map(
	"c", true,
	"d", true,
	"y", true,
	"g", true
)

DIRECT_MOTIONS := Map(
	"h", true, "H", true, "j", true, "k", true, "l", true,
	"w", true, "L", true, "b", true, "e", true, "G", true,
	"W", true, "M", true, "B", true, "E", true, "{", true,
	"$", true, "^", true, "0", true, "}", true
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
	"i", Map("w", 1, "W", 1, "b", 1, "B", 1, "p", 1, "s", 1, "(", 1, ")", 1, "{", 1, "}", 1, "[", 1, "]", 1, ">", 1, "<", 1, "`"", 1, "'", 1, "``", 1),
	"a", Map("w", 1, "W", 1, "b", 1, "B", 1, "p", 1, "s", 1, "(", 1, ")", 1, "{", 1, "}", 1, "[", 1, "]", 1, ">", 1, "<", 1, "`"", 1, "'", 1, "``", 1, "m", 1, "M", 1),
	"g", Map("0", 1, "^", 1, "_", 1, "$", 1, "g", 1, "j", 1, "k", 1, "e", 1, "E", 1, "w", 1, "W", 1, "o", 1)
)

VISUAL_INSERT_OPERATORS := Map("c", true, "C", true, "I", true, "A", true)
VISUAL_EXIT_OPERATORS := Map("d", true, "y", true, "x", true, "<", true, ">", true, "=", true, "u", true)

; ===============================================

; ================= RESET TRACKER VARIABLES ======================
resetPendingTrackers() {
	global pendingOperator, pendingCount, pendingMotion
	pendingOperator := ""
	pendingCount := ""
	pendingMotion := ""
}

resetVisualStateTrackers() {
	global visualPendingMotion, visualPendingCount, visualType
	visualPendingCount := ""
	visualPendingMotion := ""
	visualType := ""
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
			} else if (pendingMotion = 'f' || pendingMotion = 'F' || pendingMotion = 't' || pendingMotion = 'T') {
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
	global currentMode, VISUAL_EXIT_OPERATORS

	if (currentMode != "INSERT" && currentMode != "VISUAL")
		return false

	if (key = "<Esc>" || key = "<C-[>" || key = "<C-c>") {
		SetMode("NORMAL")
		resetPendingTrackers()
		resetVisualStateTrackers()
		return true
	}

	if (currentMode = "VISUAL") {
		if (VISUAL_EXIT_OPERATORS.Has(key)) {
			resetVisualStateTrackers()
			setMode("NORMAL")
			return true
		}
	}

	return false
}

; ==================================================

; ======================== INSERT TO NORMAL COMBO KEYS DETECTOR ========================

Handle_InsertToNormal_Combo(key) {
	global currentMode, lastInsertKey, lastInsertTick, comboWindowMs, modeTimeline
	if (currentMode != "INSERT")
		return false

	now := A_TickCount

	if (lastInsertKey = "j" && key = "k") {
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

; ======================== VISUAL TO NORMAL COMBO KEYS DETECTOR ========================

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
setVisualModeType(key) {
	global visualType
	if (key = "v") {
		visualType := "CHAR"
	}
	if (key = "V") {
		visualType := "LINE"
	}
	if (key = "<C-v>") {
		visualType := "BLOCK"
	}
}

toggleVisualMode(key) {
	global currentMode, visualType

	if (key = "v") {
		if (visualType = "CHAR") {
			SetMode("NORMAL")
			resetVisualStateTrackers()
			return true
		}
		setVisualModeType(key)
		return false
	}

	if (key = "V") {
		if (visualType = "LINE") {
			SetMode("NORMAL")
			resetVisualStateTrackers()
			return true
		}
		setVisualModeType(key)
		return false
	}

	if (key = "<C-v>") {
		if (visualType = "BLOCK") {
			SetMode("NORMAL")
			resetVisualStateTrackers()
			return true
		}
		setVisualModeType(key)
		return false
	}
}

HandleNormalToVisual(key) {
	global currentMode

	if (currentMode != "NORMAL")
		return false

	if (key = "v" || key = "V" || key = "<C-v>") {
		setVisualModeType(key)
		setMode("VISUAL")
		return true
	}

	return false
}

HandleVisualExpansion(key) {
	global currentMode, visualPendingCount, visualPendingMotion, visualType
	global DIRECT_MOTIONS, COUNTS, MOTION_STARTERS, MOTION_COMPLETIONS
	global VISUAL_EXIT_OPERATORS, VISUAL_INSERT_OPERATORS

	if (currentMode != "VISUAL") {
		return false
	}

	if (key = "o" || key = "O") {
		return false
	}

	; Visual to Visual keys

	if (key = "v" || key = "V" || key = "<C-v>") {
		if (toggleVisualMode(key)) {
			return true
		}
		return false
	}

	if (visualPendingMotion = "" && MOTION_STARTERS.Has(key)) {
		visualPendingMotion := key
		return false
	}

	; ---------------- DIRECT MOTIONS ----------------
	if (DIRECT_MOTIONS.Has(key)) {
		visualPendingMotion := ""
		visualPendingCount := ""
		return false
	}

	; Visual to Normal keys

	if (VISUAL_EXIT_OPERATORS.Has(key) && visualPendingMotion = "") {
		SetMode("NORMAL")
		resetVisualStateTrackers()
		return true
	}

	if (visualPendingMotion != "") {

		; for ip and ap
		if (MOTION_COMPLETIONS.Has(visualPendingMotion) && MOTION_COMPLETIONS[visualPendingMotion].Has(key)) {
			if ((visualPendingMotion = "i" || visualPendingMotion = "a") && key = "p") {
				toggleVisualMode("V")
			}
			return false
		}
		visualPendingMotion := ""
		visualPendingCount := ""
		return false
	}

	; Visual to Insert keys
	; key = I/A/c/C, visualPendingMotion = ""
	if (visualPendingMotion = "") {
		if (VISUAL_INSERT_OPERATORS.Has(key)) {
			SetMode("INSERT")
			resetVisualStateTrackers()
			return true
		}
	}

	; ---------------- COUNT ACCUMULTION ----------------
	if (COUNTS.Has(key)) {
		; bare 0 is motion, not count
		if (key != 0 || visualPendingCount != "") {
			visualPendingCount .= key
			return FALSE
		}
		; else fall through -> treat 0 as motion
	}

	resetVisualStateTrackers()
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
	; VISUAL Expansion
	if (HandleVisualExpansion(char))
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

for k in [
	"-",
	"=",
	"[",
	"]",
	"\",
	";",
	"'",
	",",
	".",
	"/",
	"``"
] {
	Hotkey "~*" k, LogPhysical.Bind(k)
}

LogPhysical(key, *) {
	global shiftMap
	shifted := GetKeyState("Shift", "P")
	char := shifted ? shiftMap.Get(key, key) : key
	LogKey(char)
	if (Handle_ToNormal_Immediate(char))
		return

	if (HandleVisualExpansion(char))
		return

	if (Handle_VisualToNormal_Combo(char))
		return

	if (HandleNormalToVisual(char))
		return

	if (HandleNormalToInsert(char))
		return
}
; ----------------------------------------

; ---------- SPECIAL KEYS ----------
Hotkey "~*Space", (*) => LogKey("<Space>")
Hotkey "~*Enter", (*) => LogKey("<Enter>")
Hotkey "~*Backspace", (*) => LogKey("<BS>")
Hotkey "~*Tab", (*) => LogKey("<Tab>")
Hotkey "~*Ctrl", (*) => LogKey("<Ctrl>")
Hotkey "~*Alt", (*) => LogKey("<Alt>")
Hotkey "~*LWin", (*) => LogKey("<Win>")
Hotkey "~*RWin", (*) => LogKey("<Win>")

; ---------------------------------
Hotkey "~*Escape", (*) => (
	LogKey("<Esc>"),
	Handle_ToNormal_Immediate("<Esc>")
	; HandleInsertToNormal_Immediate("<Esc>"),
)

Hotkey "~*^[", (*) => (
	; HandleInsertToNormal_Immediate("<C-[>"),
	LogKey("<C-[>"),
	Handle_ToNormal_Immediate("<C-[>")
)

Hotkey "~*^c", (*) => (
	; HandleInsertToNormal_Immediate("<C-[>"),
	LogKey("<C-c>"),
	Handle_ToNormal_Immediate("<C-c>")
)

Hotkey "~*^o", (*) => (
	; HandleInsertToNormal_Immediate("<C-[>"),
	LogKey("<C-o>"),
	HandleNormalToInsert("<C-o>")
)

HotIf
