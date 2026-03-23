#Requires AutoHotkey v2.0
; =============================================================================
; Help & About Window
; =============================================================================
ShowHelp(*) {
	if (state.textMode)
		return

	if (_GuiExists(ui.helpGui)) {
		try {
			if (state.drawingMode)
				DisableDrawingCursor()
			_ManageDrawToolbar("hide")
			_OnAppSettingsClose()
			ui.helpGui.Show()
			return
		}
	}

	_ManageDrawToolbar("hide")
	_OnAppSettingsClose()

	if (state.drawingMode)
		DisableDrawingCursor()

	ownerHwnd := _SafeHwnd(ui.overlayGui)
	ui.helpGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox" (ownerHwnd ? " +Owner" ownerHwnd : ""), App.helpWinTitle)
	ui.helpGui.OnEvent("Close", _OnHelpClose)
	ui.helpGui.OnEvent("Escape", _OnHelpClose)

	ui.helpGui.SetFont("s11 bold")
	ui.helpGui.AddText("y+5", App.Name " v" App.Version)

	_ResetUISettingsFont(ui.helpGui)
	_txt := "A lightweight on-screen drawing tool for annotating the screen with lines, rectangles, ellipses, "
	_txt .= "circles, arrows, freehand drawings, solid background fills, and on-screen text."
	ui.helpGui.AddText("y+5 w350", _txt)
	_txt := "©2026 Mesut Akcan | makcan@gmail.com`n"
	_txt .= '<a href="' App.githubRepo '">GitHub Repository </a> | <a href="https://github.com/akcansoft">GitHub</a> | '
	_txt .= '<a href="https://mesutakcan.blogspot.com">Blog</a> | <a href="https://youtube.com/mesutakcan">YouTube</a>'
	ui.helpGui.AddLink("y+10 w350", _txt)

	ui.helpGui.SetFont("s10 bold")
	ui.helpGui.AddText("Section", "Hotkeys:")
	_ResetUISettingsFont(ui.helpGui)

	edtSearch := ui.helpGui.AddEdit("x+10 ys-3 w250 BackgroundFFFFEF vHkSearch")
	SendMessage(0x1501, 1, StrPtr("Search..."), edtSearch.Hwnd) ; EM_SETCUEBANNER

	ui.helpGui.SetFont("s10", "Segoe MDL2 Assets")
	btnClear := ui.helpGui.AddButton("x+2 yp w30 h24", Chr(0xE894)) ; Clear
	_ResetUISettingsFont(ui.helpGui)

	lv := ui.helpGui.AddListView("xs y+5 w350 r18 -Multi +Grid +NoSortHdr vHkListView", ["Action", "Hotkey(s)"])

	hkList := []
	if (cfg.hotkeys.help)
		hkList.Push(["Show this help", FormatHotkeyLabel(cfg.hotkeys.help)])
	hkList.Push(["Toggle drawing mode", FormatHotkeyLabel(cfg.hotkeys.toggle)])
	if (cfg.hotkeys.exit)
		hkList.Push(["Exit app", FormatHotkeyLabel(cfg.hotkeys.exit)])
	if (cfg.hotkeys.clear)
		hkList.Push(["Clear drawing", FormatHotkeyLabel(cfg.hotkeys.clear)])
	hkList.Push(["Toggle Ortho mode (Line/Arrow)", FormatHotkeyLabel(cfg.hotkeys.ortho)])

	hkList.Push(["Draw Line", "Shift"])
	hkList.Push(["Draw Rect", "Ctrl"])
	hkList.Push(["Draw Ellipse", "Alt"])
	hkList.Push(["Draw Circle", "Ctrl+Alt"])
	hkList.Push(["Draw Arrow", "Ctrl+Shift"])

	if (cfg.hotkeys.undo)
		hkList.Push(["Undo last shape", FormatHotkeyLabel(cfg.hotkeys.undo)])
	if (cfg.hotkeys.redo)
		hkList.Push(["Redo last shape", FormatHotkeyLabel(cfg.hotkeys.redo)])
	if (cfg.hotkeys.incLine)
		hkList.Push(["Increase line width", FormatHotkeyLabel(cfg.hotkeys.incLine)])
	if (cfg.hotkeys.decLine)
		hkList.Push(["Decrease line width", FormatHotkeyLabel(cfg.hotkeys.decLine)])

	hkList.Push(["Line width +/-", "WheelUp/Down"])
	hkList.Push(["Draw Toolbar", "Right click"])
	hkList.Push(["Undo last shape", "Mouse Back"])
	hkList.Push(["Redo last shape", "Mouse Forward"])

	; ── Text mode ──────────────────────────────────────────────────────────────
	if (cfg.hotkeys.text)
		hkList.Push(["Enter text mode", FormatHotkeyLabel(cfg.hotkeys.text)])
	if (cfg.hotkeys.exitText)
		hkList.Push(["Exit text mode", FormatHotkeyLabel(cfg.hotkeys.exitText) " or click outside"])
	if (cfg.hotkeys.decTextSize)
		hkList.Push(["Decrease text size", FormatHotkeyLabel(cfg.hotkeys.decTextSize)])
	if (cfg.hotkeys.incTextSize)
		hkList.Push(["Increase text size", FormatHotkeyLabel(cfg.hotkeys.incTextSize)])
	if (cfg.hotkeys.cycleTextCol)
		hkList.Push(["Cycle text color", FormatHotkeyLabel(cfg.hotkeys.cycleTextCol)])
	hkList.Push(["Text: place cursor", "Left click"])
	hkList.Push(["Text: new line", "Enter"])
	; ───────────────────────────────────────────────────────────────────────────

	colorKeys := ""
	for item in cfg.colors.List
		colorKeys .= (colorKeys = "" ? FormatHotkeyLabel(item.hk) : ", " FormatHotkeyLabel(item.hk))
	if (colorKeys != "") {
		hkList.Push(["Set draw color", colorKeys])
		fillModLabel := ""
		for i, v in _FillModValues {
			if (v = cfg.fillModifier) {
				fillModLabel := _FillModLabels[i]
				break
			}
		}
		if (fillModLabel = "")
			fillModLabel := cfg.fillModifier
		hkList.Push(["Fill background with color", fillModLabel " + color key"])
	}

	ui.helpGui.hkList := hkList
	_FilterHelpList()

	edtSearch.OnEvent("Change", (*) => _FilterHelpList())
	btnClear.OnEvent("Click", (*) => (ui.helpGui["HkSearch"].Value := "", _FilterHelpList(), ui.helpGui["HkSearch"].Focus()))

	_ResetUISettingsFont(ui.helpGui)
	chkStartup := ui.helpGui.AddCheckbox("y+10 Checked" cfg.showHelpOnStartup,
		"Show this on startup")
	chkStartup.OnEvent("Click", (*) => SaveWelcomeSettings(chkStartup.Value))

	btnOk := ui.helpGui.AddButton("w100 xm+85 Default", "OK")
	btnOk.OnEvent("Click", _OnHelpClose)
	btnSettings := ui.helpGui.AddButton("w100 x+5", App.settingsWinTitle)
	btnSettings.OnEvent("Click", ShowAppSettings)
	ControlFocus(btnOk)
	ui.helpGui.Show()
	_SetAppIcon(ui.helpGui.Hwnd, App.helpIcon.file, App.helpIcon.idx)
}

_OnHelpClose(*) {
	if (_GuiExists(ui.helpGui))
		ui.helpGui.Hide()
	if (state.drawingMode && _GuiExists(ui.overlayGui))
		EnableDrawingCursor()
}

_FilterHelpList() {
	if (!IsObject(ui.helpGui) || !ui.helpGui.Hwnd)
		return

	lv := ui.helpGui["HkListView"]
	query := Trim(StrLower(ui.helpGui["HkSearch"].Value))

	lv.Opt("-Redraw")
	lv.Delete()

	for row in ui.helpGui.hkList {
		if (query = "" || InStr(StrLower(row[1]), query) || InStr(StrLower(row[2]), query)) {
			lv.Add("", row[1], row[2])
		}
	}
	lv.ModifyCol(1, 175)
	lv.Opt("+Redraw")
}