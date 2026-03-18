#Requires AutoHotkey v2.0

; =============================================================================
; App Settings Window
; =============================================================================
_IsAppSettingsOpen() {
  global ui
  return IsObject(ui.appSettingsGui) && ui.appSettingsGui != ""
    && WinExist("ahk_id " ui.appSettingsGui.Hwnd)
}

ShowAppSettings(*) {
  global ui, state
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
  global ui, cfg, App, state

  ownerHwnd := (IsObject(ui.overlayGui) && ui.overlayGui != "") ? ui.overlayGui.Hwnd : 0
  win := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox" (ownerHwnd ? " +Owner" ownerHwnd : ""),
    App.Name " - " App.settingsWinTitle)
  _ResetUISettingsFont(win)
  win.OnEvent("Close", _OnAppSettingsClose)
  win.OnEvent("Escape", _OnAppSettingsClose)
  ui.appSettingsGui := win

  tabH := 330
  tabY := 8
  btnY := tabY + tabH + 10

  tabs := win.Add("Tab3", "xm ym w330 h" tabH, ["General", "Hotkeys", "Colors"])

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

  win.Add("Checkbox", "vClearOnExitDraw xm+15 y+13 Checked" cfg.clearOnExitDraw, "Clear drawing when exiting drawing mode")
  win.Add("Checkbox", "vShowColorHints xm+15 y+6  Checked" cfg.showColorHints, "Show color hints in settings panel")
  win.Add("Checkbox", "vSaveLastUsed xm+15 y+6  Checked" cfg.saveLastUsed, "Save last used drawing properties on exit")
  win.Add("Checkbox", "vshowHelpOnStartup xm+15 y+6  Checked" cfg.showHelpOnStartup, "Show " App.helpWinTitle " on startup")

  ; ── HOTKEYS TAB ──────────────────────────────────────────────────────────
  tabs.UseTab(2)

  win.Add("Text", "xm+15 y40 w440 c808080",
    "Syntax: ^ = Ctrl  + = Shift   ! = Alt   # = Win`n(e.g. ^F9 = Ctrl+F9)")

  hkData := [
    ["toggle", "Toggle Drawing Mode:"],
    ["exit", "Exit App:"],
    ["clear", "Clear Drawing:"],
    ["undo", "Undo:"],
    ["redo", "Redo:"],
    ["incLine", "Increase Line Width:"],
    ["decLine", "Decrease Line Width:"],
    ["ortho", "Ortho Mode (Line/Arrow):"],
    ["help", "Help:"]
  ]

  for i, row in hkData {
    yOpt := (i = 1) ? "xm+15 y+12" : "xm+15 y+8"
    win.Add("Text", yOpt " w150", row[2])
    win.Add("Edit", "v" row[1] "_hk yp-3 x+5 w140", cfg.hotkeys.%row[1]%)
  }

  ; ── COLORS TAB ───────────────────────────────────────────────────────────
  tabs.UseTab(3)

  win.Add("Text", "xm+15 y40 w430 c808080",
    "Double-click a row to edit.`nColor value: 6-digit hex without # (e.g. FF0000).")
  lv := win.Add("ListView", "vColorLV xm+5 y+8 w300 h220 -Multi", ["Hotkey", "Color (Hex)"])
  lv.ModifyCol(1, 80)
  lv.ModifyCol(2, 190)
  for item in cfg.colors.List
    lv.Add("", item.hk, Format("{:06X}", item.val & 0xFFFFFF))
  lv.OnEvent("DoubleClick", (ctrl, row) => _EditColorRow(ctrl, row))

  win.Add("Button", "xm+5 y+6 w90", "Add").OnEvent("Click", (*) => _AddColorRow(lv))
  win.Add("Button", "x+5  yp  w90", "Edit").OnEvent("Click", (*) => _EditColorRow(lv, 0))
  win.Add("Button", "x+5  yp  w90", "Delete").OnEvent("Click", (*) => _DeleteColorRow(lv))

  ; ── BOTTOM BUTTONS (shared across all tabs) ──────────────────────────────
  tabs.UseTab()
  win.Add("Button", "xm+10 y" btnY " w80 Default", "OK").OnEvent("Click", (*) => _AppSettingsOK(win))
  win.Add("Button", "x+8   yp          w80", "Cancel").OnEvent("Click", _OnAppSettingsClose)
  win.Add("Button", "x+8   yp         w130", "Reset to Defaults").OnEvent("Click", (*) => _AppSettingsReset(win))

  win.Show("AutoSize Center")
}

_OnAppSettingsClose(*) {
  global ui, state
  if (!IsObject(ui.appSettingsGui) || ui.appSettingsGui = "")
    return
  try ui.appSettingsGui.Destroy()
  ui.appSettingsGui := ""
  if (state.drawingMode && IsObject(ui.overlayGui) && ui.overlayGui != "")
    EnableDrawingCursor()
}

_AppSettingsOK(win) {
  global cfg, App, state, draw

  sv := win.Submit(false)

  ; ── Numeric fields: validate and clamp
  newMinW := Max(_SafeInt(sv.MinLineWidth, cfg.line.minWidth), 1)
  newMaxW := Max(_SafeInt(sv.MaxLineWidth, cfg.line.maxWidth), newMinW)
  newAlpha := Max(Min(_SafeInt(sv.DrawAlpha, cfg.drawAlpha), 255), 0)
  newFI := Max(_SafeInt(sv.FrameIntervalMs, cfg.frameIntervalMs), 1)
  newMPS := Max(_SafeInt(sv.MinPointStep, cfg.minPointStep), 1)
  newMHS := Max(_SafeInt(sv.MaxHistorySize, cfg.maxHistorySize), 10)

  ; ── Hotkeys: read from Edit controls (empty = no hotkey)
  hkFields := [
    ["toggle", "ToggleDrawingMode"],
    ["exit", "ExitApp"],
    ["clear", "ClearDrawing"],
    ["undo", "UndoDrawing"],
    ["redo", "RedoDrawing"],
    ["incLine", "IncreaseLineWidth"],
    ["decLine", "DecreaseLineWidth"],
    ["ortho", "OrthoMode"],
    ["help", "HotkeysHelp"]
  ]
  hotkeyChanged := false
  newHK := {}
  for pair in hkFields {
    newVal := Trim(win[pair[1] "_hk"].Value)
    newHK.%pair[1]% := newVal
    if (newVal != cfg.hotkeys.%pair[1]%)
      hotkeyChanged := true
  }

  ; ── Validate hotkeys before applying
  invalidHotkeys := ""
  for pair in hkFields {
    newVal := newHK.%pair[1]%
    if (newVal = "")
      continue
    if (!_IsValidHotkey(newVal))
      invalidHotkeys .= (invalidHotkeys = "" ? "" : "`n") . pair[2] . ": " . newVal
  }
  if (invalidHotkeys != "") {
    MsgBox("The following hotkeys are invalid and were not saved:`n`n" invalidHotkeys, "Invalid Hotkey(s)", "Iconi Owner" win.Hwnd)
    return
  }

  ; ── Colors: collect from ListView
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

  ; ── Apply to cfg
  cfg.line.minWidth := newMinW
  cfg.line.maxWidth := newMaxW
  cfg.line.width := Max(Min(cfg.line.width, newMaxW), newMinW)  ; clamp current width to new bounds
  cfg.drawAlpha := newAlpha
  cfg.frameIntervalMs := newFI
  cfg.minPointStep := newMPS
  cfg.maxHistorySize := newMHS
  cfg.clearOnExitDraw := !!sv.ClearOnExitDraw
  cfg.showColorHints := !!sv.ShowColorHints
  cfg.saveLastUsed := !!sv.SaveLastUsed
  cfg.showHelpOnStartup := !!sv.showHelpOnStartup
  for pair in hkFields
    cfg.hotkeys.%pair[1]% := newHK.%pair[1]%
  draw.color := ARGB(draw.color & 0xFFFFFF, cfg.drawAlpha)
  if (colorChanged)
    cfg.colors.List := newColors

  ; ── Save all settings in one call
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

  ; Reset hotkey Edit controls
  win["toggle_hk"].Value := h.ToggleDrawingMode
  win["exit_hk"].Value := h.ExitApp
  win["clear_hk"].Value := h.ClearDrawing
  win["undo_hk"].Value := h.UndoDrawing
  win["redo_hk"].Value := h.RedoDrawing
  win["incLine_hk"].Value := h.IncreaseLineWidth
  win["decLine_hk"].Value := h.DecreaseLineWidth
  win["ortho_hk"].Value := h.OrthoMode
  win["help_hk"].Value := h.HotkeysHelp

  lv := win["ColorLV"]
  lv.Delete()
  for item in DrawingColors.Defaults
    lv.Add("", item.hk, Format("{:06X}", item.val & 0xFFFFFF))
}

; ── Color row edit helpers ───────────────────────────────────────────────────
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
  global ui
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
  global ui
  static custColors := []  ; persists custom colors across dialog opens

  hex := Trim(hexEdit.Value)
  initColor := 0
  if (StrLen(hex) = 6 && RegExMatch(hex, "i)^[0-9A-F]{6}$"))
    initColor := Integer("0x" hex)

  result := _ColorSelect(initColor, ui.appSettingsGui.Hwnd, &custColors, true)
  if (result = -1)
    return  ; user cancelled

  newHex := Format("{:06X}", result & 0xFFFFFF)
  hexEdit.Value := newHex
  _UpdateColorPreview(hexEdit, preview)
}

; Opens the Windows color picker dialog.
; Color: initial color as 0xRRGGBB (default 0 = black)
; hwnd: parent window handle
; custColorObj: &VarRef to an Array of up to 16 custom colors (0xRRGGBB), persisted across calls
; fullPanel: true = show custom colors panel, false = basic panel only
; Returns selected color as integer (0xRRGGBB), or -1 if cancelled.
_ColorSelect(Color := 0, hwnd := 0, &custColorObj := "", fullPanel := true) {
  static p := A_PtrSize
  flags := fullPanel ? 0x3 : 0x1  ; CC_RGBINIT | CC_FULLOPEN  or  CC_RGBINIT only

  if (!IsObject(custColorObj))
    custColorObj := []
  if (custColorObj.Length > 16)
    throw Error("Too many custom colors. Maximum is 16.")
  loop (16 - custColorObj.Length)
    custColorObj.Push(0)

  CUSTOM := Buffer(16 * 4, 0)
  loop 16 {
    NumPut("UInt", _RGB2BGR(custColorObj[A_Index]), CUSTOM, (A_Index - 1) * 4)
  }

  ; CHOOSECOLORW struct — real sizes: x86=36 bytes, x64=72 bytes
  CHOOSECOLOR := Buffer((p = 4) ? 36 : 72, 0)
  NumPut("UInt", CHOOSECOLOR.Size, CHOOSECOLOR, 0)      ; lStructSize
  NumPut("UPtr", hwnd, CHOOSECOLOR, p)      ; hwndOwner
  NumPut("UInt", _RGB2BGR(Color), CHOOSECOLOR, 3 * p)  ; rgbResult (BGR)
  NumPut("UPtr", CUSTOM.Ptr, CHOOSECOLOR, 4 * p)  ; lpCustColors
  NumPut("UInt", flags, CHOOSECOLOR, 5 * p)  ; Flags

  if !DllCall("comdlg32\ChooseColorW", "UPtr", CHOOSECOLOR.Ptr, "UInt")
    return -1

  ; Read back custom colors
  custColorObj := []
  loop 16 {
    custColorObj.Push(_RGB2BGR(NumGet(CUSTOM, (A_Index - 1) * 4, "UInt")))
  }

  return _RGB2BGR(NumGet(CHOOSECOLOR, 3 * p, "UInt"))
}

; Swaps R and B channels: RGB <-> BGR
_RGB2BGR(c) {
  return ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)
}

SaveWelcomeSettings(val) {
  global cfg
  cfg.showHelpOnStartup := val
  cfg.Save()
}