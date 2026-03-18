;@Ahk2Exe-SetName On Screen Drawing Tool
;@Ahk2Exe-SetDescription Lightweight screen annotation tool
;@Ahk2Exe-SetFileVersion 1.5
;@Ahk2Exe-SetCompanyName akcanSoft
;@Ahk2Exe-SetCopyright ©2026 Mesut Akcan
;@Ahk2Exe-SetMainIcon app_icon.ico

/*
=========================
On Screen Drawing Tool
=========================
A lightweight on-screen drawing tool for annotating the screen with
lines, rectangles, ellipses, circles, arrows and freehand drawings.
=========================
Date: 19/03/2026
Author: Mesut Akcan
=========================
github.com/akcansoft
mesutakcan.blogspot.com
akcansoft.blogspot.com
youtube.com/mesutakcan
=========================
Detailed information, source code, compiled binaries, and more are available on GitHub:
https://github.com/akcansoft/On-Screen-Drawing-Tool
=========================
*/

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "Gdip.ahk"
#Include "AppLib.ahk"
#Include "Settings.ahk"
#Include "Help.ahk"

; Set custom icon for the tray menu
if (!A_IsCompiled)
  try TraySetIcon(A_ScriptDir "\app_icon.ico")

InitDpiAwareness()
CoordMode("Mouse", "Screen")

App := {
  Name: "akcanSoft On Screen Drawing Tool",
  Version: "1.5",
  iniPath: A_ScriptDir "\settings.ini",
  githubRepo: "https://github.com/akcansoft/On-Screen-Drawing-Tool",
  helpWinTitle: "Help",
  settingsWinTitle: "Settings"
}

cfg := AppConfig()

state := {
  drawingMode: false,
  drawing: false,
  needsUpdate: false,
  cursorActive: false,
  orthoMode: false,
  monitor: { num: 0, left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 },
  skipSaveSettings: false
}

draw := {
  color: ARGB(cfg.hasLastUsedColor ? cfg.lastUsedColorRGB : cfg.colors.List[1].val, cfg.drawAlpha),
  currentShape: {},
  history: [],
  redoStack: []
}

ui := {
  overlayGui: "",
  drawToolbar: "",
  appSettingsGui: "",
  helpGui: "",
  colorMarks: Map(),
  lineWidthCtrl: "",
  drawAlphaCtrl: "",
  trayLabel: ""
}

gdi := GDIContext()

gdi.Init() ; Initialize GDI+

OnExit(OnAppExit)

; Event Listeners
OnMessage(0x201, WM_LBUTTONDOWN) ; Left button down
OnMessage(0x202, WM_LBUTTONUP)   ; Left button up
OnMessage(0x200, WM_MOUSEMOVE)   ; Mouse move
OnMessage(0x204, WM_RBUTTONDOWN) ; Right button down (for settings)
OnMessage(0x0F, WM_PAINT)       ; WM_PAINT
OnMessage(0x14, WM_ERASEBKGND)  ; WM_ERASEBKGND
OnMessage(0x20, WM_SETCURSOR)   ; WM_SETCURSOR

InitTrayMenu()

if (cfg.showHelpOnStartup) ; Show help on startup
  ShowHelp()

; Hotkeys
if cfg.hotkeys.toggle
  Hotkey(cfg.hotkeys.toggle, ToggleDrawingMode)
if cfg.hotkeys.exit
  Hotkey(cfg.hotkeys.exit, (*) => ExitApp())
if cfg.hotkeys.help
  Hotkey(cfg.hotkeys.help, ShowHelp)

HotIf (*) => WinActive("ahk_id " _SafeHwnd(ui.drawToolbar))
Hotkey("Esc", CloseDrawToolbar)

HotIf (*) => state.drawingMode && IsMouseOnActiveMonitor()
  && !WinActive("ahk_class #32770")
  && !(_GuiExists(ui.drawToolbar) && WinActive("ahk_id " _SafeHwnd(ui.drawToolbar)))
  && !_IsAppSettingsOpen()
  && !_GuiExists(ui.helpGui)
if cfg.hotkeys.clear
  Hotkey(cfg.hotkeys.clear, ClearDrawing)
if cfg.hotkeys.undo
  Hotkey(cfg.hotkeys.undo, DeleteLastShape)
if cfg.hotkeys.redo
  Hotkey(cfg.hotkeys.redo, RedoLastShape)
if cfg.hotkeys.incLine
  Hotkey(cfg.hotkeys.incLine, AdjustLineWidthUp)
if cfg.hotkeys.decLine
  Hotkey(cfg.hotkeys.decLine, AdjustLineWidthDown)
Hotkey("XButton1", DeleteLastShape)
Hotkey("XButton2", RedoLastShape)
if cfg.hotkeys.ortho
  Hotkey(cfg.hotkeys.ortho, ToggleOrthoMode)
for item in cfg.colors.List
  Hotkey(item.hk, SetDrawColor.Bind(item.val))
Hotkey("WheelUp", AdjustLineWidthUp)
Hotkey("WheelDown", AdjustLineWidthDown)
HotIf

;=============================================
CloseDrawToolbar(*) {
  _ManageDrawToolbar("hide")
}

; Centralized management for Drawing Toolbar GUI (Hide or Destroy)
_ManageDrawToolbar(action := "hide", restoreCursor := true) {
  global ui, state

  if (!IsObject(ui.drawToolbar))
    return

  try {
    if (action = "destroy") {
      ui.drawToolbar.Destroy()
      ui.drawToolbar := ""
      ui.colorMarks.Clear()
      ui.lineWidthCtrl := ""
      ui.drawAlphaCtrl := ""
    } else {
      if (_GuiExists(ui.drawToolbar))
        ui.drawToolbar.Hide()
    }
  } catch Error as e {
    ; OutputDebug("_ManageDrawToolbar Error: " e.Message)
  }

  if (restoreCursor && state.drawingMode && _GuiExists(ui.overlayGui))
    EnableDrawingCursor()
}

OnDrawToolbarClose(*) {
  _ManageDrawToolbar("hide")
}


AdjustLineWidthUp(*) => AdjustLineWidth(1)
AdjustLineWidthDown(*) => AdjustLineWidth(-1)

ToggleOrthoMode(*) {
  state.orthoMode := !state.orthoMode
  ToolTip("Ortho: " (state.orthoMode ? "ON" : "OFF"))
  SetTimer(() => ToolTip(), -1000)
}

; Start/Stop drawing mode from tray menu
StartDrawingFromTray(*) {
  if (state.drawingMode) {
    ExitDrawingMode(false)
    return
  }
  ; Allow tray menu to close and then take screenshot as soon as it's gone
  SetTimer(() => (
    WinWaitClose("ahk_class #32768", , 0.5), ; Wait for menu to vanish
    Sleep(150),
    ToggleDrawingMode()
  ), -10)
}

; Initialize tray menu
InitTrayMenu() {
  hkSuffix := "`t" FormatHotkeyLabel(cfg.hotkeys.toggle)
  ui.trayLabel := (state.drawingMode ? "Stop Drawing" : "Start Drawing") . hkSuffix

  A_TrayMenu.Delete()

  AddMenuItem(App.helpWinTitle "`t" FormatHotkeyLabel(cfg.hotkeys.help), ShowHelp, "shell32.dll", 24)
  AddMenuItem(App.settingsWinTitle, ShowAppSettings, "shell32.dll", 270)
  AddMenuItem("Restart Application", (*) => Reload(), "imageres.dll", 230)
  A_TrayMenu.Add()
  AddMenuItem(ui.trayLabel, StartDrawingFromTray, "imageres.dll", 365)
  AddMenuItem("Exit`t" FormatHotkeyLabel(cfg.hotkeys.exit), (*) => ExitApp(), "shell32.dll", 28)

  A_TrayMenu.Default := ui.trayLabel
}

; Add a menu item to the tray menu
AddMenuItem(label, callback, iconFile := "", iconIdx := 0) {
  A_TrayMenu.Add(label, callback)
  if (iconFile)
    try A_TrayMenu.SetIcon(label, iconFile, iconIdx)
}

UpdateTrayToggleMenu() {
  hkSuffix := "`t" FormatHotkeyLabel(cfg.hotkeys.toggle)
  newLabel := (state.drawingMode ? "Stop Drawing" : "Start Drawing") . hkSuffix

  if (ui.trayLabel = newLabel)
    return

  try {
    A_TrayMenu.Rename(ui.trayLabel, newLabel)
    ui.trayLabel := newLabel
    A_TrayMenu.Default := ui.trayLabel
  } catch {
    InitTrayMenu()
  }
}


; Drawing Mode: Toggle
ToggleDrawingMode(*) {
  global ui, gdi, state, draw

  if (state.drawingMode) {
    ExitDrawingMode(false)
    return
  }

  mon := GetMouseMonitorInfo()
  if (!IsObject(mon) || mon.Width <= 0 || mon.Height <= 0) {
    MsgBox("Failed to detect monitor for mouse position.", "Error", 48)
    return
  }

  ; Check before closing — determines if we need to wait for windows to disappear
  needsDelay := _GuiExists(ui.helpGui) || _GuiExists(ui.appSettingsGui) || _GuiExists(ui.overlayGui)
  _OnHelpClose()
  _OnAppSettingsClose()

  lastMonitorNum := state.monitor.num  ; preserve before overwrite
  monitorChanged := (lastMonitorNum != 0 && lastMonitorNum != mon.Num)
  state.monitor := {
    num: Integer(mon.Num),
    left: mon.Left,
    top: mon.Top,
    right: mon.Right,
    bottom: mon.Bottom,
    width: mon.Width,
    height: mon.Height
  }

  if (_GuiExists(ui.overlayGui))
    try ui.overlayGui.Hide()
  if (needsDelay)
    Sleep(250)

  ; Release old GDI resources
  gdi.DestroyBuffer()

  ; Capture screen and create buffers
  try {
    gdi.CreateBuffer(state.monitor.num, state.monitor.width, state.monitor.height)
  } catch Error as e {
    MsgBox(e.Message, "Error", 48)
    return
  }

  draw.currentShape := {}
  state.drawing := false
  state.needsUpdate := false
  state.drawingMode := true
  if (monitorChanged) {
    draw.history := []
    draw.redoStack := []
  }

  RefreshBakedBuffer()
  UpdateBuffer()

  ; Transparent, clickable overlay window
  ui.overlayGui := Gui("+AlwaysOnTop -DPIScale -Caption +ToolWindow +E0x20")
  ui.overlayGui.OnEvent("Close", (*) => ExitDrawingMode(false))
  ui.overlayGui.Show("NA x" state.monitor.left " y" state.monitor.top " w" state.monitor.width " h" state.monitor.height
  )
  EnableDrawingCursor()
  InvalidateOverlay()
  UpdateTrayToggleMenu()
}

; Drawing Mode: Exit
ExitDrawingMode(UserInitiated := false) {
  global ui, gdi, state, draw, cfg

  SetTimer(UpdateTimer, 0)
  DisableDrawingCursor()
  state.drawingMode := false
  state.drawing := false
  state.needsUpdate := false

  draw.currentShape := {}

  if (_GuiExists(ui.overlayGui)) {
    try ui.overlayGui.Destroy()
    ui.overlayGui := ""
  }
  _ManageDrawToolbar("destroy", false)

  if (cfg.clearOnExitDraw) {
    draw.history := []
    draw.redoStack := []
  }

  if (UserInitiated)
    gdi.Destroy()
  else
    gdi.DestroyBuffer()

  state.monitor := {
    num: state.monitor.num,  ; preserve last monitor number for change detection on next toggle
    left: 0,
    top: 0,
    right: 0,
    bottom: 0,
    width: 0,
    height: 0
  }

  UpdateTrayToggleMenu()
}

EnableDrawingCursor() {
  global state, ui
  state.cursorActive := true
  SetTimer(_ApplyPenCursor, -50)
}

_ApplyPenCursor() {
  global state, ui
  if (!state.drawingMode || !state.cursorActive || !_GuiExists(ui.overlayGui))
    return
  MouseGetPos(&mX, &mY)
  if (mX >= state.monitor.left && mX < state.monitor.right
    && mY >= state.monitor.top && mY < state.monitor.bottom) {
    static IDC_PEN := 32631
    hCursor := DllCall("LoadCursor", "Ptr", 0, "Ptr", IDC_PEN, "Ptr")
    if (hCursor)
      DllCall("SetCursor", "Ptr", hCursor)
  }
}

InvalidateOverlay() {
  global ui
  if (_GuiExists(ui.overlayGui)) {
    try DllCall("InvalidateRect", "Ptr", ui.overlayGui.Hwnd, "Ptr", 0, "Int", 0)
  }
}

DisableDrawingCursor() {
  global state
  state.cursorActive := false
}

; Save last used drawing settings to INI on exit
SaveLastUsedSettings() {
  global cfg, draw, state
  if (state.skipSaveSettings)
    return
  cfg.WriteLastUsed(draw.color)
}

; On app exit
OnAppExit(ExitReason, ExitCode) {
  SaveLastUsedSettings()
  ExitDrawingMode(true)
}

; WM Message Handlers
WM_ERASEBKGND(wParam, lParam, msg, hwnd) {
  global ui
  ; Prevent white flickering in the overlay window
  if (_SafeHwnd(ui.overlayGui) == hwnd)
    return 1
}

WM_PAINT(wParam, lParam, msg, hwnd) {
  global ui, gdi, state

  if (!state.drawingMode || _SafeHwnd(ui.overlayGui) != hwnd || !gdi.hdcMem || state.monitor.width <=
    0 || state.monitor.height <= 0)
    return

  static ps := Buffer(A_PtrSize == 8 ? 72 : 64) ; paint Struct Size
  hDC := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")
  if (!hDC)
    return 0

  DllCall("BitBlt",
    "Ptr", hDC, "Int", 0, "Int", 0, "Int", state.monitor.width, "Int", state.monitor.height,
    "Ptr", gdi.hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)  ; SRCCOPY

  DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr)
  return 0
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
  global ui, state, draw, cfg

  if (!state.drawingMode || !_GuiExists(ui.overlayGui))
    return

  if (_GuiExists(ui.drawToolbar)) {
    toolbarHwnd := _SafeHwnd(ui.drawToolbar)
    if (hwnd = toolbarHwnd || DllCall("IsChild", "Ptr", toolbarHwnd, "Ptr", hwnd, "Int"))
      return
  }

  if (_IsAppSettingsOpen())
    return

  if (_GuiExists(ui.helpGui))
    return

  if (hwnd != _SafeHwnd(ui.overlayGui))
    return

  ; Close settings window if open and clicked outside
  _ManageDrawToolbar("hide")

  GetOverlayPointFromLParam(lParam, &x, &y, true)

  ; Determine active tool based on modifier key combinations
  currentTool := "free"
  if (GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P"))
    currentTool := "arrow"
  else if (GetKeyState("Ctrl", "P") && GetKeyState("Alt", "P"))
    currentTool := "circle"
  else if (GetKeyState("Alt", "P"))
    currentTool := "ellipse"
  else if (GetKeyState("Shift", "P"))
    currentTool := "line"
  else if (GetKeyState("Ctrl", "P"))
    currentTool := "rect"

  state.drawing := true

  draw.currentShape := {
    type: currentTool,
    startX: x,
    startY: y,
    endX: x,
    endY: y,
    radius: 0,
    color: draw.color,
    width: cfg.line.width
  }
  if (currentTool = "free") {
    draw.currentShape.points := [[x, y]]
    draw.currentShape.pointsStr := x "," y  ; Incremental string starts here
  }

  SetTimer(UpdateTimer, cfg.frameIntervalMs)
  DllCall("SetCapture", "Ptr", hwnd)
}

WM_LBUTTONUP(wParam, lParam, msg, hwnd) {
  global ui, state, draw

  if (!state.drawingMode || !_GuiExists(ui.overlayGui) || hwnd != _SafeHwnd(ui.overlayGui))
    return

  DllCall("ReleaseCapture")
  state.drawing := false
  SetTimer(UpdateTimer, 0)

  shapeToFinalize := draw.currentShape
  draw.currentShape := {}
  if (!IsObject(shapeToFinalize) || !shapeToFinalize.HasProp("type") || shapeToFinalize.type = "")
    return

  ; Skip invalid (single point or zero dimension) shapes
  valid := true
  if (shapeToFinalize.type = "free" && shapeToFinalize.points.Length <= 2)
    valid := false
  else if (shapeToFinalize.type != "free"
    && shapeToFinalize.startX = shapeToFinalize.endX
    && shapeToFinalize.startY = shapeToFinalize.endY)
    valid := false

  if (valid) {
    draw.redoStack := []
    ; Enforce history size limit — silently drop the oldest entry if exceeded
    while (draw.history.Length >= cfg.maxHistorySize)
      draw.history.RemoveAt(1)
    draw.history.Push(shapeToFinalize)
    if (!_AppendShapeToBaked(shapeToFinalize))
      RefreshBakedBuffer()
  }

  UpdateBuffer()
  InvalidateOverlay()
  state.needsUpdate := false
}

WM_SETCURSOR(wParam, lParam, msg, hwnd) {
  global ui, state
  ; Set pen cursor when hovering over the overlay in drawing mode, otherwise show default cursor
  if (state.drawingMode && state.cursorActive && _GuiExists(ui.overlayGui)
    && hwnd = _SafeHwnd(ui.overlayGui)) {
    static IDC_PEN := 32631
    hCursor := DllCall("LoadCursor", "Ptr", 0, "Ptr", IDC_PEN, "Ptr")
    if (hCursor) {
      DllCall("SetCursor", "Ptr", hCursor)
      return true
    }
  }
}

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
  global ui, state, draw, cfg

  if (!state.drawing || !state.drawingMode || !_GuiExists(ui.overlayGui) || hwnd != _SafeHwnd(ui.overlayGui))
    return
  if (!IsObject(draw.currentShape) || !draw.currentShape.HasProp("type"))
    return

  GetOverlayPointFromLParam(lParam, &x, &y, true)

  if (draw.currentShape.type = "free") {
    if (!draw.currentShape.HasProp("points") || !IsObject(draw.currentShape.points))
      return
    lastPoint := draw.currentShape.points[draw.currentShape.points.Length]
    if (Abs(x - lastPoint[1]) >= cfg.minPointStep || Abs(y - lastPoint[2]) >= cfg.minPointStep) {
      draw.currentShape.points.Push([x, y])
      draw.currentShape.pointsStr .= "|" x "," y  ; O(1) incremental append
      state.needsUpdate := true
    }
  } else {
    ; Ortho mode: locks to horizontal or vertical axis (line and arrow only)
    if ((draw.currentShape.type = "line" || draw.currentShape.type = "arrow") && state.orthoMode) {
      dx := Abs(x - draw.currentShape.startX)
      dy := Abs(y - draw.currentShape.startY)
      if (dx >= dy)
        y := draw.currentShape.startY  ; lock horizontal
      else
        x := draw.currentShape.startX  ; lock vertical
    }
    draw.currentShape.endX := x
    draw.currentShape.endY := y
    if (draw.currentShape.type = "circle")
      draw.currentShape.radius := Max(Abs(x - draw.currentShape.startX), Abs(y - draw.currentShape.startY))
    state.needsUpdate := true
  }
}

; Right-click to open drawing toolbar
WM_RBUTTONDOWN(wParam, lParam, msg, hwnd) {
  global ui, state

  if (!state.drawingMode || !_GuiExists(ui.overlayGui) || hwnd != _SafeHwnd(ui.overlayGui))
    return

  if (_IsAppSettingsOpen())
    return

  if (_GuiExists(ui.helpGui))
    return

  DisableDrawingCursor()

  if (!_GuiExists(ui.drawToolbar))
    _CreateDrawToolbar()

  _UpdateDrawToolbar()

  MouseGetPos(&mX, &mY)
  try {
    ui.drawToolbar.Show("AutoSize x" mX " y" mY)
    WinGetPos(, , &w, &h, "ahk_id " ui.drawToolbar.Hwnd)
    minX := state.monitor.left
    minY := state.monitor.top
    maxX := Max(minX, state.monitor.right - w)
    maxY := Max(minY, state.monitor.bottom - h)
    finalX := Min(Max(mX, minX), maxX)
    finalY := Min(Max(mY, minY), maxY)
    if (finalX != mX || finalY != mY)
      WinMove(finalX, finalY, , , "ahk_id " ui.drawToolbar.Hwnd)
  } catch Error as e {
    OutputDebug("WM_RBUTTONDOWN Error showing toolbar: " e.Message)
  }
}

_CreateDrawToolbar() {
  global ui, cfg

  ownerHwnd := _SafeHwnd(ui.overlayGui)
  ui.drawToolbar := Gui("+AlwaysOnTop +ToolWindow -Caption Border" (ownerHwnd ? " +Owner" ownerHwnd : ""))
  ui.drawToolbar.OnEvent("Close", OnDrawToolbarClose)
  _ResetUISettingsFont(ui.drawToolbar)
  margin := 10
  btnSize := 30
  gap := 4
  colorColumnCount := 3

  ui.colorMarks.Clear()
  curY := margin
  for i, item in cfg.colors.List {
    val := item.val
    hkLetter := StrUpper(item.hk)
    hex := Format("{:06X}", val)
    col := Mod(i - 1, colorColumnCount)
    row := (i - 1) // colorColumnCount

    bx := margin + col * (btnSize + gap)
    by := curY + row * (btnSize + gap)
    btn := ui.drawToolbar.Add("Text", "x" bx " y" by " w" btnSize " h" btnSize " +Border +0x0100 Background" hex)

    luminance := GetLuminance(val)
    markColor := (luminance > 128) ? "000000" : "FFFFFF"

    ; Selection checkmark (Center)
    ui.drawToolbar.SetFont("s16 w1000")
    chk := ui.drawToolbar.AddText("xp yp wp hp +Center +0x200 c" markColor " BackgroundTrans", "")

    ; Shortcut hint (Bottom-left)
    if (cfg.showColorHints) {
      ui.drawToolbar.SetFont("s7 w700")
      ui.drawToolbar.AddText("x" bx + 2 " y" by + btnSize - 13 " w15 h12 c" markColor " BackgroundTrans",
        hkLetter)
    }

    btn.OnEvent("Click", ColorSelect.Bind(val))
    chk.OnEvent("Click", ColorSelect.Bind(val))
    ui.colorMarks[val] := chk
  }
  _ResetUISettingsFont(ui.drawToolbar)

  rowCount := Ceil(cfg.colors.List.Length / colorColumnCount)
  gridBottom := curY + rowCount * (btnSize + gap)

  ; Line width control
  ui.drawToolbar.AddText("x" margin " y" (gridBottom + 5), "Line width:")
  ui.lineWidthCtrl := ui.drawToolbar.AddEdit("vLineWidth yp-5 w40 x+2 Number", cfg.line.width)
  ui.lineWidthCtrl.OnEvent("Change", (*) => UpdateLineWidth(ui.drawToolbar))
  ui.drawToolbar.AddUpDown("Range" cfg.line.minWidth "-" cfg.line.maxWidth, cfg.line.width).OnEvent("Change", (*) =>
    UpdateLineWidth(ui.drawToolbar))

  ; Opacity control
  ui.drawToolbar.AddText("x" margin " y+12", "Opacity:")
  ui.drawAlphaCtrl := ui.drawToolbar.AddEdit("vDrawAlpha yp-5 w50 x+6 Number", cfg.drawAlpha)
  ui.drawAlphaCtrl.OnEvent("Change", (*) => UpdateDrawAlpha(ui.drawToolbar))
  ui.drawToolbar.AddUpDown("Range0-255", cfg.drawAlpha).OnEvent("Change", (*) => UpdateDrawAlpha(ui.drawToolbar))

  ; Quick actions (symbol buttons)
  btnOpt := " w30 h30 +Border +Center +0x200 +0x100 BackgroundFAFAFA"
  iconFont := "Segoe MDL2 Assets"
  try {
    RegRead("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts", "Segoe Fluent Icons (TrueType)")
    iconFont := "Segoe Fluent Icons"
  }
  ui.drawToolbar.SetFont("s14 c2b8600", iconFont)
  btnUndo := ui.drawToolbar.AddText("x10 y+5" btnOpt, Chr(0xE7A7))
  btnRedo := ui.drawToolbar.AddText("x+" gap " yp" btnOpt, Chr(0xE7A6))
  ui.drawToolbar.SetFont("c0059ff")
  btnClear := ui.drawToolbar.AddText("x+" gap " yp" btnOpt, Chr(0xED62)) ; E74D EF19

  ; Last row buttons: Help, Exit Drawing, Exit App
  btnHelp := ui.drawToolbar.AddText("x10 y+5" btnOpt, Chr(0xE897))
  btnExitDraw := ui.drawToolbar.AddText("x+" gap " yp" btnOpt, Chr(0xEE56))
  ui.drawToolbar.SetFont("cff0000")
  btnExitApp := ui.drawToolbar.AddText("x+" gap " yp" btnOpt, Chr(0xE7E8)) ; ⏻

  btnExitDraw.GetPos(&dX, &dY, &dW, &dH)
  ui.drawToolbar.SetFont("s20")
  chkExit := ui.drawToolbar.AddText("x" dX - 5 " y" dY - 10 " w" dW " h" dH " cRed +Center +0x200 BackgroundTrans +E0x20",
    "✕")
  _ResetUISettingsFont(ui.drawToolbar)

  btnUndo.OnEvent("Click", (*) => DeleteLastShape())
  btnUndo.OnEvent("DoubleClick", (*) => DeleteLastShape())
  btnRedo.OnEvent("Click", (*) => RedoLastShape())
  btnRedo.OnEvent("DoubleClick", (*) => RedoLastShape())
  btnClear.OnEvent("Click", (*) => ClearDrawing())
  btnHelp.OnEvent("Click", (*) => ShowHelp())
  btnExitDraw.OnEvent("Click", (*) => ExitDrawingFromToolbar())
  btnExitApp.OnEvent("Click", (*) => ExitAppFromToolbar())
}

_UpdateDrawToolbar() {
  global ui, cfg, draw
  activeRGB := draw.color & 0xFFFFFF
  for val, chkCtrl in ui.colorMarks {
    chkCtrl.Text := (val = activeRGB) ? "✓" : ""
  }
  if (ui.lineWidthCtrl.Value != cfg.line.width)
    ui.lineWidthCtrl.Value := cfg.line.width
  if (ui.drawAlphaCtrl.Value != cfg.drawAlpha)
    ui.drawAlphaCtrl.Value := cfg.drawAlpha
}

; Toolbar & Color Operations
ColorSelect(colorVal, *) {
  global draw, cfg
  draw.color := ARGB(colorVal, cfg.drawAlpha)
  _ManageDrawToolbar("hide")
}

UpdateLineWidth(gui, *) {
  val := gui["LineWidth"].Value
  if (val != "" && IsNumber(val)) {
    newWidth := Integer(val)
    if (newWidth >= cfg.line.minWidth && newWidth <= cfg.line.maxWidth)
      cfg.line.width := newWidth
  }
}

UpdateDrawAlpha(gui, *) {
  global draw, cfg
  val := gui["DrawAlpha"].Value
  if (val != "" && IsNumber(val)) {
    newAlpha := Integer(val)
    if (newAlpha >= 0 && newAlpha <= 255) {
      cfg.drawAlpha := newAlpha
      draw.color := ARGB(draw.color & 0xFFFFFF, cfg.drawAlpha)
    }
  }
}

ExitDrawingFromToolbar(*) {
  _ManageDrawToolbar("hide", false)
  ExitDrawingMode(false)
}

ExitAppFromToolbar(*) {
  _ManageDrawToolbar("hide", false)
  ExitApp()
}

ClearDrawing(*) {
  global ui, gdi, state, draw
  if (!state.drawingMode)
    return

  ; If currently drawing, cancel the active shape first
  if (state.drawing) {
    state.drawing := false
    draw.currentShape := {}
    DllCall("ReleaseCapture")
    SetTimer(UpdateTimer, 0)
  }

  ; Check if there are any visible shapes to clear (items after the last clear marker)
  lastClearIdx := 0
  for i, item in draw.history
    if (IsObject(item) && item.HasProp("type") && item.type == "clear")
      lastClearIdx := i
  if (lastClearIdx >= draw.history.Length)
    return  ; Nothing visible to clear

  ; Push a flat clear marker — just another step in the linear history
  draw.history.Push({ type: "clear" })
  ; ---- draw.redoStack := [] -----

  if (gdi.G_Baked)
    DllCall("gdiplus\GdipGraphicsClear", "UPtr", gdi.G_Baked, "Int", 0)
  RefreshBakedBuffer()
  UpdateBuffer()
  InvalidateOverlay()
}

DeleteLastShape(*) {
  global ui, gdi, state, draw
  if (!state.drawingMode || !draw.history.Length)
    return

  ; Pop the last action (shape or clear marker) and move it to redo stack
  draw.redoStack.Push(draw.history.Pop())

  if (gdi.G_Baked)
    DllCall("gdiplus\GdipGraphicsClear", "UPtr", gdi.G_Baked, "Int", 0)
  RefreshBakedBuffer()
  UpdateBuffer()
  InvalidateOverlay()
}

RedoLastShape(*) {
  global ui, gdi, state, draw
  if (!state.drawingMode || !draw.redoStack.Length)
    return

  ; Restore the next action (shape or clear marker) from redo stack
  item := draw.redoStack.Pop()
  draw.history.Push(item)

  if (gdi.G_Baked)
    DllCall("gdiplus\GdipGraphicsClear", "UPtr", gdi.G_Baked, "Int", 0)
  RefreshBakedBuffer()
  UpdateBuffer()
  InvalidateOverlay()
}

AdjustLineWidth(delta) {
  static tooltipTimer := 0
  if (!state.drawingMode)
    return
  cfg.line.width := Max(Min(cfg.line.width + delta, cfg.line.maxWidth), cfg.line.minWidth)
  ToolTip("Width: " cfg.line.width)
  if (tooltipTimer)
    SetTimer(tooltipTimer, 0)
  tooltipTimer := () => ToolTip()
  SetTimer(tooltipTimer, -1000)
}

SetDrawColor(colorRGB, *) {
  global state, draw, cfg
  if (!state.drawingMode)
    return false
  rgb := colorRGB & 0xFFFFFF
  draw.color := ARGB(rgb, cfg.drawAlpha)
  return true
}

; Timer & Buffer Update
UpdateTimer() {
  global ui, state
  if (!state.drawingMode || !_GuiExists(ui.overlayGui)) {
    SetTimer(UpdateTimer, 0)
    return
  }
  if (state.needsUpdate) {
    state.needsUpdate := false
    UpdateBuffer()
    InvalidateOverlay()
  }
}

UpdateBuffer() {
  global gdi, draw, state
  if (!gdi.G_Mem || !gdi.hdcBaked || !gdi.hdcMem || state.monitor.width <= 0 || state.monitor.height <= 0)
    return

  DllCall("BitBlt",
    "Ptr", gdi.hdcMem, "Int", 0, "Int", 0, "Int", state.monitor.width, "Int", state.monitor.height,
    "Ptr", gdi.hdcBaked, "Int", 0, "Int", 0, "UInt", 0x00CC0020)  ; SRCCOPY

  if (state.drawing && IsObject(draw.currentShape) && draw.currentShape.HasProp("type"))
    DrawShapesToGraphics(gdi.G_Mem, [draw.currentShape])
}

RefreshBakedBuffer() {
  global gdi, state, draw
  if (!gdi.G_Baked || !gdi.hBitmapBackground || state.monitor.width <= 0 || state.monitor.height <= 0)
    return

  ; Find the index of the last clear marker in the flat history
  lastClearIdx := 0
  for i, item in draw.history
    if (IsObject(item) && item.HasProp("type") && item.type == "clear")
      lastClearIdx := i

  ; Draw background, then only the shapes that are visible (after the last clear)
  Gdip_DrawImage(gdi.G_Baked, gdi.hBitmapBackground, 0, 0, state.monitor.width, state.monitor.height)
  if (lastClearIdx < draw.history.Length) {
    visibleShapes := []
    loop draw.history.Length - lastClearIdx
      visibleShapes.Push(draw.history[lastClearIdx + A_Index])
    DrawShapesToGraphics(gdi.G_Baked, visibleShapes)
  }
}

_AppendShapeToBaked(shape) {
  global gdi, state
  if (!IsObject(shape) || !shape.HasProp("type") || shape.type == "clear")
    return false
  if (!gdi.G_Baked || state.monitor.width <= 0 || state.monitor.height <= 0)
    return false
  try {
    DrawShapesToGraphics(gdi.G_Baked, [shape])
    return true
  } catch {
    return false
  }
}

IsMouseOnActiveMonitor() {
  global state
  if (!IsObject(state.monitor) || state.monitor.width <= 0 || state.monitor.height <= 0)
    return false
  MouseGetPos(&mX, &mY)
  return (mX >= state.monitor.left && mX < state.monitor.right && mY >= state.monitor.top && mY < state.monitor.bottom
  )
}

GetMouseMonitorInfo() {
  MouseGetPos(&mX, &mY)
  hMon := MDMF_FromPoint(&mX, &mY, 2)
  if (!hMon)
    return ""

  info := MDMF_GetInfo(hMon)
  if (!IsObject(info))
    return ""

  info.HMON := hMon
  info.Width := info.Right - info.Left
  info.Height := info.Bottom - info.Top
  return info
}

GetOverlayPointFromLParam(lParam, &x, &y, clampToOverlay := false) {
  global state

  x := SignedInt16(lParam & 0xFFFF)
  y := SignedInt16((lParam >> 16) & 0xFFFF)

  if (!clampToOverlay || state.monitor.width <= 0 || state.monitor.height <= 0)
    return

  x := Max(0, Min(x, state.monitor.width - 1))
  y := Max(0, Min(y, state.monitor.height - 1))
}


DrawShapesToGraphics(G, shapesArray) {
  lastPenColor := -1, lastPenWidth := -1, pPen := 0
  lastFreePenColor := -1, lastFreePenWidth := -1, pFreePen := 0  ; Round-cap pen for freehand
  lastBrushColor := -1, pBrush := 0

  static LineCapRound := 1  ; GDI+ LineCap enumeration
  static LineJoinRound := 2  ; GDI+ LineJoin enumeration (distinct from LineCap!)

  for index, shape in shapesArray {
    if (!IsObject(shape) || !shape.HasProp("type") || shape.type == "clear")
      continue

    if (shape.color != lastPenColor || shape.width != lastPenWidth) {
      if (pPen)
        Gdip_DeletePen(pPen)
      pPen := Gdip_CreatePen(shape.color, shape.width)
      if (!pPen)
        continue
      lastPenColor := shape.color
      lastPenWidth := shape.width
    }

    ; Freehand uses a separate round-cap pen for smooth stroke ends and joins
    if (shape.type = "free" && (shape.color != lastFreePenColor || shape.width != lastFreePenWidth)) {
      if (pFreePen)
        Gdip_DeletePen(pFreePen)
      pFreePen := Gdip_CreatePen(shape.color, shape.width)
      if (pFreePen) {
        DllCall("gdiplus\GdipSetPenStartCap", "UPtr", pFreePen, "Int", LineCapRound)
        DllCall("gdiplus\GdipSetPenEndCap", "UPtr", pFreePen, "Int", LineCapRound)
        DllCall("gdiplus\GdipSetPenLineJoin", "UPtr", pFreePen, "Int", LineJoinRound)
      }
      lastFreePenColor := shape.color
      lastFreePenWidth := shape.width
    }

    if (shape.type = "arrow" && shape.color != lastBrushColor) {
      if (pBrush)
        Gdip_DeleteBrush(pBrush)
      pBrush := Gdip_BrushCreateSolid(shape.color)
      if (pBrush)  ; Only update cache key if brush was created successfully
        lastBrushColor := shape.color
    }

    try {
      switch shape.type {
        case "free":
          if (shape.HasProp("points") && shape.points.Length >= 2 && pFreePen)
            Gdip_DrawLines(G, pFreePen, shape.pointsStr)
        case "rect":
          Gdip_DrawRectangle(G, pPen,
            Min(shape.startX, shape.endX),
            Min(shape.startY, shape.endY),
            Abs(shape.endX - shape.startX),
            Abs(shape.endY - shape.startY))
        case "line":
          Gdip_DrawLine(G, pPen, shape.startX, shape.startY, shape.endX, shape.endY)
        case "ellipse":
          Gdip_DrawEllipse(G, pPen,
            Min(shape.startX, shape.endX),
            Min(shape.startY, shape.endY),
            Abs(shape.endX - shape.startX),
            Abs(shape.endY - shape.startY))
        case "circle":
          Gdip_DrawEllipse(G, pPen,
            shape.startX - shape.radius, shape.startY - shape.radius,
            shape.radius * 2, shape.radius * 2)
        case "arrow":
          if (pBrush)
            DrawArrowGdip(G, pPen, pBrush, shape.startX, shape.startY, shape.endX, shape.endY, shape.width)
      }
    } catch Error as e {
      OutputDebug("GDI+ Drawing Error [type=" shape.type ", idx=" index "]: " e.Message "`n")
    }
  }

  if (pPen)
    Gdip_DeletePen(pPen)
  if (pFreePen)
    Gdip_DeletePen(pFreePen)
  if (pBrush)
    Gdip_DeleteBrush(pBrush)
}