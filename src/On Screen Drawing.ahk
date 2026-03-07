;@Ahk2Exe-SetName On Screen Drawing Tool
;@Ahk2Exe-SetDescription Lightweight screen annotation tool
;@Ahk2Exe-SetFileVersion 1.3.0
;@Ahk2Exe-SetCompanyName akcanSoft
;@Ahk2Exe-SetCopyright ©2026 Mesut Akcan
;@Ahk2Exe-SetMainIcon app_icon.ico

/*
=========================
On Screen Drawing Tool
=========================
A lightweight on-screen drawing tool for annotating the screen with
lines, rectangles, ellipses, circles, and freehand drawings.
=========================
Date: 07/03/2026
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
#Include "Gdip_all.ahk"

; Set custom icon for the tray menu
if (!A_IsCompiled)
	try TraySetIcon(A_ScriptDir "\app_icon.ico")

InitDpiAwareness()
CoordMode("Mouse", "Screen")

App := {
	Name: "akcanSoft On Screen Drawing Tool",
	Version: "1.3.0",
	iniPath: A_ScriptDir "\settings.ini"
}

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
				parts := StrSplit(line, "=")
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

	static GetDefaultIniSection() {
		str := "[Colors]`n"
		for item in this.Defaults
			str .= item.hk "=" Format("0x{:06X}", item.val) "`n"
		return str
	}
}

global cfg := {
	line: {
		minWidth: ReadIniInt("Settings", "MinLineWidth", 1),
		maxWidth: ReadIniInt("Settings", "MaxLineWidth", 10),
		width: ReadIniInt("Settings", "StartupLineWidth", 2)
	},
	drawAlpha: ReadIniInt("Settings", "DrawAlpha", 200),
	frameIntervalMs: ReadIniInt("Settings", "FrameIntervalMs", 16),
	minPointStep: ReadIniInt("Settings", "MinPointStep", 3),
	clearOnExit: ReadIniBool("Settings", "ClearOnExit", false),
	showColorHints: ReadIniBool("Settings", "ShowColorHints", true)
}
cfg.line.minWidth := Max(cfg.line.minWidth, 1)
if (cfg.line.maxWidth < cfg.line.minWidth)
	cfg.line.maxWidth := cfg.line.minWidth
cfg.line.width := Max(Min(cfg.line.width, cfg.line.maxWidth), cfg.line.minWidth)
cfg.drawAlpha := Max(Min(cfg.drawAlpha, 255), 0)
cfg.frameIntervalMs := Max(cfg.frameIntervalMs, 1)
cfg.minPointStep := Max(cfg.minPointStep, 1)

global hotkeys := {
	toggle: IniRead(App.iniPath, "Hotkeys", "ToggleDrawingMode", "^F9"),
	exit: IniRead(App.iniPath, "Hotkeys", "ExitApp", "^+F12"),
	clear: IniRead(App.iniPath, "Hotkeys", "ClearDrawing", "Esc"),
	undo: IniRead(App.iniPath, "Hotkeys", "UndoDrawing", "Backspace"),
	redo: IniRead(App.iniPath, "Hotkeys", "RedoDrawing", "+Backspace"),
	incLine: IniRead(App.iniPath, "Hotkeys", "IncreaseLineWidth", "^NumpadAdd"),
	decLine: IniRead(App.iniPath, "Hotkeys", "DecreaseLineWidth", "^NumpadSub"),
	help: IniRead(App.iniPath, "Hotkeys", "HotkeysHelp", "F1")
}

DrawingColors.Load()

global state := {
	drawingMode: false,
	drawing: false,
	needsUpdate: false,
	cursorActive: false,
	lastMonitorNum: 0,
	monitor: { num: 0, left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 }
}

global draw := {
	color: ARGB(DrawingColors.List[1].val, cfg.drawAlpha),
	startX: 0,
	startY: 0,
	currentShape: {},
	history: [],
	redoStack: []
}

global ui := {
	overlayGui: "",
	settingsGui: "",
	colorMarks: Map(),
	lineWidthCtrl: "",
	drawAlphaCtrl: "",
	trayLabel: ""
}

class GDIContext {
	isDestroyed := false
	token := 0
	hBitmapBackground := 0
	hdcMem := 0
	hbmBuffer := 0
	hbmDefault := 0
	G_Mem := 0
	G_Baked := 0
	hdcBaked := 0
	hbmBaked := 0
	hbmBakedDefault := 0

	; Startup GDI+
	Init() {
		try {
			this.isDestroyed := false
			this.token := Gdip_Startup()
		} catch Error as e {
			MsgBox("GDI+ Error: " e.Message, "Error", 48)
			ExitApp
		}
	}

	; Create resources for a specific monitor
	CreateBuffer(monNum, width, height) {
		this.DestroyBuffer()

		this.hBitmapBackground := Gdip_BitmapFromScreen(monNum)
		if (this.hBitmapBackground <= 0) {
			this.hBitmapBackground := 0
			throw Error("Failed to capture screen.")
		}

		hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
		this.hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
		this.hbmBuffer := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", width, "Int", height, "Ptr")
		this.hdcBaked := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
		this.hbmBaked := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", width, "Int", height, "Ptr")
		DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

		if (!this.hdcMem || !this.hbmBuffer || !this.hdcBaked || !this.hbmBaked) {
			this.DestroyBuffer()
			throw Error("Failed to create memory DC or bitmap.")
		}

		this.hbmDefault := DllCall("SelectObject", "Ptr", this.hdcMem, "Ptr", this.hbmBuffer, "Ptr")
		this.hbmBakedDefault := DllCall("SelectObject", "Ptr", this.hdcBaked, "Ptr", this.hbmBaked, "Ptr")

		this.G_Mem := Gdip_GraphicsFromHDC(this.hdcMem)
		this.G_Baked := Gdip_GraphicsFromHDC(this.hdcBaked)

		if (!this.G_Mem || !this.G_Baked) {
			this.DestroyBuffer()
			throw Error("Failed to get GDI+ graphics context.")
		}

		Gdip_SetSmoothingMode(this.G_Mem, 4)
		Gdip_SetSmoothingMode(this.G_Baked, 4)
	}

	; Cleanup only the drawing buffers (when switching monitors or exiting drawing mode)
	DestroyBuffer() {
		if (this.G_Mem) {
			Gdip_DeleteGraphics(this.G_Mem)
			this.G_Mem := 0
		}
		if (this.hdcMem) {
			if (this.hbmBuffer) {
				if (this.hbmDefault && this.hbmDefault != -1)
					DllCall("SelectObject", "Ptr", this.hdcMem, "Ptr", this.hbmDefault)
				DllCall("DeleteObject", "Ptr", this.hbmBuffer)
				this.hbmBuffer := 0
			}
			this.hbmDefault := 0
			DllCall("DeleteDC", "Ptr", this.hdcMem)
			this.hdcMem := 0
		}
		if (this.G_Baked) {
			Gdip_DeleteGraphics(this.G_Baked)
			this.G_Baked := 0
		}
		if (this.hdcBaked) {
			if (this.hbmBaked) {
				if (this.hbmBakedDefault && this.hbmBakedDefault != -1)
					DllCall("SelectObject", "Ptr", this.hdcBaked, "Ptr", this.hbmBakedDefault)
				DllCall("DeleteObject", "Ptr", this.hbmBaked)
				this.hbmBaked := 0
			}
			this.hbmBakedDefault := 0
			DllCall("DeleteDC", "Ptr", this.hdcBaked)
			this.hdcBaked := 0
		}
		if (this.hBitmapBackground) {
			Gdip_DisposeImage(this.hBitmapBackground)
			this.hBitmapBackground := 0
		}
	}

	; Full cleanup including GDI+ shutdown
	Destroy() {
		if (this.isDestroyed)
			return

		this.isDestroyed := true
		this.DestroyBuffer()
		if (this.token) {
			Gdip_Shutdown(this.token)
			this.token := 0
		}
	}

	__Delete() => this.Destroy()
}

global gdi := GDIContext()

gdi.Init() ; Initialize GDI+

OnExit((*) => ExitDrawingMode(true))

; Event Listeners
OnMessage(0x201, WM_LBUTTONDOWN) ; Left button down
OnMessage(0x202, WM_LBUTTONUP)   ; Left button up
OnMessage(0x200, WM_MOUSEMOVE)   ; Mouse move
OnMessage(0x204, WM_RBUTTONDOWN) ; Right button down (for settings)
OnMessage(0x0F, WM_PAINT_Handler)
OnMessage(0x14, WM_ERASEBKGND_Handler)

InitTrayMenu()

; Hotkeys
if hotkeys.toggle
	Hotkey(hotkeys.toggle, ToggleDrawingMode)
if hotkeys.exit
	Hotkey(hotkeys.exit, (*) => ExitApp())
if hotkeys.help
	Hotkey(hotkeys.help, ShowHotkeysHelp)

HotIf (*) => WinActive("ahk_id " (ui.settingsGui ? ui.settingsGui.Hwnd : 0))
Hotkey("Esc", CloseSettingsGui)

HotIf (*) => state.drawingMode && IsMouseOnActiveMonitor() && !WinActive("ahk_class #32770") && !WinActive("ahk_id " (
	ui.settingsGui ? ui.settingsGui.Hwnd : 0))
if hotkeys.clear
	Hotkey(hotkeys.clear, ClearDrawing)
if hotkeys.redo
	Hotkey(hotkeys.redo, RedoLastShape)
if hotkeys.incLine
	Hotkey(hotkeys.incLine, AdjustLineWidthUp)
if hotkeys.decLine
	Hotkey(hotkeys.decLine, AdjustLineWidthDown)
Hotkey("XButton1", DeleteLastShape)
Hotkey("XButton2", RedoLastShape)

for item in DrawingColors.List
	Hotkey(item.hk, SetDrawColor.Bind(item.val))

; Mouse wheel settings
HotIf (*) => state.drawingMode && IsMouseOnActiveMonitor() && !WinActive("ahk_id " (ui.settingsGui ? ui.settingsGui.Hwnd :
	0)) && !WinActive("ahk_class #32770")
if hotkeys.undo
	Hotkey(hotkeys.undo, DeleteLastShape)
Hotkey("WheelUp", AdjustLineWidthUp)
Hotkey("WheelDown", AdjustLineWidthDown)
HotIf

;=============================================
CloseSettingsGui(*) {
	_ManageSettingsGui("hide")
}

; Centralized management for Settings GUI (Hide or Destroy)
_ManageSettingsGui(action := "hide", restoreCursor := true) {
	global ui, state

	if (!IsObject(ui.settingsGui))
		return

	try {
		if (action = "destroy") {
			ui.settingsGui.Destroy()
			ui.settingsGui := ""
			ui.colorMarks.Clear()
			ui.lineWidthCtrl := ""
			ui.drawAlphaCtrl := ""
		} else {
			if (ui.settingsGui.Hwnd)
				ui.settingsGui.Hide()
		}
	} catch Error as e {
		OutputDebug("_ManageSettingsGui Error: " e.Message)
	}

	if (restoreCursor && state.drawingMode && IsObject(ui.overlayGui))
		EnableDrawingCursor()
}

OnSettingsGuiClose(*) {
	_ManageSettingsGui("hide")
}

; Helper to reset settings font
_ResetUISettingsFont() => ui.settingsGui.SetFont("s9 w400", "Segoe UI")

AdjustLineWidthUp(*) => AdjustLineWidth(1)
AdjustLineWidthDown(*) => AdjustLineWidth(-1)

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

InitTrayMenu() {
	hkSuffix := "`t" FormatHotkeyLabel(hotkeys.toggle)
	ui.trayLabel := (state.drawingMode ? "Stop Drawing" : "Start Drawing") . hkSuffix

	A_TrayMenu.Delete()
	A_TrayMenu.Add("About", (*) => About())
	A_TrayMenu.Add("Hotkeys Help`t" . FormatHotkeyLabel(hotkeys.help), ShowHotkeysHelp)
	A_TrayMenu.Add("GitHub repo", (*) => Run("https://github.com/akcansoft/On-Screen-Drawing-Tool"))
	A_TrayMenu.Add()
	A_TrayMenu.Add("Open settings.ini", OpenSettingsIniFromTray)
	A_TrayMenu.Add("Reset to Defaults", ResetDefaultsFromTray)
	A_TrayMenu.Add("Reload Script", (*) => Reload())
	A_TrayMenu.Add()
	A_TrayMenu.Add(ui.trayLabel, StartDrawingFromTray)
	A_TrayMenu.Add("Exit`t" . FormatHotkeyLabel(hotkeys.exit), (*) => ExitApp())
	A_TrayMenu.Default := ui.trayLabel
}

UpdateTrayToggleMenu() {
	hkSuffix := "`t" FormatHotkeyLabel(hotkeys.toggle)
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

; Open settings.ini in default text editor from tray menu
OpenSettingsIniFromTray(*) {
	if (!FileExist(App.iniPath)) {
		MsgBox("settings.ini not found:`n" App.iniPath, "Error", 48)
		return
	}
	Run('notepad.exe "' App.iniPath '"')
}

; Helper to format hotkey labels for display (e.g. "^+F12" -> "Ctrl+Shift+F12")
FormatHotkeyLabel(hk) {
	if (hk = "")
		return ""

	label := StrReplace(hk, "+", "{SHIFT}")
	label := StrReplace(label, "^", "Ctrl+")
	label := StrReplace(label, "!", "Alt+")
	label := StrReplace(label, "#", "Win+")
	label := StrReplace(label, "{SHIFT}", "Shift+")
	return label
}

; Reset settings.ini to defaults from tray menu
ResetDefaultsFromTray(*) {
	if (MsgBox("Reset settings.ini to defaults and reload the script?", "Reset to Defaults", "YesNo Icon!") != "Yes")
		return

	try {
		defaultIni := "[Settings]`n"
			. "StartupLineWidth=2`n"
			. "MinLineWidth=1`n"
			. "MaxLineWidth=10`n"
			. "DrawAlpha=200`n"
			. "FrameIntervalMs=16`n"
			. "MinPointStep=3`n"
			. "ClearOnExit=false`n"
			. "ShowColorHints=true`n`n"
			. "[Hotkeys]`n"
			. "ToggleDrawingMode=^F9`n"
			. "ExitApp=^+F12`n"
			. "ClearDrawing=Esc`n"
			. "UndoDrawing=Backspace`n"
			. "RedoDrawing=+Backspace`n"
			. "IncreaseLineWidth=^NumpadAdd`n"
			. "DecreaseLineWidth=^NumpadSub`n"
			. "HotkeysHelp=F1`n`n"
			. DrawingColors.GetDefaultIniSection()

		f := FileOpen(App.iniPath, "w", "UTF-8")
		if (!f)
			throw Error("Unable to open settings.ini for write: " App.iniPath)
		f.Write(defaultIni)
		f.Close()
	} catch Error as e {
		MsgBox("Failed to reset settings.ini:`n" e.Message, "Error", 48)
		return
	}

	Reload()
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

	monitorChanged := (state.lastMonitorNum != 0 && state.lastMonitorNum != mon.Num)
	state.monitor := {
		num: Integer(mon.Num),
		left: mon.Left,
		top: mon.Top,
		right: mon.Right,
		bottom: mon.Bottom,
		width: mon.Width,
		height: mon.Height
	}

	; Temporarily hide old overlay if it exists (to take a clean screenshot)
	if (IsObject(ui.overlayGui)) {
		ui.overlayGui.Hide()
		Sleep(50)
	}

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
	state.lastMonitorNum := state.monitor.num
	if (monitorChanged) {
		draw.history := []
		draw.redoStack := []
	}

	RefreshBakedBuffer()
	UpdateBuffer()

	; Transparent, clickable overlay window
	ui.overlayGui := Gui("+AlwaysOnTop -DPIScale -Caption +ToolWindow +E0x20")
	ui.overlayGui.OnEvent("Close", (*) => ExitDrawingMode(false))
	ui.overlayGui.Title := "Drawing Overlay"
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

	if (IsObject(ui.overlayGui)) {
		ui.overlayGui.Destroy()
		ui.overlayGui := ""
	}
	_ManageSettingsGui("destroy", false)

	if (cfg.clearOnExit) {
		draw.history := []
		draw.redoStack := []
	}

	if (UserInitiated)
		gdi.Destroy()
	else
		gdi.DestroyBuffer()

	state.monitor := {
		num: 0,
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
	global state
	static OCR_NORMAL := 32512
	static IDC_PEN := 32631

	if (state.cursorActive)
		return true

	; Replace only the normal arrow cursor with the system pen cursor.
	hPen := DllCall("LoadCursor", "Ptr", 0, "Ptr", IDC_PEN, "Ptr")
	if (!hPen)
		return false

	hCopy := DllCall("CopyIcon", "Ptr", hPen, "Ptr")
	if (!hCopy)
		return false

	if (!DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", OCR_NORMAL)) {
		DllCall("DestroyIcon", "Ptr", hCopy)
		return false
	}

	state.cursorActive := true
	return true
}

InvalidateOverlay() {
	global ui
	if (IsObject(ui.overlayGui))
		DllCall("InvalidateRect", "Ptr", ui.overlayGui.Hwnd, "Ptr", 0, "Int", 0)
}

DisableDrawingCursor() {
	global state
	static SPI_SETCURSORS := 0x57

	if (!state.cursorActive)
		return true

	if (!DllCall("SystemParametersInfo", "UInt", SPI_SETCURSORS, "UInt", 0, "Ptr", 0, "UInt", 0))
		return false

	state.cursorActive := false
	return true
}

ReadIniInt(section, key, default := 0) {
	try return Integer(IniRead(App.iniPath, section, key, default))
	catch
		return Integer(default)
}

ReadIniBool(section, key, default := false) {
	raw := Trim(IniRead(App.iniPath, section, key, ""))
	if (raw == "")
		return !!default
	norm := StrLower(raw)
	if (norm = "1" || norm = "true" || norm = "yes" || norm = "on")
		return true
	if (norm = "0" || norm = "false" || norm = "no" || norm = "off")
		return false
	if RegExMatch(norm, "^-?\d+$")
		return Integer(norm) != 0
	return !!default
}

; WM Message Handlers
WM_ERASEBKGND_Handler(wParam, lParam, msg, hwnd) {
	global ui
	; Prevent white flickering in the overlay window
	if (IsObject(ui.overlayGui) && hwnd == ui.overlayGui.Hwnd)
		return 1
}

WM_PAINT_Handler(wParam, lParam, msg, hwnd) {
	global ui, gdi, state

	if (!state.drawingMode || !IsObject(ui.overlayGui) || hwnd != ui.overlayGui.Hwnd || !gdi.hdcMem || state.monitor.width <=
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

	if (!state.drawingMode || !IsObject(ui.overlayGui))
		return

	if (IsObject(ui.settingsGui) && ui.settingsGui.Hwnd) {
		if (hwnd = ui.settingsGui.Hwnd || DllCall("IsChild", "Ptr", ui.settingsGui.Hwnd, "Ptr", hwnd, "Int"))
			return
	}

	if (hwnd != ui.overlayGui.Hwnd)
		return

	; Close settings window if open and clicked outside
	if (IsObject(ui.settingsGui) && ui.settingsGui.Hwnd) {
		_ManageSettingsGui("hide")
	}

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
	draw.startX := x, draw.startY := y

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
		draw.currentShape.pointsStr := x "," y
	}

	state.needsUpdate := false
	SetTimer(UpdateTimer, cfg.frameIntervalMs)
	DllCall("SetCapture", "Ptr", hwnd)
}

WM_LBUTTONUP(wParam, lParam, msg, hwnd) {
	global ui, state, draw

	if (!state.drawingMode || !IsObject(ui.overlayGui) || hwnd != ui.overlayGui.Hwnd)
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
		draw.history.Push(shapeToFinalize)
		if (!_AppendShapeToBaked(shapeToFinalize))
			RefreshBakedBuffer()
	}

	UpdateBuffer()
	InvalidateOverlay()
	state.needsUpdate := false
}

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
	global ui, state, draw, cfg

	if (!state.drawing || !state.drawingMode || !IsObject(ui.overlayGui) || hwnd != ui.overlayGui.Hwnd)
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
		draw.currentShape.endX := x
		draw.currentShape.endY := y
		if (draw.currentShape.type = "circle")
			draw.currentShape.radius := Max(Abs(x - draw.startX), Abs(y - draw.startY))
		state.needsUpdate := true
	}
}

WM_RBUTTONDOWN(wParam, lParam, msg, hwnd) {
	global ui, state

	if (!state.drawingMode || !IsObject(ui.overlayGui) || hwnd != ui.overlayGui.Hwnd)
		return

	DisableDrawingCursor()

	if (!IsObject(ui.settingsGui) || !ui.settingsGui.Hwnd)
		_CreateSettingsGui()

	_UpdateSettingsGui()

	MouseGetPos(&mX, &mY)
	ui.settingsGui.Show("AutoSize x" mX " y" mY)
	WinGetPos(, , &w, &h, "ahk_id " ui.settingsGui.Hwnd)
	minX := state.monitor.left
	minY := state.monitor.top
	maxX := Max(minX, state.monitor.right - w)
	maxY := Max(minY, state.monitor.bottom - h)
	finalX := Min(Max(mX, minX), maxX)
	finalY := Min(Max(mY, minY), maxY)
	if (finalX != mX || finalY != mY)
		WinMove(finalX, finalY, , , "ahk_id " ui.settingsGui.Hwnd)
}

_CreateSettingsGui() {
	global ui, cfg
	ui.settingsGui := Gui("+AlwaysOnTop +ToolWindow -Caption Border +Owner" ui.overlayGui.Hwnd)
	ui.settingsGui.Title := "Drawing Settings"
	ui.settingsGui.OnEvent("Close", OnSettingsGuiClose)
	_ResetUISettingsFont()
	margin := 10
	btnSize := 30
	gap := 4
	colorColumnCount := 3

	ui.colorMarks.Clear()
	curY := margin
	for i, item in DrawingColors.List {
		val := item.val
		hkLetter := StrUpper(item.hk)
		hex := Format("{:06X}", val)
		col := Mod(i - 1, colorColumnCount)
		row := (i - 1) // colorColumnCount

		bx := margin + col * (btnSize + gap)
		by := curY + row * (btnSize + gap)
		btn := ui.settingsGui.Add("Text", "x" bx " y" by " w" btnSize " h" btnSize " +Border +0x0100 Background" hex)

		luminance := GetLuminance(val)
		markColor := (luminance > 128) ? "000000" : "FFFFFF"

		; Selection checkmark (Center)
		ui.settingsGui.SetFont("s16 w1000")
		chk := ui.settingsGui.AddText("xp yp wp hp +Center +0x200 c" markColor " BackgroundTrans", "")

		; Shortcut hint (Bottom-left)
		if (cfg.showColorHints) {
			ui.settingsGui.SetFont("s7 w700")
			ui.settingsGui.AddText("x" bx + 2 " y" by + btnSize - 13 " w15 h12 c" markColor " BackgroundTrans",
				hkLetter)
		}

		_ResetUISettingsFont()

		btn.OnEvent("Click", ColorSelect.Bind(val))
		chk.OnEvent("Click", ColorSelect.Bind(val))
		ui.colorMarks[val] := chk
	}

	rowCount := Ceil(DrawingColors.List.Length / colorColumnCount)
	gridBottom := curY + rowCount * (btnSize + gap)

	; Line width control
	ui.settingsGui.AddText("x" margin " y" (gridBottom + 5), "Line width:")
	ui.lineWidthCtrl := ui.settingsGui.AddEdit("vLineWidth yp-5 w40 x+2 Number", cfg.line.width)
	ui.lineWidthCtrl.OnEvent("Change", (*) => UpdateLineWidth(ui.settingsGui))
	ui.settingsGui.AddUpDown("Range" cfg.line.minWidth "-" cfg.line.maxWidth, cfg.line.width).OnEvent("Change", (*) =>
		UpdateLineWidth(ui.settingsGui))

	; Opacity control
	ui.settingsGui.AddText("x" margin " y+12", "Opacity:")
	ui.drawAlphaCtrl := ui.settingsGui.AddEdit("vDrawAlpha yp-5 w50 x+6 Number", cfg.drawAlpha)
	ui.drawAlphaCtrl.OnEvent("Change", (*) => UpdateDrawAlpha(ui.settingsGui))
	ui.settingsGui.AddUpDown("Range0-255", cfg.drawAlpha).OnEvent("Change", (*) => UpdateDrawAlpha(ui.settingsGui))

	; Quick actions (symbol buttons)
	btnOpt := " w30 h30 +Border +Center +0x200 +0x100 BackgroundFAFAFA"
	iconFont := "Segoe MDL2 Assets"
	try {
		RegRead("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts", "Segoe Fluent Icons (TrueType)")
		iconFont := "Segoe Fluent Icons"
	}
	ui.settingsGui.SetFont("s14 c2b8600", iconFont)
	btnUndo := ui.settingsGui.AddText("x10 y+5" btnOpt, Chr(0xE7A7))
	btnRedo := ui.settingsGui.AddText("x+" gap " yp" btnOpt, Chr(0xE7A6))
	ui.settingsGui.SetFont("c0059ff")
	btnClear := ui.settingsGui.AddText("x+" gap " yp" btnOpt, Chr(0xED62)) ; E74D EF19

	; Last row buttons: Help, Exit Drawing, Exit App
	btnHelp := ui.settingsGui.AddText("x10 y+5" btnOpt, Chr(0xE897))
	btnExitDraw := ui.settingsGui.AddText("x+" gap " yp" btnOpt, Chr(0xEE56))
	ui.settingsGui.SetFont("cff0000")
	btnExitApp := ui.settingsGui.AddText("x+" gap " yp" btnOpt, Chr(0xE7E8)) ; ⏻

	btnExitDraw.GetPos(&dX, &dY, &dW, &dH)
	ui.settingsGui.SetFont("s20")
	chkExit := ui.settingsGui.AddText("x" dX - 5 " y" dY - 10 " w" dW " h" dH " cRed +Center +0x200 BackgroundTrans +E0x20",
		"✕")
	_ResetUISettingsFont()

	btnUndo.OnEvent("Click", (*) => DeleteLastShape())
	btnUndo.OnEvent("DoubleClick", (*) => DeleteLastShape())
	btnRedo.OnEvent("Click", (*) => RedoLastShape())
	btnRedo.OnEvent("DoubleClick", (*) => RedoLastShape())
	btnClear.OnEvent("Click", (*) => ClearDrawing())
	btnHelp.OnEvent("Click", (*) => ShowHotkeysHelp())
	btnExitDraw.OnEvent("Click", (*) => ExitDrawingFromSettings())
	btnExitApp.OnEvent("Click", (*) => ExitAppFromSettings())
	chkExit.OnEvent("Click", (*) => ExitDrawingFromSettings())
}

_UpdateSettingsGui() {
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
	_ManageSettingsGui("hide")
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

ExitDrawingFromSettings(*) {
	_ManageSettingsGui("hide", false)
	ExitDrawingMode(false)
}

ExitAppFromSettings(*) {
	_ManageSettingsGui("hide", false)
	ExitApp()
}

ClearDrawing(*) {
	global ui, gdi, state, draw
	if (!state.drawingMode || !draw.history.Length)
		return

	savedShapes := draw.history
	draw.history := [{ type: "clear", shapes: savedShapes }]
	draw.redoStack := []

	; Clear the baked graphics properly before redrawing the background
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

	item := draw.history.Pop()
	if (item.HasProp("type") && item.type == "clear") {
		draw.history := item.shapes
	}
	draw.redoStack.Push(item)

	; Clear the baked graphics properly before redrawing everything, otherwise removed shapes leave artifacts
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

	item := draw.redoStack.Pop()
	if (item.HasProp("type") && item.type == "clear") {
		draw.history := [item]
	} else {
		draw.history.Push(item)
	}

	if (!_AppendShapeToBaked(item)) {
		if (gdi.G_Baked)
			DllCall("gdiplus\GdipGraphicsClear", "UPtr", gdi.G_Baked, "Int", 0)
		RefreshBakedBuffer()
	}
	UpdateBuffer()
	InvalidateOverlay()
}

AdjustLineWidth(delta) {
	if (!state.drawingMode)
		return
	cfg.line.width := Max(Min(cfg.line.width + delta, cfg.line.maxWidth), cfg.line.minWidth)
	ToolTip("Width: " cfg.line.width)
	SetTimer(HideToolTip, -1000)
}

HideToolTip() {
	ToolTip()
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
	if (!state.drawingMode || !IsObject(ui.overlayGui)) {
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
	Gdip_DrawImage(gdi.G_Baked, gdi.hBitmapBackground, 0, 0, state.monitor.width, state.monitor.height)
	DrawShapesToGraphics(gdi.G_Baked, draw.history)
}

_AppendShapeToBaked(shape) {
	global gdi, state
	if (!IsObject(shape) || !shape.HasProp("type") || shape.type == "clear")
		return false
	if (!gdi.G_Baked || !gdi.hBitmapBackground || state.monitor.width <= 0 || state.monitor.height <= 0)
		return false
	DrawShapesToGraphics(gdi.G_Baked, [shape])
	return true
}

IsMouseOnActiveMonitor() {
	global state
	if (!IsObject(state.monitor) || state.monitor.width <= 0 || state.monitor.height <= 0)
		return false
	MouseGetPos(&mX, &mY)
	return (mX >= state.monitor.left && mX < state.monitor.right && mY >= state.monitor.top && mY < state.monitor.bottom)
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

SignedInt16(v) {
	v := v & 0xFFFF
	return (v & 0x8000) ? (v - 0x10000) : v
}

; Shape Drawing
BuildPointsStr(points) {
	if (!IsObject(points) || points.Length < 2)
		return ""
	str := points[1][1] "," points[1][2]
	loop points.Length - 1
		str .= "|" points[A_Index + 1][1] "," points[A_Index + 1][2]
	return str
}

DrawShapesToGraphics(G, shapesArray) {
	lastPenColor := -1, lastPenWidth := -1, pPen := 0
	lastBrushColor := -1, pBrush := 0

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

		if (shape.type = "arrow" && shape.color != lastBrushColor) {
			if (pBrush)
				Gdip_DeleteBrush(pBrush)
			pBrush := Gdip_BrushCreateSolid(shape.color)
			lastBrushColor := shape.color
		}

		try {
			switch shape.type {
				case "free":
					if (shape.HasProp("points") && shape.points.Length >= 2) {
						if (!shape.HasProp("pointsStr"))
							shape.pointsStr := BuildPointsStr(shape.points)
						Gdip_DrawLines(G, pPen, shape.pointsStr)
					}
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
					if (pBrush) {
						DrawArrowGdip(G, pPen, pBrush, shape.startX, shape.startY, shape.endX, shape.endY, shape.width)
					}
			}
		} catch Error as e {
			OutputDebug("GDI+ Drawing Error [type=" shape.type ", idx=" index "]: " e.Message "`n")
		}
	}

	if (pPen)
		Gdip_DeletePen(pPen)
	if (pBrush)
		Gdip_DeleteBrush(pBrush)
}

; Draw an arrow from (x1, y1) to (x2, y2) with specified width and cached brush
DrawArrowGdip(G, pPen, pBrush, x1, y1, x2, y2, width) {
	dx := x2 - x1
	dy := y2 - y1
	len := Sqrt((dx * dx) + (dy * dy))
	if (len <= 3)
		return

	hLen := 12 + (width * 4)

	; If the segment is shorter than the arrowhead itself, draw a plain line
	if (len <= hLen) {
		DllCall("gdiplus\GdipSetPenEndCap", "UPtr", pPen, "Int", 0)
		Gdip_DrawLine(G, pPen, x1, y1, x2, y2)
		return
	}

	hWid := Max(hLen * 0.5236, 8) ; 0.5236 = 30 deg.
	halfWid := hWid / 2

	ux := dx / len
	uy := dy / len
	perpX := -uy
	perpY := ux

	bx := x2 - (ux * hLen), by := y2 - (uy * hLen)
	W1 := perpX * halfWid, W2 := perpY * halfWid

	DllCall("gdiplus\GdipSetPenEndCap", "UPtr", pPen, "Int", 0)  ; Flat cap
	Gdip_DrawLine(G, pPen, x1, y1, bx, by)

	pPoints := x2 "," y2 "|" (bx + W1) "," (by + W2) "|" (bx - W1) "," (by - W2)
	Gdip_FillPolygon(G, pBrush, pPoints)
}

; Combine Alpha + RGB — alpha is always passed explicitly
ARGB(rgb, a) => (a << 24) | (rgb & 0xFFFFFF)

; Calculate perceived brightness for a color (0-255) — used to determine contrasting checkmark color in settings
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

; Show hotkeys help message box
ShowHotkeysHelp(*) {
	global hotkeys
	colorKeys := ""
	for item in DrawingColors.List
		colorKeys .= (colorKeys = "" ? FormatHotkeyLabel(item.hk) : ", " FormatHotkeyLabel(item.hk))

	txt := "Hotkeys:"
	if (hotkeys.help)
		txt .= "`n" FormatHotkeyLabel(hotkeys.help) ": Show this help"
	txt .= "`n" FormatHotkeyLabel(hotkeys.toggle) ": Toggle drawing mode"
	if (hotkeys.exit)
		txt .= "`n" FormatHotkeyLabel(hotkeys.exit) ": Exit app"
	if (hotkeys.clear)
		txt .= "`n" FormatHotkeyLabel(hotkeys.clear) ": Clear drawing"
	if (hotkeys.undo)
		txt .= "`n" FormatHotkeyLabel(hotkeys.undo) ": Undo last shape"
	if (hotkeys.redo)
		txt .= "`n" FormatHotkeyLabel(hotkeys.redo) ": Redo last shape`n"
	if (hotkeys.incLine)
		txt .= "`n" FormatHotkeyLabel(hotkeys.incLine) ": Increase line width"
	if (hotkeys.decLine)
		txt .= "`n" FormatHotkeyLabel(hotkeys.decLine) ": Decrease line width"

	txt .= "`nWheelUp/WheelDown: Line width +/-"
	txt .= "`nMouse Back (XButton1): Undo last shape"
	txt .= "`nMouse Forward (XButton2): Redo last shape`n"

	txt .= "`nRight click: Open settings panel"
	txt .= "`nShift: Line"
	txt .= "`nCtrl: Rect"
	txt .= "`nAlt: Ellipse"
	txt .= "`nCtrl+Alt: Circle"
	txt .= "`nCtrl+Shift: Arrow`n"
	if (colorKeys != "")
		txt .= "`nColor hotkeys: " colorKeys

	_TopMostMsgBox(txt, "Hotkeys Help")
}

About(*) {
	txt := "
	(
		©2026 Mesut Akcan 
		makcan@gmail.com
		github.com/akcansoft
		mesutakcan.blogspot.com
		youtube.com/mesutakcan
	)"
	_TopMostMsgBox(txt, "About")
}

; Helper to show a MsgBox that stays on top (modal when drawing, AlwaysOnTop otherwise)
_TopMostMsgBox(text, title, options := "Iconi") {
	global ui
	text := App.Name " v" App.Version "`n`n" text

	ownerHwnd := 0
	settingsHwnd := 0

	if (IsObject(ui.settingsGui) && WinExist("ahk_id " ui.settingsGui.Hwnd))
		settingsHwnd := ui.settingsGui.Hwnd

	if (IsObject(ui.overlayGui) && ui.overlayGui.Hwnd)
		ownerHwnd := ui.overlayGui.Hwnd

	if (ownerHwnd) {
		options .= " Owner" ownerHwnd
		if (settingsHwnd)
			try WinSetEnabled(0, "ahk_id " settingsHwnd)
	} else if (settingsHwnd) {
		options .= " Owner" settingsHwnd
	} else {
		options .= " 0x40000" ; AlwaysOnTop fallback
	}

	result := MsgBox(text, title, options)

	if (ownerHwnd && settingsHwnd)
		try WinSetEnabled(1, "ahk_id " settingsHwnd)

	return result
}
