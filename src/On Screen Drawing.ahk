/*
=========================
On Screen Drawing Tool
=========================
A lightweight on-screen drawing tool for annotating the screen with lines,
rectangles, ellipses, circles, arrows, freehand drawings, solid background fills,
and on-screen text.
=========================
Date: 04/04/2026
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

;@Ahk2Exe-SetName On Screen Drawing Tool
;@Ahk2Exe-SetDescription Lightweight screen annotation tool
;@Ahk2Exe-SetFileVersion 1.8
;@Ahk2Exe-SetCompanyName akcanSoft
;@Ahk2Exe-SetCopyright ©2026 Mesut Akcan
;@Ahk2Exe-SetMainIcon app_icon.ico

#Include "Gdip.ahk"
#Include "AppLib.ahk"
#Include "CommonDialog.ahk"
#Include "Settings.ahk"
#Include "Help.ahk"
#Include "DrawText.ahk"
#Include "CtrlToolTip.ahk"

if (!A_IsCompiled)
	try TraySetIcon(A_ScriptDir "\app_icon.ico")

InitDpiAwareness()
CoordMode("Mouse", "Screen")

App := {
	Name: "akcanSoft On Screen Drawing Tool",
	Version: "1.8",
	iniPath: A_ScriptDir "\settings.ini",
	githubRepo: "https://github.com/akcansoft/On-Screen-Drawing-Tool",
	helpWinTitle: "Help",
	settingsWinTitle: "Settings",
	helpIcon: { file: "shell32.dll", idx: 24 },
	settingsIcon: { file: "imageres.dll", idx: 110 }
}

cfg := AppConfig()

state := {
	drawingMode: false,
	drawing: false,
	needsUpdate: false,
	cursorActive: false,
	orthoMode: false,
	textMode: false,
	textInput: {
		active: false,
		buffer: "",
		x: 0, y: 0,
		cursorVisible: false
	},
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
	textGui: "",
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
OnMessage(0x202, WM_LBUTTONUP) ; Left button up
OnMessage(0x200, WM_MOUSEMOVE) ; Mouse move
OnMessage(0x204, WM_RBUTTONDOWN) ; Right button down (for settings)
OnMessage(0x0F, WM_PAINT) ; WM_PAINT
OnMessage(0x14, WM_ERASEBKGND) ; WM_ERASEBKGND
OnMessage(0x20, WM_SETCURSOR) ; WM_SETCURSOR

InitTrayMenu()

if (cfg.showHelpOnStartup) ; Show help on startup
	ShowHelp()

; Global hotkeys
if cfg.hotkeys.toggle
	Hotkey(cfg.hotkeys.toggle, ToggleDrawingMode)
if cfg.hotkeys.exit
	Hotkey(cfg.hotkeys.exit, (*) => ExitApp())
if cfg.hotkeys.help
	Hotkey(cfg.hotkeys.help, ShowHelp)

; Only active when drawing toolbar is open
HotIf (*) => WinActive("ahk_id " _SafeHwnd(ui.drawToolbar))
Hotkey("Esc", CloseDrawToolbar)

; Drawing mode hotkeys (not active in text mode)
HotIf (*) => state.drawingMode && !state.textMode && IsMouseOnActiveMonitor()
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
for item in cfg.colors.List {
	Hotkey(item.hk, SetDrawColor.Bind(item.val))
	if (cfg.fillModifier != "")
		Hotkey(cfg.fillModifier item.hk, FillBackground.Bind(item.val))
}
Hotkey("WheelUp", AdjustLineWidthUp)
Hotkey("WheelDown", AdjustLineWidthDown)

; Enter text mode
if cfg.hotkeys.text
	Hotkey(cfg.hotkeys.text, EnterTextMode)

; Text mode hotkeys
HotIf (*) => state.drawingMode && state.textMode
if cfg.hotkeys.exitText
	Hotkey(cfg.hotkeys.exitText, ExitTextMode)
if cfg.hotkeys.decTextSize
	Hotkey(cfg.hotkeys.decTextSize, (*) => AdjustTextSize(-4))
if cfg.hotkeys.incTextSize
	Hotkey(cfg.hotkeys.incTextSize, (*) => AdjustTextSize(4))
if cfg.hotkeys.cycleTextCol
	Hotkey(cfg.hotkeys.cycleTextCol, CycleTextColor)

HotIf ; End context-sensitive hotkeys

;=============================
CloseDrawToolbar(*) {
	_ManageDrawToolbar("hide")
}

_ManageDrawToolbar(action := "hide", restoreCursor := true) {
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
		OutputDebug("_ManageDrawToolbar Error: " e.Message)
	}

	if (restoreCursor && state.drawingMode && !state.textMode && _GuiExists(ui.overlayGui))
		EnableDrawingCursor()
}

AdjustLineWidthUp(*) => AdjustLineWidth(1)
AdjustLineWidthDown(*) => AdjustLineWidth(-1)

ToggleOrthoMode(*) {
	static _clearTip := () => ToolTip()
	state.orthoMode := !state.orthoMode
	ToolTip("Ortho: " (state.orthoMode ? "ON" : "OFF"))
	SetTimer(_clearTip, -1000)
}

StartDrawingFromTray(*) {
	if (state.drawingMode) {
		ExitDrawingMode(false)
		return
	}
	SetTimer(() => (
		WinWaitClose("ahk_class #32768", , 0.5),
		Sleep(150),
		ToggleDrawingMode()
	), -10)
}

InitTrayMenu() {
	hkSuffix := cfg.hotkeys.toggle ? "`t" FormatHotkeyLabel(cfg.hotkeys.toggle) : ""
	ui.trayLabel := (state.drawingMode ? "Stop Drawing" : "Start Drawing") . hkSuffix

	A_TrayMenu.Delete()

	AddMenuItem(App.helpWinTitle (cfg.hotkeys.help ? "`t" FormatHotkeyLabel(cfg.hotkeys.help) : ""), ShowHelp, App.helpIcon.file, App.helpIcon.idx)
	AddMenuItem(App.settingsWinTitle, ShowAppSettings, App.settingsIcon.file, App.settingsIcon.idx)
	AddMenuItem("Restart Application", (*) => Reload(), "imageres.dll", 230)
	A_TrayMenu.Add()
	AddMenuItem(ui.trayLabel, StartDrawingFromTray, "imageres.dll", 365)
	AddMenuItem("Exit" (cfg.hotkeys.exit ? "`t" FormatHotkeyLabel(cfg.hotkeys.exit) : ""), (*) => ExitApp(), "shell32.dll", 28)

	A_TrayMenu.Default := ui.trayLabel
}

AddMenuItem(label, callback, iconFile := "", iconIdx := 0) {
	A_TrayMenu.Add(label, callback)
	if (iconFile)
		try A_TrayMenu.SetIcon(label, iconFile, iconIdx)
}

UpdateTrayToggleMenu() {
	hkSuffix := cfg.hotkeys.toggle ? "`t" FormatHotkeyLabel(cfg.hotkeys.toggle) : ""
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

ToggleDrawingMode(*) {
	if (state.drawingMode) {
		ExitDrawingMode(false)
		return
	}

	mon := GetMouseMonitorInfo()
	if (!IsObject(mon) || mon.Width <= 0 || mon.Height <= 0) {
		MsgBox("Failed to detect monitor for mouse position.", "Error", 48)
		return
	}

	needsDelay := _GuiExists(ui.helpGui) || _IsAppSettingsOpen() || _GuiExists(ui.overlayGui)
	_OnHelpClose()
	_OnAppSettingsClose()

	lastMonitorNum := state.monitor.num
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

	try ui.overlayGui.Hide()
	if (needsDelay)
		Sleep(250)

	gdi.DestroyBuffer()

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

	ui.overlayGui := Gui("+AlwaysOnTop -DPIScale -Caption +ToolWindow +E0x20")
	ui.overlayGui.OnEvent("Close", (*) => ExitDrawingMode(false))
	ui.overlayGui.Show("NA x" state.monitor.left " y" state.monitor.top " w" state.monitor.width " h" state.monitor.height)
	EnableDrawingCursor()
	InvalidateOverlay()
	UpdateTrayToggleMenu()
}

ExitDrawingMode(UserInitiated := false) {
	if (state.textMode) {
		_StopCursorBlink()
		_StopTextInput()
		state.textMode := false
		state.textInput.active := false
		state.textInput.buffer := ""
	}

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
		num: state.monitor.num,
		left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0
	}

	UpdateTrayToggleMenu()
}

EnableDrawingCursor() {
	state.cursorActive := true
	SetTimer(_ApplyPenCursor, -50)
}

_ApplyPenCursor() {
	if (!state.drawingMode || !state.cursorActive || !_GuiExists(ui.overlayGui))
		return
	if (state.textMode)
		return
	MouseGetPos(&mX, &mY)
	if (mX >= state.monitor.left && mX < state.monitor.right
		&& mY >= state.monitor.top && mY < state.monitor.bottom) {
		hCursor := LoadSystemCursor(32631) ; IDC_PEN
		if (hCursor)
			DllCall("SetCursor", "Ptr", hCursor)
	}
}

InvalidateOverlay() {
	if (_GuiExists(ui.overlayGui))
		try DllCall("InvalidateRect", "Ptr", ui.overlayGui.Hwnd, "Ptr", 0, "Int", 0)
}

; Manages only WS_EX_TRANSPARENT. For text mode, use _StartTextInput/_StopTextInput
; which handle both WS_EX_TRANSPARENT and WS_EX_NOACTIVATE together.
_SetOverlayTransparent(transparent) {
	if (!_GuiExists(ui.overlayGui))
		return
	hwnd := ui.overlayGui.Hwnd
	exStyle := DllCall("GetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int")
	if (transparent)
		exStyle |= WS_EX_TRANSPARENT
	else
		exStyle &= ~WS_EX_TRANSPARENT
	DllCall("SetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int", exStyle)
}

DisableDrawingCursor() {
	state.cursorActive := false
}

SaveLastUsedSettings() {
	if (state.skipSaveSettings)
		return
	cfg.WriteLastUsed(draw.color)
}

OnAppExit(ExitReason, ExitCode) {
	SaveLastUsedSettings()
	ExitDrawingMode(true)
}

; WM Message Handlers
WM_ERASEBKGND(wParam, lParam, msg, hwnd) {
	if (_SafeHwnd(ui.overlayGui) == hwnd)
		return 1
}

WM_PAINT(wParam, lParam, msg, hwnd) {
	if (!state.drawingMode || _SafeHwnd(ui.overlayGui) != hwnd || !gdi.hdcMem
		|| state.monitor.width <= 0 || state.monitor.height <= 0)
		return

	static ps := Buffer(A_PtrSize == 8 ? 72 : 64)
	hDC := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")
	if (!hDC)
		return 0

	DllCall("BitBlt",
		"Ptr", hDC, "Int", 0, "Int", 0, "Int", state.monitor.width, "Int", state.monitor.height,
		"Ptr", gdi.hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)

	DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr)
	return 0
}

WM_SETCURSOR(wParam, lParam, msg, hwnd) {
	if (_GuiExists(ui.overlayGui) && hwnd = _SafeHwnd(ui.overlayGui)) {
		if (state.drawingMode) {
			if (state.textMode) {
				hIBeam := LoadSystemCursor(32513) ; IDC_IBEAM
				if (hIBeam) {
					DllCall("SetCursor", "Ptr", hIBeam)
					return true
				}
			} else if (state.cursorActive) {
				hPen := LoadSystemCursor(32631) ; IDC_PEN
				if (hPen) {
					DllCall("SetCursor", "Ptr", hPen)
					return true
				}
			}
		}
	}
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
	if (!state.drawingMode || !_GuiExists(ui.overlayGui))
		return

	if (_GuiExists(ui.drawToolbar)) {
		toolbarHwnd := _SafeHwnd(ui.drawToolbar)
		if (hwnd = toolbarHwnd || DllCall("IsChild", "Ptr", toolbarHwnd, "Ptr", hwnd, "Int"))
			return
	}

	if (_IsAppSettingsOpen() || _GuiExists(ui.helpGui) || hwnd != _SafeHwnd(ui.overlayGui))
		return

	; Text mode left click
	if (state.textMode) {
		if (state.textInput.active)
			CommitText()
		GetOverlayPointFromLParam(lParam, &x, &y, true)
		state.textInput.x := x
		state.textInput.y := y
		state.textInput.active := true
		state.textInput.buffer := ""
		_StartTextInput()
		_StartCursorBlink()
		UpdateBuffer()
		InvalidateOverlay()
		return
	}

	; Normal drawing mode left click
	_ManageDrawToolbar("hide")
	GetOverlayPointFromLParam(lParam, &x, &y, true)

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
		startX: x, startY: y, endX: x, endY: y,
		radius: 0,
		color: draw.color,
		width: cfg.line.width
	}
	if (currentTool = "free") {
		draw.currentShape.points := [[x, y]]
		draw.currentShape.pointsStr := x "," y
	}

	SetTimer(UpdateTimer, cfg.frameIntervalMs)
	DllCall("SetCapture", "Ptr", hwnd)
}

WM_LBUTTONUP(wParam, lParam, msg, hwnd) {
	if (!state.drawingMode || !_GuiExists(ui.overlayGui) || hwnd != _SafeHwnd(ui.overlayGui))
		return

	DllCall("ReleaseCapture")
	state.drawing := false
	SetTimer(UpdateTimer, 0)

	shapeToFinalize := draw.currentShape
	draw.currentShape := {}
	if (!IsObject(shapeToFinalize) || !shapeToFinalize.HasProp("type") || shapeToFinalize.type = "")
		return

	valid := true
	if (shapeToFinalize.type = "free" && shapeToFinalize.points.Length < 2)
		valid := false
	else if (shapeToFinalize.type != "free"
		&& shapeToFinalize.startX = shapeToFinalize.endX
		&& shapeToFinalize.startY = shapeToFinalize.endY)
		valid := false

	if (valid) {
		draw.redoStack := []
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

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
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
			draw.currentShape.pointsStr .= "|" x "," y
			state.needsUpdate := true
		}
	} else {
		if ((draw.currentShape.type = "line" || draw.currentShape.type = "arrow") && state.orthoMode) {
			dx := Abs(x - draw.currentShape.startX)
			dy := Abs(y - draw.currentShape.startY)
			if (dx >= dy)
				y := draw.currentShape.startY
			else
				x := draw.currentShape.startX
		}
		draw.currentShape.endX := x
		draw.currentShape.endY := y
		if (draw.currentShape.type = "circle")
			draw.currentShape.radius := Max(Abs(x - draw.currentShape.startX), Abs(y - draw.currentShape.startY))
		state.needsUpdate := true
	}
}

WM_RBUTTONDOWN(wParam, lParam, msg, hwnd) {
	if (!state.drawingMode || !_GuiExists(ui.overlayGui) || hwnd != _SafeHwnd(ui.overlayGui))
		return
	if (_IsAppSettingsOpen() || _GuiExists(ui.helpGui) || state.textMode)
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

; Draw Toolbar
_CreateDrawToolbar() {
	ownerHwnd := _SafeHwnd(ui.overlayGui)
	ui.drawToolbar := Gui("+AlwaysOnTop +ToolWindow -Caption Border" (ownerHwnd ? " +Owner" ownerHwnd : ""))
	ui.drawToolbar.OnEvent("Close", CloseDrawToolbar)
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

		ui.drawToolbar.SetFont("s16 w1000")
		chk := ui.drawToolbar.AddText("xp yp wp hp +Center +0x200 c" markColor " BackgroundTrans", "")

		if (cfg.showColorHints) {
			ui.drawToolbar.SetFont("s7 w700")
			ui.drawToolbar.AddText("x" bx + 2 " y" by + btnSize - 13 " w15 h12 c" markColor " BackgroundTrans", hkLetter)
		}

		btn.OnEvent("Click", ColorSelect.Bind(val))
		chk.OnEvent("Click", ColorSelect.Bind(val))
		ui.colorMarks[val] := chk
	}
	_ResetUISettingsFont(ui.drawToolbar)

	rowCount := Ceil(cfg.colors.List.Length / colorColumnCount)
	gridBottom := curY + rowCount * (btnSize + gap)

	ui.drawToolbar.AddText("x" margin " y" (gridBottom + 5), "Line width:")
	ui.lineWidthCtrl := ui.drawToolbar.AddEdit("vLineWidth yp-5 w40 x+2 Number", cfg.line.width)
	ui.lineWidthCtrl.OnEvent("Change", (*) => UpdateLineWidth(ui.drawToolbar))
	lineWidthSpin := ui.drawToolbar.AddUpDown("Range" cfg.line.minWidth "-" cfg.line.maxWidth, cfg.line.width)
	lineWidthSpin.OnEvent("Change", (*) => UpdateLineWidth(ui.drawToolbar))

	ui.drawToolbar.AddText("x" margin " y+12", "Opacity:")
	ui.drawAlphaCtrl := ui.drawToolbar.AddEdit("vDrawAlpha yp-5 w50 x+6 Number", cfg.drawAlpha)
	ui.drawAlphaCtrl.OnEvent("Change", (*) => UpdateDrawAlpha(ui.drawToolbar))
	drawAlphaSpin := ui.drawToolbar.AddUpDown("Range0-255", cfg.drawAlpha)
	drawAlphaSpin.OnEvent("Change", (*) => UpdateDrawAlpha(ui.drawToolbar))

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
	btnClear := ui.drawToolbar.AddText("x+" gap " yp" btnOpt, Chr(0xED62))

	btnHelp := ui.drawToolbar.AddText("x10 y+5" btnOpt, Chr(0xE897))
	btnExitDraw := ui.drawToolbar.AddText("x+" gap " yp" btnOpt, Chr(0xEE56))
	ui.drawToolbar.SetFont("cff0000")
	btnExitApp := ui.drawToolbar.AddText("x+" gap " yp" btnOpt, Chr(0xE7E8))

	btnExitDraw.GetPos(&dX, &dY, &dW, &dH)
	ui.drawToolbar.SetFont("s20")
	ui.drawToolbar.AddText("x" dX - 5 " y" dY - 10 " w" dW " h" dH " cRed +Center +0x200 BackgroundTrans +E0x20", "✕")
	_ResetUISettingsFont(ui.drawToolbar)

	btnUndo.OnEvent("Click", (*) => DeleteLastShape())
	btnUndo.OnEvent("DoubleClick", (*) => DeleteLastShape())
	btnRedo.OnEvent("Click", (*) => RedoLastShape())
	btnRedo.OnEvent("DoubleClick", (*) => RedoLastShape())
	btnClear.OnEvent("Click", (*) => ClearDrawing())
	btnHelp.OnEvent("Click", (*) => ShowHelp())
	btnExitDraw.OnEvent("Click", (*) => ExitDrawingFromToolbar())
	btnExitApp.OnEvent("Click", (*) => ExitAppFromToolbar())

	lineWidthTip := "Line width (" cfg.line.minWidth "-" cfg.line.maxWidth ")"
	if (cfg.hotkeys.incLine || cfg.hotkeys.decLine) {
		lineWidthKeys := ""
		if (cfg.hotkeys.incLine)
			lineWidthKeys .= FormatHotkeyLabel(cfg.hotkeys.incLine)
		if (cfg.hotkeys.decLine)
			lineWidthKeys .= (lineWidthKeys ? " / " : "") FormatHotkeyLabel(cfg.hotkeys.decLine)
		lineWidthTip .= "`nHotkeys: " lineWidthKeys
	}
	lineWidthTip .= "`nMouse wheel: change width"
	CtrlToolTip(ui.lineWidthCtrl, lineWidthTip)
	CtrlToolTip(lineWidthSpin, lineWidthTip)

	opacityTip := "Opacity (0-255)"
	CtrlToolTip(ui.drawAlphaCtrl, opacityTip)
	CtrlToolTip(drawAlphaSpin, opacityTip)

	undoTip := "Undo last shape"
	if (cfg.hotkeys.undo)
		undoTip .= "`nHotkey: " FormatHotkeyLabel(cfg.hotkeys.undo)
	undoTip .= "`nMouse: XButton1"
	CtrlToolTip(btnUndo, undoTip)

	redoTip := "Redo last shape"
	if (cfg.hotkeys.redo)
		redoTip .= "`nHotkey: " FormatHotkeyLabel(cfg.hotkeys.redo)
	redoTip .= "`nMouse: XButton2"
	CtrlToolTip(btnRedo, redoTip)

	clearTip := "Clear drawing"
	if (cfg.hotkeys.clear)
		clearTip .= "`nHotkey: " FormatHotkeyLabel(cfg.hotkeys.clear)
	CtrlToolTip(btnClear, clearTip)

	helpTip := "Show help"
	if (cfg.hotkeys.help)
		helpTip .= "`nHotkey: " FormatHotkeyLabel(cfg.hotkeys.help)
	CtrlToolTip(btnHelp, helpTip)

	CtrlToolTip(btnExitDraw, "Exit drawing mode")

	exitAppTip := "Exit application"
	if (cfg.hotkeys.exit)
		exitAppTip .= "`nHotkey: " FormatHotkeyLabel(cfg.hotkeys.exit)
	CtrlToolTip(btnExitApp, exitAppTip)
}

_UpdateDrawToolbar() {
	activeRGB := draw.color & 0xFFFFFF
	for val, chkCtrl in ui.colorMarks {
		chkCtrl.Text := (val = activeRGB) ? "✓" : ""
	}
	if (ui.lineWidthCtrl.Value != cfg.line.width)
		ui.lineWidthCtrl.Value := cfg.line.width
	if (ui.drawAlphaCtrl.Value != cfg.drawAlpha)
		ui.drawAlphaCtrl.Value := cfg.drawAlpha
}

ColorSelect(colorVal, *) {
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

; Drawing Operations
ClearDrawing(*) {
	if (!state.drawingMode)
		return

	if (state.drawing) {
		state.drawing := false
		draw.currentShape := {}
		DllCall("ReleaseCapture")
		SetTimer(UpdateTimer, 0)
	}

	_FindLastClearOrFill(&lastClearIdx, &lastFillColor)
	if (lastClearIdx >= draw.history.Length)
		return

	while (draw.history.Length >= cfg.maxHistorySize)
		draw.history.RemoveAt(1)
	if (lastFillColor >= 0)
		draw.history.Push({ type: "fill", color: lastFillColor })
	else
		draw.history.Push({ type: "clear" })
	draw.redoStack := []

	RefreshBakedBuffer()
	UpdateBuffer()
	InvalidateOverlay()
}

DeleteLastShape(*) {
	if (!state.drawingMode || !draw.history.Length)
		return
	draw.redoStack.Push(draw.history.Pop())
	RefreshBakedBuffer()
	UpdateBuffer()
	InvalidateOverlay()
}

RedoLastShape(*) {
	if (!state.drawingMode || !draw.redoStack.Length)
		return
	item := draw.redoStack.Pop()
	draw.history.Push(item)
	RefreshBakedBuffer()
	UpdateBuffer()
	InvalidateOverlay()
}

AdjustLineWidth(delta) {
	static _clearTip := () => ToolTip()
	if (!state.drawingMode)
		return
	cfg.line.width := Max(Min(cfg.line.width + delta, cfg.line.maxWidth), cfg.line.minWidth)
	ToolTip("Width: " cfg.line.width)
	SetTimer(_clearTip, -1000)
}

SetDrawColor(colorRGB, *) {
	if (!state.drawingMode)
		return
	rgb := colorRGB & 0xFFFFFF
	draw.color := ARGB(rgb, cfg.drawAlpha)
}

FillBackground(colorRGB, *) {
	if (!state.drawingMode)
		return
	fillShape := { type: "fill", color: colorRGB & 0xFFFFFF }
	draw.redoStack := []
	while (draw.history.Length >= cfg.maxHistorySize)
		draw.history.RemoveAt(1)
	draw.history.Push(fillShape)
	RefreshBakedBuffer()
	UpdateBuffer()
	InvalidateOverlay()
}

; Timer & Buffer Update
UpdateTimer() {
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

; Monitor / Coordinate Helpers
IsMouseOnActiveMonitor() {
	if (!IsObject(state.monitor) || state.monitor.width <= 0 || state.monitor.height <= 0)
		return false
	MouseGetPos(&mX, &mY)
	return (mX >= state.monitor.left && mX < state.monitor.right
		&& mY >= state.monitor.top && mY < state.monitor.bottom)
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
