#Requires AutoHotkey v2.0

class DrawingColors {
	static Defaults := [{ hk: "r", val: 0xFF0000 }, { hk: "g", val: 0x00FF00 }, { hk: "b", val: 0x0000FF }, { hk: "y",
		val: 0xFFFF00 }, { hk: "m", val: 0xFF00FF }, { hk: "c", val: 0x00FFFF }, { hk: "o", val: 0xFFA500 }, { hk: "v",
			val: 0x7F00FF }, { hk: "s", val: 0x8B4513 }, { hk: "w", val: 0xFFFFFF }, { hk: "n", val: 0x808080 }, { hk: "k",
				val: 0x000000 }
	]
	static List := []
	static Load() {
		this.List := []
		iniReadResult := IniRead(App.iniPath, "Colors", , "")

		if (iniReadResult != "") {
			for line in StrSplit(iniReadResult, "`n", "`r") {
				if (line = "")
					continue
				parts := StrSplit(line, "=", "", 2)
				if (parts.Length = 2) {
					hk := Trim(parts[1])
					try {
						cVal := Integer(Trim(parts[2]))
						this.List.Push({ hk: hk, val: cVal })
					}
				}
			}
		}

		if (this.List.Length = 0) {
			for item in this.Defaults
				this.List.Push({ hk: item.hk, val: item.val })
		}
	}
}

class AppConfig {
	static Defaults := {
		Settings: {
			MinLineWidth: 1,
			MaxLineWidth: 10,
			DrawAlpha: 200,
			FrameIntervalMs: 16,
			MinPointStep: 3,
			ClearOnExitDraw: false,
			ShowColorHints: true,
			SaveLastUsedOnExit: true,
			showHelpOnStartup: true,
			MaxHistorySize: 200,
			FillModifier: "+",
			; ── Text mode defaults ───────────────────────────────────────────
			TextFont: "Segoe UI",
			TextSize: 18,
			TextBold: false,
			TextItalic: false,
			TextUnderline: false
		},
		Hotkeys: {
			ToggleDrawingMode: "^F9",
			ExitApp: "^+F12",
			ClearDrawing: "Esc",
			UndoDrawing: "^z",
			RedoDrawing: "^y",
			IncreaseLineWidth: "^NumpadAdd",
			DecreaseLineWidth: "^NumpadSub",
			HotkeysHelp: "F1",
			OrthoMode: "F8",
			TextMode: "t", ; Enter text (typing) mode
			ExitTextMode: "Esc",
			DecreaseTextSize: "F2",
			IncreaseTextSize: "F3",
			CycleTextColor: "F4"
		}
	}

	line := {}
	drawAlpha := 0
	frameIntervalMs := 0
	minPointStep := 0
	maxHistorySize := 0
	clearOnExitDraw := false
	showColorHints := false
	saveLastUsed := false
	showHelpOnStartup := true
	fillModifier := "+"

	; ── Text mode settings ────────────────────────────────────────────────────
	text := {}   ; .font  .size  .bold  .italic  .underline

	hotkeys := {}

	lastUsedColorRGB := 0
	hasLastUsedColor := false

	colors := DrawingColors

	__New() {
		d := AppConfig.Defaults.Settings

		this.line.minWidth := d.MinLineWidth
		this.line.maxWidth := d.MaxLineWidth
		this.line.width := d.MinLineWidth
		this.drawAlpha := d.DrawAlpha
		this.frameIntervalMs := d.FrameIntervalMs
		this.minPointStep := d.MinPointStep
		this.maxHistorySize := d.MaxHistorySize
		this.clearOnExitDraw := d.ClearOnExitDraw
		this.showColorHints := d.ShowColorHints
		this.saveLastUsed := d.SaveLastUsedOnExit
		this.showHelpOnStartup := d.showHelpOnStartup
		this.fillModifier := d.FillModifier

		; ── Text mode defaults ───────────────────────────────────────────────
		this.text := {
			font: d.TextFont,
			size: d.TextSize,
			bold: d.TextBold,
			italic: d.TextItalic,
			underline: d.TextUnderline,
			charSet: 1   ; DEFAULT_CHARSET
		}

		iniSettings := IniRead(App.iniPath, "Settings", , "")
		if (iniSettings != "") {
			for line in StrSplit(iniSettings, "`n", "`r") {
				if (line = "")
					continue
				parts := StrSplit(line, "=", , 2)
				if (parts.Length = 2) {
					key := Trim(parts[1])
					val := Trim(parts[2])
					try {
						switch key {
							case "MinLineWidth": this.line.minWidth := Integer(val)
							case "MaxLineWidth": this.line.maxWidth := Integer(val)
							case "DrawAlpha": this.drawAlpha := Integer(val)
							case "FrameIntervalMs": this.frameIntervalMs := Integer(val)
							case "MinPointStep": this.minPointStep := Integer(val)
							case "MaxHistorySize": this.maxHistorySize := Integer(val)
							case "ClearOnExitDraw": this.clearOnExitDraw := AppConfig._ParseBool(val)
							case "ShowColorHints": this.showColorHints := AppConfig._ParseBool(val)
							case "SaveLastUsedOnExit": this.saveLastUsed := AppConfig._ParseBool(val)
							case "showHelpOnStartup": this.showHelpOnStartup := AppConfig._ParseBool(val)
							case "FillModifier":
								static validMods := Map("+", true, "^", true, "!", true, "#", true)
								if (validMods.Has(val))
									this.fillModifier := val
								; ── Text mode ────────────────────────────────────────────────
							case "TextFont":
								if (val != "")
									this.text.font := val
							case "TextSize":
								sz := Integer(val)
								if (sz >= 6 && sz <= 200)
									this.text.size := sz
							case "TextBold": this.text.bold := AppConfig._ParseBool(val)
							case "TextItalic": this.text.italic := AppConfig._ParseBool(val)
							case "TextUnderline": this.text.underline := AppConfig._ParseBool(val)
							case "TextCharSet":
								cs := Integer(val)
								if (cs >= 0 && cs <= 255)
									this.text.charSet := cs
						}
					} catch {
						; Skip malformed values; defaults are already set above
					}
				}
			}
		}

		hk := AppConfig.Defaults.Hotkeys
		this.hotkeys := {
			toggle: hk.ToggleDrawingMode,
			exit: hk.ExitApp,
			clear: hk.ClearDrawing,
			undo: hk.UndoDrawing,
			redo: hk.RedoDrawing,
			incLine: hk.IncreaseLineWidth,
			decLine: hk.DecreaseLineWidth,
			help: hk.HotkeysHelp,
			ortho: hk.OrthoMode,
			text: hk.TextMode,
			exitText: hk.ExitTextMode,
			decTextSize: hk.DecreaseTextSize,
			incTextSize: hk.IncreaseTextSize,
			cycleTextCol: hk.CycleTextColor
		}

		iniHotkeys := IniRead(App.iniPath, "Hotkeys", , "")
		if (iniHotkeys != "") {
			for line in StrSplit(iniHotkeys, "`n", "`r") {
				if (line = "")
					continue
				parts := StrSplit(line, "=", , 2)
				if (parts.Length = 2) {
					key := Trim(parts[1])
					val := Trim(parts[2])
					try {
						switch key {
							case "ToggleDrawingMode": this.hotkeys.toggle := val
							case "ExitApp": this.hotkeys.exit := val
							case "ClearDrawing": this.hotkeys.clear := val
							case "UndoDrawing": this.hotkeys.undo := val
							case "RedoDrawing": this.hotkeys.redo := val
							case "IncreaseLineWidth": this.hotkeys.incLine := val
							case "DecreaseLineWidth": this.hotkeys.decLine := val
							case "HotkeysHelp": this.hotkeys.help := val
							case "OrthoMode": this.hotkeys.ortho := val
							case "TextMode": this.hotkeys.text := val
							case "ExitTextMode": this.hotkeys.exitText := val
							case "DecreaseTextSize": this.hotkeys.decTextSize := val
							case "IncreaseTextSize": this.hotkeys.incTextSize := val
							case "CycleTextColor": this.hotkeys.cycleTextCol := val
						}
					} catch {
						; Skip malformed hotkey entries; defaults remain
					}
				}
			}
		}

		iniLastUsed := IniRead(App.iniPath, "LastUsed", , "")
		lastUsed := { W: 0, A: -1, C: "" }
		if (iniLastUsed != "") {
			for line in StrSplit(iniLastUsed, "`n", "`r") {
				if (line = "")
					continue
				parts := StrSplit(line, "=", , 2)
				if (parts.Length = 2) {
					key := Trim(parts[1])
					val := Trim(parts[2])
					try {
						switch key {
							case "LineWidth": lastUsed.W := Integer(val)
							case "DrawAlpha": lastUsed.A := Integer(val)
							case "Color": lastUsed.C := val
						}
					} catch {
						; Skip malformed last-used values; defaults remain
					}
				}
			}
		}

		this.line.minWidth := Max(this.line.minWidth, 1)
		if (this.line.maxWidth < this.line.minWidth)
			this.line.maxWidth := this.line.minWidth
		this.line.width := Max(Min(this.line.width, this.line.maxWidth), this.line.minWidth)
		this.drawAlpha := Max(Min(this.drawAlpha, 255), 0)
		this.frameIntervalMs := Max(this.frameIntervalMs, 1)
		this.minPointStep := Max(this.minPointStep, 1)
		this.maxHistorySize := Max(this.maxHistorySize, 10)

		if (lastUsed.W >= this.line.minWidth && lastUsed.W <= this.line.maxWidth)
			this.line.width := lastUsed.W
		if (lastUsed.A >= 0 && lastUsed.A <= 255)
			this.drawAlpha := lastUsed.A
		if (lastUsed.C != "") {
			try {
				this.lastUsedColorRGB := Integer(lastUsed.C)
				this.hasLastUsedColor := true
			}
		}

		this.colors.Load()
	}

	static _ParseBool(val) {
		val := StrLower(Trim(val))
		return (val = "1" || val = "true" || val = "yes" || val = "on")
	}

	_Write(value, section, key) => IniWrite(value, App.iniPath, section, key)

	Save() {
		try {
			this._Write(this.line.minWidth, "Settings", "MinLineWidth")
			this._Write(this.line.maxWidth, "Settings", "MaxLineWidth")
			this._Write(this.drawAlpha, "Settings", "DrawAlpha")
			this._Write(this.frameIntervalMs, "Settings", "FrameIntervalMs")
			this._Write(this.minPointStep, "Settings", "MinPointStep")
			this._Write(this.maxHistorySize, "Settings", "MaxHistorySize")
			this._Write(this.clearOnExitDraw ? "true" : "false", "Settings", "ClearOnExitDraw")
			this._Write(this.showColorHints ? "true" : "false", "Settings", "ShowColorHints")
			this._Write(this.saveLastUsed ? "true" : "false", "Settings", "SaveLastUsedOnExit")
			this._Write(this.showHelpOnStartup ? "true" : "false", "Settings", "showHelpOnStartup")
			this._Write(this.fillModifier, "Settings", "FillModifier")

			this._Write(this.text.font, "Settings", "TextFont")
			this._Write(this.text.size, "Settings", "TextSize")
			this._Write(this.text.bold ? "true" : "false", "Settings", "TextBold")
			this._Write(this.text.italic ? "true" : "false", "Settings", "TextItalic")
			this._Write(this.text.underline ? "true" : "false", "Settings", "TextUnderline")
			this._Write(this.text.charSet, "Settings", "TextCharSet")

			this._Write(this.hotkeys.toggle, "Hotkeys", "ToggleDrawingMode")
			this._Write(this.hotkeys.exit, "Hotkeys", "ExitApp")
			this._Write(this.hotkeys.clear, "Hotkeys", "ClearDrawing")
			this._Write(this.hotkeys.undo, "Hotkeys", "UndoDrawing")
			this._Write(this.hotkeys.redo, "Hotkeys", "RedoDrawing")
			this._Write(this.hotkeys.incLine, "Hotkeys", "IncreaseLineWidth")
			this._Write(this.hotkeys.decLine, "Hotkeys", "DecreaseLineWidth")
			this._Write(this.hotkeys.help, "Hotkeys", "HotkeysHelp")
			this._Write(this.hotkeys.ortho, "Hotkeys", "OrthoMode")
			this._Write(this.hotkeys.text, "Hotkeys", "TextMode")
			this._Write(this.hotkeys.exitText, "Hotkeys", "ExitTextMode")
			this._Write(this.hotkeys.decTextSize, "Hotkeys", "DecreaseTextSize")
			this._Write(this.hotkeys.incTextSize, "Hotkeys", "IncreaseTextSize")
			this._Write(this.hotkeys.cycleTextCol, "Hotkeys", "CycleTextColor")

			IniDelete(App.iniPath, "Colors")
			for c in this.colors.List
				this._Write(Format("0x{:06X}", c.val), "Colors", c.hk)
		} catch Error as e {
			MsgBox("Failed to save settings: " e.Message, "Error", 48)
		}
	}

	; Saves the last used drawing settings (called on exit).
	WriteLastUsed(currentColorARGB) {
		if (!this.saveLastUsed)
			return
		try {
			this._Write(this.line.width, "LastUsed", "LineWidth")
			this._Write(this.drawAlpha, "LastUsed", "DrawAlpha")
			this._Write(Format("0x{:06X}", currentColorARGB & 0xFFFFFF), "LastUsed", "Color")
		}
	}
}

; Helper to reset font for a given GUI across the app
_ResetUISettingsFont(guiObj) {
	guiObj.SetFont("s9 w400", "Segoe UI")
}

; Set icon on a GUI window from a DLL/EXE resource
_SetAppIcon(hwnd, iconFile, iconIdx) {
	try {
		hIcon := LoadPicture(iconFile, "Icon" iconIdx " w32 h32", &imgType)
		if (hIcon) {
			SendMessage(0x0080, 1, hIcon, , "ahk_id " hwnd)  ; WM_SETICON large
			SendMessage(0x0080, 0, hIcon, , "ahk_id " hwnd)  ; WM_SETICON small
		}
	}
}

; Safe GUI existence check helper
_GuiExists(guiObj) {
	if (!guiObj)
		return 0
	if (!IsObject(guiObj) || !guiObj.HasProp("Hwnd") || !guiObj.Hwnd)
		return 0
	return WinExist("ahk_id " guiObj.Hwnd)
}

; Safe Hwnd getter - returns 0 if GUI doesn't exist
_SafeHwnd(guiObj) {
	if (!guiObj)
		return 0
	return (IsObject(guiObj) && guiObj.HasProp("Hwnd")) ? guiObj.Hwnd : 0
}

; Helper to format hotkey labels for display (e.g. "^+F12" -> "Ctrl+Shift+F12")
FormatHotkeyLabel(hk) {
	if (hk = "")
		return ""
	label := StrReplace(hk, "+", "Shift+")
	label := StrReplace(label, "^", "Ctrl+")
	label := StrReplace(label, "!", "Alt+")
	label := StrReplace(label, "#", "Win+")
	return label
}

; Calculate perceived brightness for a color (0-255)
GetLuminance(rgb) {
	r := (rgb >> 16) & 0xFF
	g := (rgb >> 8) & 0xFF
	b := rgb & 0xFF
	return (0.299 * r) + (0.587 * g) + (0.114 * b)
}

InitDpiAwareness() {
	; Prefer per-monitor v2 so mixed monitor scale ratios map correctly.
	try {
		prev := DllCall("User32.dll\SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
		if (prev)
			return true
	} catch {
	}
	try {
		if DllCall("User32.dll\SetProcessDpiAwarenessContext", "Ptr", -4, "Int")
			return true
	} catch {
	}
	try {
		if (DllCall("Shcore.dll\SetProcessDpiAwareness", "Int", 2, "Int") = 0)
			return true
	} catch {
	}
	try {
		return DllCall("User32.dll\SetProcessDPIAware", "Int")
	} catch {
	}
	return false
}

LoadSystemCursor(cursorId) {
	static cursorCache := Map()
	if (!cursorCache.Has(cursorId)) {
		hCursor := DllCall("User32.dll\LoadCursor", "Ptr", 0, "Ptr", cursorId, "Ptr")
		cursorCache[cursorId] := hCursor
	}
	return cursorCache[cursorId]
}