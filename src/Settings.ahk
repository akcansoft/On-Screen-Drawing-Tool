#Requires AutoHotkey v2.0

; Shared fill modifier values (AHK symbol → display order)
global _FillModValues := ["+", "^", "!", "#"]
global _FillModLabels := ["Shift", "Ctrl", "Alt", "Win"]

; Hotkey definitions: [cfg.hotkeys key, display label, AppConfig.Defaults.Hotkeys property]
; Single source of truth — used by _CreateAppSettingsGui, _AppSettingsOK, _AppSettingsReset
global _HK_DEFS := [
	["toggle", "Toggle Drawing Mode:", "ToggleDrawingMode"],
	["clear", "Clear Drawing:", "ClearDrawing"],
	["undo", "Undo:", "UndoDrawing"],
	["redo", "Redo:", "RedoDrawing"],
	["incLine", "Increase Line Width:", "IncreaseLineWidth"],
	["decLine", "Decrease Line Width:", "DecreaseLineWidth"],
	["ortho", "Ortho Mode (Line/Arrow):", "OrthoMode"],
	["text", "Text Mode:", "TextMode"],
	["exitText", "Exit Text Mode:", "ExitTextMode"],
	["decTextSize", "Decrease Text Size:", "DecreaseTextSize"],
	["incTextSize", "Increase Text Size:", "IncreaseTextSize"],
	["cycleTextCol", "Cycle Text Color:", "CycleTextColor"],
	["help", "Help:", "HotkeysHelp"],
	["exit", "Exit App:", "ExitApp"]
]

; App Settings Window
_IsAppSettingsOpen() {
	return IsObject(ui.appSettingsGui) && ui.appSettingsGui != ""
		&& WinExist("ahk_id " ui.appSettingsGui.Hwnd)
}

ShowAppSettings(*) {
	if (state.textMode)
		return

	if (IsObject(ui.appSettingsGui) && ui.appSettingsGui.Hwnd) {
		try ui.appSettingsGui.Show()
		return
	}
	if (state.drawingMode)
		DisableDrawingCursor()
	_OnHelpClose()
	_CreateAppSettingsGui()
}

_CreateAppSettingsGui() {
	ownerHwnd := (IsObject(ui.overlayGui) && ui.overlayGui != "") ? ui.overlayGui.Hwnd : 0
	win := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox" (ownerHwnd ? " +Owner" ownerHwnd : ""),
		App.Name " - " App.settingsWinTitle)
	_ResetUISettingsFont(win)
	win.OnEvent("Close", _OnAppSettingsClose)
	win.OnEvent("Escape", _OnAppSettingsClose)
	ui.appSettingsGui := win

	tabH := 370
	tabY := 8
	btnY := tabY + tabH + 10

	tabs := win.Add("Tab3", "xm ym w330 h" tabH, ["General", "Hotkeys", "Colors", "Text"])

	;  GENERAL TAB
	tabs.UseTab(1)

	settingRows := [
		["Min Line Width:", "MinLineWidth", cfg.line.minWidth, 1, 99],
		["Max Line Width:", "MaxLineWidth", cfg.line.maxWidth, 1, 99],
		["Draw Alpha (0-255):", "DrawAlpha", cfg.drawAlpha, 0, 255],
		["Frame Interval (ms):", "FrameIntervalMs", cfg.frameIntervalMs, 1, 500],
		["Min Point Step:", "MinPointStep", cfg.minPointStep, 1, 20],
		["Max History Size:", "MaxHistorySize", cfg.maxHistorySize, 10, 9999]
	]

	for i, row in settingRows {
		yOpt := (i = 1) ? "xm+15 y50" : "xm+15 y+7"
		win.Add("Text", yOpt " w130", row[1])
		win.Add("Edit", "v" row[2] " yp-3 x+5 w50 Number", row[3])
		win.Add("UpDown", "Range" row[4] "-" row[5], row[3])
	}

	win.Add("Checkbox", "vClearOnExitDraw xm+15 y+13 Checked" cfg.clearOnExitDraw,
		"Clear drawing when exiting drawing mode")
	win.Add("Checkbox", "vShowColorHints xm+15 y+6 Checked" cfg.showColorHints,
		"Show color hints in settings panel")
	win.Add("Checkbox", "vSaveLastUsed xm+15 y+6 Checked" cfg.saveLastUsed,
		"Save last used drawing properties on exit")
	win.Add("Checkbox", "vshowHelpOnStartup xm+15 y+6 Checked" cfg.showHelpOnStartup,
		"Show " App.helpWinTitle " on startup")

	;  HOTKEYS TAB
	tabs.UseTab(2)

	win.Add("Text", "xm+15 y40 w295 c808080",
		"Double-click a row to edit.`nSyntax: ^ = Ctrl + = Shift ! = Alt # = Win")

	lvHK := win.Add("ListView", "vHotkeyLV xm+5 y+8 w300 h260 -Multi Grid", ["Action", "Hotkey"])
	lvHK.ModifyCol(1, 160)
	for row in _HK_DEFS
		lvHK.Add("", row[2], cfg.hotkeys.%row[1]%)

	lvHK.ModifyCol(2, 110)
	lvHK.OnEvent("DoubleClick", (ctrl, row) => _EditHotkeyRow(ctrl, row))

	; win.Add("Button", "xm+5 y+6 w90", "Edit").OnEvent("Click", (*) => _EditHotkeyRow(lvHK, 0))

	win.Add("Text", "xm+5 y+10 w150", "Fill background modifier:")
	fillModSel := 1
	for i, v in _FillModValues {
		if (v = cfg.fillModifier) {
			fillModSel := i
			break
		}
	}
	win.Add("DropDownList", "vFillModifier x+5 yp-3 w80 Choose" fillModSel, _FillModLabels)

	;  COLORS TAB
	tabs.UseTab(3)

	win.Add("Text", "xm+15 y40 w295 c808080",
		"Double-click a row to edit.`nColor value: 6-digit hex without # (e.g. FF0000).")
	lv := win.Add("ListView", "vColorLV xm+5 y+8 w300 h260 -Multi Grid", ["Hotkey", "Color (Hex)"])
	lv.ModifyCol(1, "AutoHdr")
	for item in cfg.colors.List
		lv.Add("", item.hk, Format("{:06X}", item.val & 0xFFFFFF))

	lv.ModifyCol(2, "AutoHdr")
	lv.OnEvent("DoubleClick", (ctrl, row) => _EditColorRow(ctrl, row))

	win.Add("Button", "xm+5 y+6 w90", "Add").OnEvent("Click", (*) => _AddColorRow(lv))
	win.Add("Button", "x+5 yp w90", "Edit").OnEvent("Click", (*) => _EditColorRow(lv, 0))
	win.Add("Button", "x+5 yp w90", "Delete").OnEvent("Click", (*) => _DeleteColorRow(lv))

	;  TEXT TAB
	tabs.UseTab(4)

	win.Add("Text", "xm+15 y40 w295 c808080",
		"Press the text mode hotkey in drawing mode to enter typing mode."
		" Click anywhere to place text. Enter = new line."
		" Esc or click outside = commit and exit.")

	; Active font info row
	win.Add("Text", "xm+15 y+18 w85", "Active font:")
	fontInfoLabel := win.Add("Text", "x+5 yp w190 c0059ff",
		_MakeFontInfoStr(cfg.text.font, cfg.text.size, cfg.text.bold, cfg.text.italic, cfg.text.underline))

	; Font picker button
	win.Add("Button", "xm+15 y+12 w70", "Font...").OnEvent("Click",
		(*) => _OnFontButtonClick(win))

	; Sample text input
	win.Add("Text", "xm+15 y+14 w85", "Sample text:")
	_ResetUISettingsFont(win)
	sampleInput := win.Add("Edit", "xm+15 y+4 w290 Limit40", "Abc-ILMW,l1mw\ygtfi.02468@(){[]}*/+-")

	; Text sample rendered in the active font and active draw color
	;win.Add("Text", "xm+15 y+10 w85", "Preview:")
	drawColorHex := Format("{:06X}", draw.color & 0xFFFFFF)
	styleOpt := "s" cfg.text.size " c" drawColorHex " norm"
	styleOpt .= cfg.text.bold ? " bold" : ""
	styleOpt .= cfg.text.italic ? " italic" : ""
	styleOpt .= cfg.text.underline ? " underline" : ""
	sampleCtrl := win.Add("Edit", "xm+15 y+4 w290 h140 +Wrap ReadOnly -TabStop", sampleInput.Value)
	sampleCtrl.SetFont(styleOpt, cfg.text.font)

	sampleInput.OnEvent("Change", (*) => sampleCtrl.Text := sampleInput.Value)

	win._sampleInput := sampleInput

	; Store references and pending font state on the win object
	win._fontInfoLabel := fontInfoLabel
	win._sampleCtrl := sampleCtrl
	win._pendingFont := cfg.text.font
	win._pendingSize := cfg.text.size
	win._pendingBold := cfg.text.bold
	win._pendingItalic := cfg.text.italic
	win._pendingUnderline := cfg.text.underline
	win._pendingCharSet := cfg.text.charSet

	;  BOTTOM BUTTONS (shared across all tabs)
	tabs.UseTab()
	win.Add("Button", "xm+10 y" btnY " w80 Default", "OK").OnEvent("Click",
		(*) => _AppSettingsOK(win))
	win.Add("Button", "x+8 yp w80", "Cancel").OnEvent("Click", _OnAppSettingsClose)
	win.Add("Button", "x+8 yp w130", "Reset to Defaults").OnEvent("Click",
		(*) => _AppSettingsReset(win))

	win.Show("AutoSize Center")
	_SetAppIcon(win.Hwnd, App.settingsIcon.file, App.settingsIcon.idx)
}

_OnAppSettingsClose(*) {
	if (!IsObject(ui.appSettingsGui) || ui.appSettingsGui = "")
		return
	try ui.appSettingsGui.Destroy()
	ui.appSettingsGui := ""
	if (state.drawingMode && IsObject(ui.overlayGui) && ui.overlayGui != "")
		EnableDrawingCursor()
}

_AppSettingsOK(win) {
	sv := win.Submit(false)

	; Numeric fields: validate and clamp
	newMinW := Max(_SafeInt(sv.MinLineWidth, cfg.line.minWidth), 1)
	newMaxW := Max(_SafeInt(sv.MaxLineWidth, cfg.line.maxWidth), newMinW)
	newAlpha := Max(Min(_SafeInt(sv.DrawAlpha, cfg.drawAlpha), 255), 0)
	newFI := Max(_SafeInt(sv.FrameIntervalMs, cfg.frameIntervalMs), 1)
	newMPS := Max(_SafeInt(sv.MinPointStep, cfg.minPointStep), 1)
	newMHS := Max(_SafeInt(sv.MaxHistorySize, cfg.maxHistorySize), 10)

	; Hotkeys: read from ListView (empty = no hotkey)
	hotkeyChanged := false
	newHK := {}

	lvHK := win["HotkeyLV"]
	for i, pair in _HK_DEFS {
		newVal := Trim(lvHK.GetText(i, 2))
		newHK.%pair[1]% := newVal
		if (newVal != cfg.hotkeys.%pair[1]%)
			hotkeyChanged := true
	}

	; Validate hotkeys before applying
	invalidHotkeys := ""
	for i, pair in _HK_DEFS {
		newVal := newHK.%pair[1]%
		if (newVal = "")
			continue
		if (!_IsValidHotkey(newVal))
			invalidHotkeys .= (invalidHotkeys = "" ? "" : "`n") . pair[2] . " " . newVal
	}
	if (invalidHotkeys != "") {
		MsgBox("The following hotkeys are invalid and were not saved:`n`n" invalidHotkeys,
			"Invalid Hotkey(s)", "Iconi Owner" win.Hwnd)
		return
	}

	; Colors: collect from ListView
	lv := win["ColorLV"]
	newColors := []
	loop lv.GetCount() {
		hk := Trim(lv.GetText(A_Index, 1))
		hex := Trim(lv.GetText(A_Index, 2))
		if (hk != "" && StrLen(hex) = 6 && RegExMatch(hex, "i)^[0-9A-F]{6}$"))
			newColors.Push({ hk: hk, val: Integer("0x" hex) })
	}
	colorChanged := (newColors.Length != cfg.colors.List.Length)
	if (!colorChanged) {
		for i, c in newColors {
			if (c.hk != cfg.colors.List[i].hk || c.val != (cfg.colors.List[i].val & 0xFFFFFF)) {
				colorChanged := true
				break
			}
		}
	}

	; Apply numeric / checkbox settings to cfg
	cfg.line.minWidth := newMinW
	cfg.line.maxWidth := newMaxW
	cfg.line.width := Max(Min(cfg.line.width, newMaxW), newMinW)
	cfg.drawAlpha := newAlpha
	cfg.frameIntervalMs := newFI
	cfg.minPointStep := newMPS
	cfg.maxHistorySize := newMHS
	cfg.clearOnExitDraw := !!sv.ClearOnExitDraw
	cfg.showColorHints := !!sv.ShowColorHints
	cfg.saveLastUsed := !!sv.SaveLastUsed
	cfg.showHelpOnStartup := !!sv.showHelpOnStartup
	selIdx := win["FillModifier"].Value
	newFillMod := (selIdx >= 1 && selIdx <= _FillModValues.Length)
		? _FillModValues[selIdx] : cfg.fillModifier
	if (newFillMod != cfg.fillModifier)
		hotkeyChanged := true
	cfg.fillModifier := newFillMod
	for pair in _HK_DEFS
		cfg.hotkeys.%pair[1]% := newHK.%pair[1]%
	draw.color := ARGB(draw.color & 0xFFFFFF, cfg.drawAlpha)
	if (colorChanged)
		cfg.colors.List := newColors

	; Apply pending text font (set via Font... button)
	cfg.text.font := win._pendingFont
	cfg.text.size := win._pendingSize
	cfg.text.bold := win._pendingBold
	cfg.text.italic := win._pendingItalic
	cfg.text.underline := win._pendingUnderline
	cfg.text.charSet := win._pendingCharSet

	; Save all settings in one call
	cfg.Save()

	_OnAppSettingsClose()

	if (hotkeyChanged || colorChanged) {
		if (MsgBox("Hotkey or color changes require a restart to take effect.`nRestart now?",
			"Restart Required", "YesNo Icon!") = "Yes") {
			state.skipSaveSettings := true
			Reload()
		}
	}
}

; Safe integer conversion — returns default if conversion fails
_SafeInt(v, def) {
	return (v != "" && IsNumber(v)) ? Integer(v) : def
}

_IsValidHotkey(hk) {
	if (hk = "")
		return true
	; Strip leading modifiers: ^ (Ctrl) ! (Alt) + (Shift) # (Win) ~ * $
	key := RegExReplace(hk, "^[~*$^!+#]+")
	if (key = "")
		return false
	; Known special key names (partial list covering common keys)
	static specialKeys := "F1|F2|F3|F4|F5|F6|F7|F8|F9|F10|F11|F12"
		. "|F13|F14|F15|F16|F17|F18|F19|F20|F21|F22|F23|F24"
		. "|Numpad0|Numpad1|Numpad2|Numpad3|Numpad4|Numpad5|Numpad6|Numpad7|Numpad8|Numpad9"
		. "|NumpadDot|NumpadDiv|NumpadMult|NumpadAdd|NumpadSub|NumpadEnter|NumpadDel"
		. "|NumpadIns|NumpadClear|NumpadUp|NumpadDown|NumpadLeft|NumpadRight|NumpadHome|NumpadEnd|NumpadPgUp|NumpadPgDn"
		. "|Up|Down|Left|Right|Home|End|PgUp|PgDn|Insert|Delete|Backspace|Tab|Enter|Escape|Esc|Space|CapsLock"
		. "|ScrollLock|NumLock|PrintScreen|Pause|Break|AppsKey|Sleep"
		. "|LButton|RButton|MButton|XButton1|XButton2|WheelUp|WheelDown|WheelLeft|WheelRight"
		. "|LWin|RWin|LCtrl|RCtrl|LShift|RShift|LAlt|RAlt|LControl|RControl"
		. "|Browser_Back|Browser_Forward|Browser_Refresh|Browser_Stop|Browser_Search|Browser_Favorites|Browser_Home"
		. "|Volume_Mute|Volume_Down|Volume_Up|Media_Next|Media_Prev|Media_Stop|Media_Play_Pause"
		. "|Launch_Mail|Launch_Media|Launch_App1|Launch_App2"
		. "|SC[0-9A-Fa-f]+|VK[0-9A-Fa-f]+"
	; Single printable character (letter, digit, punctuation)
	if (StrLen(key) = 1)
		return true
	; Match against known special key names (case-insensitive)
	return RegExMatch(key, "i)^(" specialKeys ")$") > 0
}

_AppSettingsReset(win) {
	d := AppConfig.Defaults
	s := d.Settings
	h := d.Hotkeys

	win["MinLineWidth"].Value := s.MinLineWidth
	win["MaxLineWidth"].Value := s.MaxLineWidth
	win["DrawAlpha"].Value := s.DrawAlpha
	win["FrameIntervalMs"].Value := s.FrameIntervalMs
	win["MinPointStep"].Value := s.MinPointStep
	win["MaxHistorySize"].Value := s.MaxHistorySize
	win["ClearOnExitDraw"].Value := s.ClearOnExitDraw ? 1 : 0
	win["ShowColorHints"].Value := s.ShowColorHints ? 1 : 0
	win["SaveLastUsed"].Value := s.SaveLastUsedOnExit ? 1 : 0
	win["showHelpOnStartup"].Value := s.showHelpOnStartup ? 1 : 0
	win["FillModifier"].Value := 1 ; default: Shift

	; Reset hotkey ListView
	lvHK := win["HotkeyLV"]
	for i, row in _HK_DEFS
		lvHK.Modify(i, "", , h.%row[3]%)

	lv := win["ColorLV"]
	lv.Delete()
	for item in DrawingColors.Defaults
		lv.Add("", item.hk, Format("{:06X}", item.val & 0xFFFFFF))

	; Reset pending text font to defaults
	win._pendingFont := s.TextFont
	win._pendingSize := s.TextSize
	win._pendingBold := s.TextBold
	win._pendingItalic := s.TextItalic
	win._pendingUnderline := s.TextUnderline
	win._pendingCharSet := 1 ; DEFAULT_CHARSET

	; Update font info label and sample control on Text tab
	if (win.HasProp("_fontInfoLabel"))
		win._fontInfoLabel.Text := _MakeFontInfoStr(s.TextFont, s.TextSize,
			s.TextBold, s.TextItalic, s.TextUnderline)
	if (win.HasProp("_sampleCtrl")) {
		styleOpt := "s" s.TextSize " c" Format("{:06X}", draw.color & 0xFFFFFF) " norm"
		styleOpt .= s.TextBold ? " bold" : ""
		styleOpt .= s.TextItalic ? " italic" : ""
		styleOpt .= s.TextUnderline ? " underline" : ""
		win._sampleCtrl.SetFont(styleOpt, s.TextFont)
	}
}

; =============================================================================
; Hotkey listview helpers
; =============================================================================

_EditHotkeyRow(lv, rowNum := 0) {
	if (rowNum <= 0)
		rowNum := lv.GetNext(0)
	if (rowNum <= 0)
		return
	_ShowHotkeyEditDialog(lv, rowNum, lv.GetText(rowNum, 1), lv.GetText(rowNum, 2))
}

_ShowHotkeyEditDialog(lv, rowIndex, actionName, currentHk) {
	dlg := Gui("+AlwaysOnTop -MinimizeBox +Owner" ui.appSettingsGui.Hwnd, "Edit Hotkey")
	_ResetUISettingsFont(dlg)
	dlg.OnEvent("Close", (*) => dlg.Destroy())
	dlg.OnEvent("Escape", (*) => dlg.Destroy())

	dlg.Add("Text", "xm+15 ym+15 w200", actionName)
	dlg.Add("Text", "xm+15 y+10 w50", "Hotkey:")
	hkEdit := dlg.Add("Edit", "vHK x+5 yp-3 w120", currentHk)
	dlg.SetFont("s10", "Segoe MDL2 Assets")
	dlg.Add("Button", "x+4 yp w28 h22", Chr(0xE894)).OnEvent("Click", (*) => hkEdit.Value := "")
	_ResetUISettingsFont(dlg)
	dlg.Add("Button", "xm+15 y+15 w80 Default", "OK").OnEvent("Click",
		(*) => _HotkeyEditOK(dlg, lv, rowIndex, hkEdit))
	dlg.Add("Button", "x+8 yp w80", "Cancel").OnEvent("Click", (*) => dlg.Destroy())

	dlg.Show("AutoSize")
	hkEdit.Focus()
}

_HotkeyEditOK(dlg, lv, rowIndex, hkEdit) {
	hk := Trim(hkEdit.Value)
	if (hk != "" && !_IsValidHotkey(hk)) {
		MsgBox("The hotkey is invalid.", "Invalid Input", "Iconi")
		return
	}
	lv.Modify(rowIndex, "", , hk)
	dlg.Destroy()
}

; =============================================================================
; Color row edit helpers
; =============================================================================

_EditColorRow(lv, rowNum := 0) {
	if (rowNum <= 0)
		rowNum := lv.GetNext(0)
	if (rowNum <= 0)
		return
	_ShowColorEditDialog(lv, rowNum, lv.GetText(rowNum, 1), lv.GetText(rowNum, 2))
}

_AddColorRow(lv) {
	_ShowColorEditDialog(lv, 0, "", "FF0000")
}

_DeleteColorRow(lv) {
	rowNum := lv.GetNext(0)
	if (rowNum <= 0)
		return
	if (lv.GetCount() <= 1) {
		MsgBox("At least one color must remain.", "Cannot Delete", "Iconi")
		return
	}
	lv.Delete(rowNum)
}

_ShowColorEditDialog(lv, rowIndex, currentHk, currentHex) {
	dlg := Gui("+AlwaysOnTop -MinimizeBox +Owner" ui.appSettingsGui.Hwnd,
		rowIndex ? "Edit Color" : "Add Color")
	_ResetUISettingsFont(dlg)
	dlg.OnEvent("Close", (*) => dlg.Destroy())
	dlg.OnEvent("Escape", (*) => dlg.Destroy())

	dlg.Add("Text", "xm+15 ym+15 w90", "Hotkey:")
	hkEdit := dlg.Add("Edit", "vHK x+5 yp-3 w140", currentHk)

	dlg.Add("Text", "xm+15 y+12 w90", "Color (hex):")
	hexEdit := dlg.Add("Edit", "vHex x+5 yp-3 w80 Uppercase Limit6", currentHex)
	preview := dlg.Add("Text", "x+8 yp w30 h22 +Border Background"
		(StrLen(currentHex) = 6 ? currentHex : "FFFFFF"))
	btnPicker := dlg.Add("Button", "x+4 yp w26 h22", "...")
	btnPicker.OnEvent("Click", (*) => _OpenColorPicker(hexEdit, preview))

	hexEdit.OnEvent("Change", (*) => _UpdateColorPreview(hexEdit, preview))

	dlg.Add("Button", "xm+15 y+15 w80 Default", "OK").OnEvent("Click",
		(*) => _ColorEditOK(dlg, lv, rowIndex, hkEdit, hexEdit))
	dlg.Add("Button", "x+8 yp w80", "Cancel").OnEvent("Click", (*) => dlg.Destroy())

	dlg.Show("AutoSize")
	hkEdit.Focus()
}

_ColorEditOK(dlg, lv, rowIndex, hkEdit, hexEdit) {
	hk := Trim(hkEdit.Value)
	hex := StrUpper(Trim(hexEdit.Value))
	if (hk = "") {
		MsgBox("Hotkey cannot be empty.", "Invalid Input", "Iconi")
		return
	}
	if (StrLen(hex) != 6 || !RegExMatch(hex, "^[0-9A-F]{6}$")) {
		MsgBox("Color must be a 6-digit hex value (e.g. FF0000).", "Invalid Input", "Iconi")
		return
	}
	if (rowIndex = 0)
		lv.Add("", hk, hex)
	else
		lv.Modify(rowIndex, "", hk, hex)
	dlg.Destroy()
}

_UpdateColorPreview(hexEdit, preview) {
	hex := StrUpper(Trim(hexEdit.Value))
	if (StrLen(hex) = 6 && RegExMatch(hex, "^[0-9A-F]{6}$")) {
		preview.Opt("Background" hex)
		preview.Redraw()
	}
}

_OpenColorPicker(hexEdit, preview) {
	static custColors := [] ; persists custom colors across dialog opens

	hex := Trim(hexEdit.Value)
	initColor := 0
	if (StrLen(hex) = 6 && RegExMatch(hex, "i)^[0-9A-F]{6}$"))
		initColor := Integer("0x" hex)

	result := ColorDialog.Choose(initColor, ui.appSettingsGui.Hwnd, &custColors, true)
	if (result = -1)
		return ; user cancelled

	newHex := Format("{:06X}", result & 0xFFFFFF)
	hexEdit.Value := newHex
	_UpdateColorPreview(hexEdit, preview)
}

SaveWelcomeSettings(val) {
	cfg.showHelpOnStartup := val
	cfg.Save()
}

; =============================================================================
; Text tab helpers
; =============================================================================

; Build the font info string shown in the Text tab (e.g. "Segoe UI 18pt [Bold, Italic]").
_MakeFontInfoStr(font, size, bold, italic, underline) {
	info := font " " size "pt"
	styles := []
	if (bold)
		styles.Push("Bold")
	if (italic)
		styles.Push("Italic")
	if (underline)
		styles.Push("Underline")
	if (styles.Length) {
		joined := ""
		for i, s in styles
			joined .= (i > 1 ? ", " : "") s
		info .= " [" joined "]"
	}
	return info
}

; Called when the "Font..." button is clicked in the Text tab.
_OnFontButtonClick(win) {
	fn := win._pendingFont
	fs := win._pendingSize
	fb := win._pendingBold
	fi := win._pendingItalic
	fu := win._pendingUnderline
	fc := win._pendingCharSet

	if (!FontDialog.Choose(win.Hwnd, &fn, &fs, &fb, &fi, &fu, &fc))
		return ; user cancelled

	win._pendingFont := fn
	win._pendingSize := fs
	win._pendingBold := fb
	win._pendingItalic := fi
	win._pendingUnderline := fu
	win._pendingCharSet := fc

	win._fontInfoLabel.Text := _MakeFontInfoStr(fn, fs, fb, fi, fu)

	styleOpt := "s" fs " c" Format("{:06X}", draw.color & 0xFFFFFF) " norm"
	styleOpt .= fb ? " bold" : ""
	styleOpt .= fi ? " italic" : ""
	styleOpt .= fu ? " underline" : ""
	win._sampleCtrl.SetFont(styleOpt, fn)
}