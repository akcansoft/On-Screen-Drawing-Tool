#Requires AutoHotkey v2.0

; =============================================================================
; Help & About Window
; =============================================================================

ShowHelp(*) {
  global ui, cfg, App, state
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
  _txt .= "circles, arrows and freehand drawings."
  ui.helpGui.AddText("y+5 w350", _txt)
  _txt := "©2026 Mesut Akcan | makcan@gmail.com`n"
  _txt .= '<a href="' App.githubRepo '">GitHub Repository </a> | <a href="https://github.com/akcansoft">GitHub</a> | '
  _txt .= '<a href="https://mesutakcan.blogspot.com">Blog</a> | <a href="https://youtube.com/mesutakcan">YouTube</a>'
  ui.helpGui.AddLink("y+10 w350", _txt)

  ui.helpGui.SetFont("s10 bold")
  ui.helpGui.AddText(, "Hotkeys:")
  _ResetUISettingsFont(ui.helpGui)

  colorKeys := ""
  for item in cfg.colors.List
    colorKeys .= (colorKeys = "" ? FormatHotkeyLabel(item.hk) : ", " FormatHotkeyLabel(item.hk))

  lv := ui.helpGui.AddListView("y+5 w350 r15 -Multi +Grid +NoSortHdr", ["Action", "Hotkey(s)"])
  if (cfg.hotkeys.help)
    lv.Add("", "Show this help", FormatHotkeyLabel(cfg.hotkeys.help))
  lv.Add("", "Toggle drawing mode", FormatHotkeyLabel(cfg.hotkeys.toggle))
  if (cfg.hotkeys.exit)
    lv.Add("", "Exit app", FormatHotkeyLabel(cfg.hotkeys.exit))
  lv.Add("", "Toggle Ortho mode (Line/Arrow)", FormatHotkeyLabel(cfg.hotkeys.ortho))

  lv.Add("", "Draw Line", "Shift")
  lv.Add("", "Draw Rect", "Ctrl")
  lv.Add("", "Draw Ellipse", "Alt")
  lv.Add("", "Draw Circle", "Ctrl+Alt")
  lv.Add("", "Draw Arrow", "Ctrl+Shift")

  if (cfg.hotkeys.clear)
    lv.Add("", "Clear drawing", FormatHotkeyLabel(cfg.hotkeys.clear))
  if (cfg.hotkeys.undo)
    lv.Add("", "Undo last shape", FormatHotkeyLabel(cfg.hotkeys.undo))
  if (cfg.hotkeys.redo)
    lv.Add("", "Redo last shape", FormatHotkeyLabel(cfg.hotkeys.redo))
  if (cfg.hotkeys.incLine)
    lv.Add("", "Increase line width", FormatHotkeyLabel(cfg.hotkeys.incLine))
  if (cfg.hotkeys.decLine)
    lv.Add("", "Decrease line width", FormatHotkeyLabel(cfg.hotkeys.decLine))

  lv.Add("", "Line width +/-", "WheelUp/Down")
  lv.Add("", "Draw Toolbar", "Right click")
  lv.Add("", "Undo last shape", "Mouse Back")
  lv.Add("", "Redo last shape", "Mouse Forward")

  if (colorKeys != "")
    lv.Add("", "Color", colorKeys)

  lv.ModifyCol(1, 140)

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
}

_OnHelpClose(*) {
  global ui, state
  if (_GuiExists(ui.helpGui))
    ui.helpGui.Hide()
  if (state.drawingMode && _GuiExists(ui.overlayGui))
    EnableDrawingCursor()
}
