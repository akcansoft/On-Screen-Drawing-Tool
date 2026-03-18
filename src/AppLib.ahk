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
			MaxHistorySize: 200
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
			OrthoMode: "F8"
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
	lastUsed := { W: 0, A: -1, C: "" }

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
						}
					} catch {
						; Skip malformed values; defaults are already set above
					}
				}
			}
		}

		this.hotkeys := {
			toggle: AppConfig.Defaults.Hotkeys.ToggleDrawingMode,
			exit: AppConfig.Defaults.Hotkeys.ExitApp,
			clear: AppConfig.Defaults.Hotkeys.ClearDrawing,
			undo: AppConfig.Defaults.Hotkeys.UndoDrawing,
			redo: AppConfig.Defaults.Hotkeys.RedoDrawing,
			incLine: AppConfig.Defaults.Hotkeys.IncreaseLineWidth,
			decLine: AppConfig.Defaults.Hotkeys.DecreaseLineWidth,
			help: AppConfig.Defaults.Hotkeys.HotkeysHelp,
			ortho: AppConfig.Defaults.Hotkeys.OrthoMode
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
						}
					} catch {
						; Skip malformed hotkey entries; defaults remain
					}
				}
			}
		}

		iniLastUsed := IniRead(App.iniPath, "LastUsed", , "")
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
							case "LineWidth": this.lastUsed.W := Integer(val)
							case "DrawAlpha": this.lastUsed.A := Integer(val)
							case "Color": this.lastUsed.C := val
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
		this.maxHistorySize := Max(this.maxHistorySize, 10)  ; At least 10 undo steps

		if (this.lastUsed.W >= this.line.minWidth && this.lastUsed.W <= this.line.maxWidth)
			this.line.width := this.lastUsed.W
		if (this.lastUsed.A >= 0 && this.lastUsed.A <= 255)
			this.drawAlpha := this.lastUsed.A
		if (this.lastUsed.C != "") {
			try {
				this.lastUsedColorRGB := Integer(this.lastUsed.C)
				this.hasLastUsedColor := true
			}
		}

		this.colors.Load()
	}

	static _ParseBool(val) {
		val := StrLower(Trim(val))
		return (val = "1" || val = "true" || val = "yes" || val = "on")
	}

	Save() {
		try {
			IniWrite(this.line.minWidth, App.iniPath, "Settings", "MinLineWidth")
			IniWrite(this.line.maxWidth, App.iniPath, "Settings", "MaxLineWidth")
			IniWrite(this.drawAlpha, App.iniPath, "Settings", "DrawAlpha")
			IniWrite(this.frameIntervalMs, App.iniPath, "Settings", "FrameIntervalMs")
			IniWrite(this.minPointStep, App.iniPath, "Settings", "MinPointStep")
			IniWrite(this.maxHistorySize, App.iniPath, "Settings", "MaxHistorySize")
			IniWrite(this.clearOnExitDraw ? "true" : "false", App.iniPath, "Settings", "ClearOnExitDraw")
			IniWrite(this.showColorHints ? "true" : "false", App.iniPath, "Settings", "ShowColorHints")
			IniWrite(this.saveLastUsed ? "true" : "false", App.iniPath, "Settings", "SaveLastUsedOnExit")
			IniWrite(this.showHelpOnStartup ? "true" : "false", App.iniPath, "Settings", "showHelpOnStartup")

			IniWrite(this.hotkeys.toggle, App.iniPath, "Hotkeys", "ToggleDrawingMode")
			IniWrite(this.hotkeys.exit, App.iniPath, "Hotkeys", "ExitApp")
			IniWrite(this.hotkeys.clear, App.iniPath, "Hotkeys", "ClearDrawing")
			IniWrite(this.hotkeys.undo, App.iniPath, "Hotkeys", "UndoDrawing")
			IniWrite(this.hotkeys.redo, App.iniPath, "Hotkeys", "RedoDrawing")
			IniWrite(this.hotkeys.incLine, App.iniPath, "Hotkeys", "IncreaseLineWidth")
			IniWrite(this.hotkeys.decLine, App.iniPath, "Hotkeys", "DecreaseLineWidth")
			IniWrite(this.hotkeys.help, App.iniPath, "Hotkeys", "HotkeysHelp")
			IniWrite(this.hotkeys.ortho, App.iniPath, "Hotkeys", "OrthoMode")

			IniDelete(App.iniPath, "Colors")
			for c in this.colors.List
				IniWrite(Format("0x{:06X}", c.val), App.iniPath, "Colors", c.hk)
		} catch Error as e {
			MsgBox("Failed to save settings: " e.Message, "Error", 48)
		}
	}

	; Saves the last used drawing settings (called on exit).
	WriteLastUsed(currentColorARGB) {
		if (!this.saveLastUsed)
			return
		try {
			IniWrite(this.line.width, App.iniPath, "LastUsed", "LineWidth")
			IniWrite(this.drawAlpha, App.iniPath, "LastUsed", "DrawAlpha")
			IniWrite(Format("0x{:06X}", currentColorARGB & 0xFFFFFF), App.iniPath, "LastUsed", "Color")
		}
	}
}

; Helper to reset font for a given GUI across the app
_ResetUISettingsFont(guiObj) {
	guiObj.SetFont("s9 w400", "Segoe UI")
}

; Safe GUI existence check helper
_GuiExists(guiObj) {
	if (!IsObject(guiObj))
		return false
	try {
		return WinExist("ahk_id " guiObj.Hwnd)
	} catch {
		return false
	}
}

; Safe Hwnd getter - returns 0 if GUI doesn't exist
_SafeHwnd(guiObj) {
	if (!IsObject(guiObj))
		return 0
	try {
		return guiObj.Hwnd
	} catch {
		return 0
	}
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

SignedInt16(v) {
	v := v & 0xFFFF
	return (v & 0x8000) ? (v - 0x10000) : v
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