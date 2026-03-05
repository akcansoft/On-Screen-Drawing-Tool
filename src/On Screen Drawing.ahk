;@Ahk2Exe-SetName On Screen Drawing Tool
;@Ahk2Exe-SetDescription Lightweight screen annotation tool
;@Ahk2Exe-SetFileVersion 1.0.2
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
Version: 1.0.2
Date: 05/03/2026
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

#Include Gdip_all.ahk

; Set custom icon for the tray menu
if (!A_IsCompiled)
	try TraySetIcon(A_ScriptDir "\app_icon.ico")

InitDpiAwareness()
CoordMode("Mouse", "Screen")

; Load Settings from INI
global iniFile := A_ScriptDir "\settings.ini"
global defaultColors := [{ hk: "r", val: 0xFF0000 }, { hk: "g", val: 0x00FF00 }, { hk: "b", val: 0x0000FF }, { hk: "y", val: 0xFFFF00 }, { hk: "m",
	val: 0xFF00FF }, { hk: "c", val: 0x00FFFF }, { hk: "o", val: 0xFFA500 }, { hk: "v", val: 0x7F00FF }, { hk: "s", val: 0x8B4513 }, { hk: "w",
		val: 0xFFFFFF }, { hk: "n", val: 0x808080 }, { hk: "k", val: 0x000000 }]

global cfg := {
	line: {
		minWidth: Integer(IniRead(iniFile, "Settings", "MinLineWidth", "1")),
		maxWidth: Integer(IniRead(iniFile, "Settings", "MaxLineWidth", "10")),
		width: Integer(IniRead(iniFile, "Settings", "StartupLineWidth", "2"))
	},
	drawAlpha: Integer(IniRead(iniFile, "Settings", "DrawAlpha", "200")),
	frameIntervalMs: Integer(IniRead(iniFile, "Settings", "FrameIntervalMs", "16")),
	minPointStep: Integer(IniRead(iniFile, "Settings", "MinPointStep", "3")),
	clearOnExit: ReadIniBool(iniFile, "Settings", "ClearOnExit", false)
}
cfg.line.minWidth := Max(cfg.line.minWidth, 1)
if (cfg.line.maxWidth < cfg.line.minWidth)
	cfg.line.maxWidth := cfg.line.minWidth
cfg.line.width := Max(Min(cfg.line.width, cfg.line.maxWidth), cfg.line.minWidth)

global hotkeys := {
	toggle: IniRead(iniFile, "Hotkeys", "ToggleDrawingMode", "^F9"),
	exit: IniRead(iniFile, "Hotkeys", "ExitApp", "^+F12"),
	clear: IniRead(iniFile, "Hotkeys", "ClearDrawing", "Esc"),
	undo: IniRead(iniFile, "Hotkeys", "UndoDrawing", "Backspace"),
	incLine: IniRead(iniFile, "Hotkeys", "IncreaseLineWidth", "^NumpadAdd"),
	decLine: IniRead(iniFile, "Hotkeys", "DecreaseLineWidth", "^NumpadSub")
}

global colorList := []
global colorHotkeys := Map()

iniReadResult := IniRead(iniFile, "Colors", , "")

if (iniReadResult = "") {
	colorList := defaultColors
	for item in colorList
		colorHotkeys[item.hk] := item.val
} else {
	loop parse, iniReadResult, "`n", "`r" {
		if (A_LoopField = "")
			continue
		parts := StrSplit(A_LoopField, "=")
		if (parts.Length = 2) {
			hk := Trim(parts[1])
			cVal := Integer(Trim(parts[2]))
			colorList.Push({ hk: hk, val: cVal })
			colorHotkeys[hk] := cVal
		}
	}
}

global drawColor := colorList.Length ? ARGB(colorList[1].val, cfg.drawAlpha) : ARGB(0xFF0000, cfg.drawAlpha)
global trayToggleLabel := ""

global drawingMode := false
global drawing := false
global startX := 0, startY := 0
global currentShape := {}
global allShapes := []
global activeMonitor := {
	num: 0,
	left: 0,
	top: 0,
	right: 0,
	bottom: 0,
	width: 0,
	height: 0
}
global lastDrawingMonitorNum := 0

global ui := {
	overlay: "",
	settings: ""
}

global needsUpdate := false

global gdi := {
	token: 0,
	hBitmapBackground: 0,
	hdcMem: 0,
	hbmBuffer: 0,
	hbmDefault: 0,
	G_Mem: 0,
	G_Baked: 0,
	hdcBaked: 0,
	hbmBaked: 0,
	hbmBakedDefault: 0
}

GdiStartup() ; Initialize GDI+

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

HotIf (*) => WinActive("ahk_id " (ui.settings ? ui.settings.Hwnd : 0))
Hotkey("Esc", CloseSettingsGui)

HotIf (*) => drawingMode && IsMouseOnActiveMonitor()
if hotkeys.clear
	Hotkey(hotkeys.clear, ClearDrawing)
if hotkeys.undo
	Hotkey(hotkeys.undo, DeleteLastShape)
if hotkeys.incLine
	Hotkey(hotkeys.incLine, AdjustLineWidthUp)
if hotkeys.decLine
	Hotkey(hotkeys.decLine, AdjustLineWidthDown)

Hotkey("WheelUp", AdjustLineWidthUp)
Hotkey("WheelDown", AdjustLineWidthDown)

for hk, val in colorHotkeys
	Hotkey(hk, SetDrawColor.Bind(val))

HotIf

;=============================================
CloseSettingsGui(*) {
	_DestroySettings()
}

; Helper to destroy settings GUI if it exists
_DestroySettings(guiObj := "") {
	global ui

	target := IsObject(guiObj) ? guiObj : ui.settings
	if (IsObject(target))
		try target.Destroy()

	ui.settings := ""
}

; Helper to reset settings font
_ResetUISettingsFont() => ui.settings.SetFont("s9 w400", "Segoe UI")

AdjustLineWidthUp(*) => AdjustLineWidth(1)
AdjustLineWidthDown(*) => AdjustLineWidth(-1)

; Start/Stop drawing mode from tray menu
StartDrawingFromTray(*) {
	if (drawingMode) {
		ExitDrawingMode(false)
		return
	}
	Sleep(400)  ; Delay to allow tray menu to close before taking screenshot
	ToggleDrawingMode()
}

InitTrayMenu() {
	global trayToggleLabel
	trayToggleLabel := drawingMode ? "Stop Drawing" : "Start Drawing"

	A_TrayMenu.Delete()
	A_TrayMenu.Add("About", (*) => About())
	A_TrayMenu.Add("GitHub repo", (*) => Run("https://github.com/akcansoft/On-Screen-Drawing-Tool"))
	A_TrayMenu.Add()
	A_TrayMenu.Add("Open settings.ini", OpenSettingsIniFromTray)
	A_TrayMenu.Add("Hotkeys Help", ShowHotkeysHelpFromTray)
	A_TrayMenu.Add("Reset to Defaults", ResetDefaultsFromTray)
	A_TrayMenu.Add("Reload Script", (*) => Reload())
	A_TrayMenu.Add()
	A_TrayMenu.Add(trayToggleLabel, StartDrawingFromTray)
	A_TrayMenu.Add("Exit", (*) => ExitApp())
	A_TrayMenu.Default := trayToggleLabel
}

UpdateTrayToggleMenu() {
	global trayToggleLabel
	newLabel := drawingMode ? "Stop Drawing" : "Start Drawing"

	if (trayToggleLabel = newLabel)
		return

	try A_TrayMenu.Rename(trayToggleLabel, newLabel)
	catch {
		InitTrayMenu()
		return
	}
	trayToggleLabel := newLabel
	A_TrayMenu.Default := trayToggleLabel
}

; Open settings.ini in default text editor from tray menu
OpenSettingsIniFromTray(*) {
	if (!FileExist(iniFile)) {
		MsgBox("settings.ini not found:`n" iniFile, "Error", 48)
		return
	}
	Run('notepad.exe "' iniFile '"')
}

; Show hotkeys help message box from tray menu
ShowHotkeysHelpFromTray(*) {
	global hotkeys, colorHotkeys
	colorKeys := ""
	for hk, val in colorHotkeys
		colorKeys .= (colorKeys = "" ? FormatHotkeyLabel(hk) : ", " FormatHotkeyLabel(hk))

	txt := "Hotkeys:"
	txt .= "`n" FormatHotkeyLabel(hotkeys.toggle) ": Toggle drawing mode"
	if (hotkeys.exit)
		txt .= "`n" FormatHotkeyLabel(hotkeys.exit) ": Exit app"
	if (hotkeys.clear)
		txt .= "`n" FormatHotkeyLabel(hotkeys.clear) ": Clear drawing"
	if (hotkeys.undo)
		txt .= "`n" FormatHotkeyLabel(hotkeys.undo) ": Delete last shape`n"
	if (hotkeys.incLine)
		txt .= "`n" FormatHotkeyLabel(hotkeys.incLine) ": Increase line width"
	if (hotkeys.decLine)
		txt .= "`n" FormatHotkeyLabel(hotkeys.decLine) ": Decrease line width"

	txt .= "`nWheelUp/WheelDown: Line width +/-`n"

	txt .= "`nRight click: Open settings panel"
	txt .= "`nShift: Line"
	txt .= "`nCtrl: Rect"
	txt .= "`nAlt: Ellipse"
	txt .= "`nCtrl+Alt: Circle"
	txt .= "`nCtrl+Shift: Arrow`n"
	if (colorKeys != "")
		txt .= "`nColor hotkeys: " colorKeys

	MsgBox(txt, "Hotkeys Help", "Iconi")
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
			. "ClearOnExit=false`n`n"
			. "[Hotkeys]`n"
			. "ToggleDrawingMode=^F9`n"
			. "ExitApp=^+F12`n"
			. "ClearDrawing=Esc`n"
			. "UndoDrawing=Backspace`n"
			. "IncreaseLineWidth=^NumpadAdd`n"
			. "DecreaseLineWidth=^NumpadSub`n`n"
			. "[Colors]`n"
			. "r=0xFF0000`n"
			. "g=0x00FF00`n"
			. "b=0x0000FF`n"
			. "y=0xFFFF00`n"
			. "m=0xFF00FF`n"
			. "c=0x00FFFF`n"
			. "o=0xFFA500`n"
			. "v=0x7F00FF`n"
			. "s=0x8B4513`n"
			. "w=0xFFFFFF`n"
			. "n=0x808080`n"
			. "k=0x000000`n"

		f := FileOpen(iniFile, "w", "UTF-8")
		if (!f)
			throw Error("Unable to open settings.ini for write: " iniFile)
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
	global drawingMode, ui, gdi, activeMonitor, lastDrawingMonitorNum
	global allShapes, currentShape, drawing, needsUpdate

	if (drawingMode) {
		ExitDrawingMode(false)
		return
	}

	mon := GetMouseMonitorInfo()
	if (!IsObject(mon) || mon.Width <= 0 || mon.Height <= 0) {
		MsgBox("Failed to detect monitor for mouse position.", "Error", 48)
		return
	}

	monitorChanged := (lastDrawingMonitorNum != 0 && lastDrawingMonitorNum != mon.Num)
	activeMonitor := {
		num: Integer(mon.Num),
		left: mon.Left,
		top: mon.Top,
		right: mon.Right,
		bottom: mon.Bottom,
		width: mon.Width,
		height: mon.Height
	}

	; Temporarily hide old overlay if it exists (to take a clean screenshot)
	if (IsObject(ui.overlay)) {
		ui.overlay.Hide()
		Sleep(50)
	}

	; Release old GDI resources
	_FreeGDIResources()

	; Take screenshot
	if (gdi.hBitmapBackground > 0)
		Gdip_DisposeImage(gdi.hBitmapBackground)
	gdi.hBitmapBackground := 0
	gdi.hBitmapBackground := Gdip_BitmapFromScreen(activeMonitor.num)
	if (gdi.hBitmapBackground <= 0) {
		gdi.hBitmapBackground := 0
		MsgBox("Failed to capture screen.", "Error", 48)
		return
	}

	; Create memory DCs and bitmaps
	hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
	gdi.hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
	gdi.hbmBuffer := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", activeMonitor.width, "Int",
		activeMonitor.height, "Ptr")
	gdi.hdcBaked := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
	gdi.hbmBaked := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", activeMonitor.width, "Int",
		activeMonitor.height, "Ptr")
	DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

	if (!gdi.hdcMem || !gdi.hbmBuffer || !gdi.hdcBaked || !gdi.hbmBaked) {
		MsgBox("Failed to create memory DC or bitmap.", "Error", 48)
		if (gdi.hdcMem)
			DllCall("DeleteDC", "Ptr", gdi.hdcMem)
		if (gdi.hbmBuffer)
			DllCall("DeleteObject", "Ptr", gdi.hbmBuffer)
		if (gdi.hdcBaked)
			DllCall("DeleteDC", "Ptr", gdi.hdcBaked)
		if (gdi.hbmBaked)
			DllCall("DeleteObject", "Ptr", gdi.hbmBaked)
		gdi.hdcMem := gdi.hbmBuffer := gdi.hdcBaked := gdi.hbmBaked := 0
		return
	}

	gdi.hbmDefault := DllCall("SelectObject", "Ptr", gdi.hdcMem, "Ptr", gdi.hbmBuffer, "Ptr")
	gdi.hbmBakedDefault := DllCall("SelectObject", "Ptr", gdi.hdcBaked, "Ptr", gdi.hbmBaked, "Ptr")

	gdi.G_Mem := Gdip_GraphicsFromHDC(gdi.hdcMem)
	gdi.G_Baked := Gdip_GraphicsFromHDC(gdi.hdcBaked)

	if (!gdi.G_Mem || !gdi.G_Baked) {
		MsgBox("Failed to get GDI+ graphics context.", "Error", 48)
		ExitDrawingMode(false)
		return
	}

	drawing := false
	needsUpdate := false
	drawingMode := true
	lastDrawingMonitorNum := activeMonitor.num
	if (monitorChanged) {
		allShapes := []
		currentShape := {}
	}

	Gdip_SetSmoothingMode(gdi.G_Mem, 4)
	Gdip_SetSmoothingMode(gdi.G_Baked, 4)

	RefreshBakedBuffer()
	UpdateBuffer()

	; Transparent, clickable overlay window
	ui.overlay := Gui("+AlwaysOnTop -DPIScale -Caption +ToolWindow +E0x20")
	ui.overlay.OnEvent("Close", (*) => ExitDrawingMode(false))
	ui.overlay.Title := "Drawing Overlay"
	ui.overlay.Show("NA x" activeMonitor.left " y" activeMonitor.top " w" activeMonitor.width " h" activeMonitor.height)

	if (ui.overlay.Hwnd)
		DllCall("InvalidateRect", "Ptr", ui.overlay.Hwnd, "Ptr", 0, "Int", 0)

	UpdateTrayToggleMenu()
}

; Helper to release GDI resources
_FreeGDIResources() {
	global gdi

	if (gdi.G_Mem) {
		Gdip_DeleteGraphics(gdi.G_Mem)
		gdi.G_Mem := 0
	}
	if (gdi.hdcMem) {
		if (gdi.hbmBuffer) {
			if (gdi.hbmDefault && gdi.hbmDefault != -1)
				DllCall("SelectObject", "Ptr", gdi.hdcMem, "Ptr", gdi.hbmDefault)
			DllCall("DeleteObject", "Ptr", gdi.hbmBuffer)
			gdi.hbmBuffer := 0
		}
		gdi.hbmDefault := 0
		DllCall("DeleteDC", "Ptr", gdi.hdcMem)
		gdi.hdcMem := 0
	}
	if (gdi.G_Baked) {
		Gdip_DeleteGraphics(gdi.G_Baked)
		gdi.G_Baked := 0
	}
	if (gdi.hdcBaked) {
		if (gdi.hbmBaked) {
			if (gdi.hbmBakedDefault && gdi.hbmBakedDefault != -1)
				DllCall("SelectObject", "Ptr", gdi.hdcBaked, "Ptr", gdi.hbmBakedDefault)
			DllCall("DeleteObject", "Ptr", gdi.hbmBaked)
			gdi.hbmBaked := 0
		}
		gdi.hbmBakedDefault := 0
		DllCall("DeleteDC", "Ptr", gdi.hdcBaked)
		gdi.hdcBaked := 0
	}
}

; Drawing Mode: Exit
ExitDrawingMode(UserInitiated := false) {
	global drawingMode, drawing, needsUpdate, ui, gdi, activeMonitor
	global currentShape, allShapes, cfg

	SetTimer(UpdateTimer, 0)
	drawingMode := false
	drawing := false
	needsUpdate := false

	currentShape := {}

	if (IsObject(ui.overlay)) {
		ui.overlay.Destroy()
		ui.overlay := ""
	}
	_DestroySettings()

	if (cfg.clearOnExit)
		allShapes := []

	_FreeGDIResources()

	if (gdi.hBitmapBackground > 0) {
		Gdip_DisposeImage(gdi.hBitmapBackground)
		gdi.hBitmapBackground := 0
	}
	if (UserInitiated && gdi.token) {
		Gdip_Shutdown(gdi.token)
		gdi.token := 0
	}

	activeMonitor := {
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

ReadIniBool(file, section, key, default := false) {
	raw := Trim(IniRead(file, section, key, default ? "1" : "0"))
	if (raw = "")
		return default
	norm := StrLower(raw)
	if (norm = "1" || norm = "true" || norm = "yes" || norm = "on")
		return true
	if (norm = "0" || norm = "false" || norm = "no" || norm = "off")
		return false
	if RegExMatch(norm, "^-?\d+$")
		return Integer(norm) != 0
	return default
}

; WM Message Handlers
WM_ERASEBKGND_Handler(wParam, lParam, msg, hwnd) {
	global ui
	; Prevent white flickering in the overlay window
	if (IsObject(ui.overlay) && hwnd == ui.overlay.Hwnd)
		return 1
}

WM_PAINT_Handler(wParam, lParam, msg, hwnd) {
	global ui, gdi, activeMonitor

	if (!drawingMode || !IsObject(ui.overlay) || hwnd != ui.overlay.Hwnd || !gdi.hdcMem || activeMonitor.width <= 0 || activeMonitor.height <= 0)
		return

	ps := Buffer(A_PtrSize == 8 ? 72 : 64) ; paint Struct Size
	hDC := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")
	if (!hDC)
		return 0

	DllCall("BitBlt",
		"Ptr", hDC, "Int", 0, "Int", 0, "Int", activeMonitor.width, "Int", activeMonitor.height,
		"Ptr", gdi.hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)  ; SRCCOPY

	DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr)
	return 0
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
	global drawing, startX, startY, currentShape, needsUpdate
	global ui

	if (!drawingMode || !IsObject(ui.overlay))
		return

	if (IsObject(ui.settings) && ui.settings.Hwnd) {
		if (hwnd = ui.settings.Hwnd || DllCall("IsChild", "Ptr", ui.settings.Hwnd, "Ptr", hwnd, "Int"))
			return
	}

	if (hwnd != ui.overlay.Hwnd)
		return

	; Close settings window if open and clicked outside
	if (IsObject(ui.settings) && ui.settings.Hwnd) {
		_DestroySettings()
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

	drawing := true
	startX := x, startY := y

	currentShape := {
		type: currentTool,
		startX: x,
		startY: y,
		endX: x,
		endY: y,
		radius: 0,
		color: drawColor,
		width: cfg.line.width
	}
	if (currentTool = "free") {
		currentShape.points := [[x, y]]
		currentShape.pointsStr := x "," y
	}

	needsUpdate := false
	SetTimer(UpdateTimer, cfg.frameIntervalMs)
	DllCall("SetCapture", "Ptr", hwnd)
}

WM_LBUTTONUP(wParam, lParam, msg, hwnd) {
	global ui
	global drawing, currentShape, allShapes, needsUpdate

	if (!drawingMode || !IsObject(ui.overlay) || hwnd != ui.overlay.Hwnd)
		return

	DllCall("ReleaseCapture")
	drawing := false
	SetTimer(UpdateTimer, 0)

	shapeToFinalize := currentShape
	currentShape := {}
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
		allShapes.Push(shapeToFinalize)
		if (!_AppendShapeToBaked(shapeToFinalize))
			RefreshBakedBuffer()
	}

	UpdateBuffer()
	DllCall("InvalidateRect", "Ptr", ui.overlay.Hwnd, "Ptr", 0, "Int", 0)
	needsUpdate := false
}

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
	global ui
	global drawing, startX, startY, currentShape, needsUpdate

	if (!drawing || !drawingMode || !IsObject(ui.overlay) || hwnd != ui.overlay.Hwnd)
		return
	if (!IsObject(currentShape) || !currentShape.HasProp("type"))
		return

	GetOverlayPointFromLParam(lParam, &x, &y, true)

	if (currentShape.type = "free") {
		if (!currentShape.HasProp("points") || !IsObject(currentShape.points))
			return
		lastPoint := currentShape.points[currentShape.points.Length]
		if (Abs(x - lastPoint[1]) >= cfg.minPointStep || Abs(y - lastPoint[2]) >= cfg.minPointStep) {
			currentShape.points.Push([x, y])
			currentShape.pointsStr .= "|" x "," y
			needsUpdate := true
		}
	} else {
		currentShape.endX := x
		currentShape.endY := y
		if (currentShape.type = "circle")
			currentShape.radius := Max(Abs(x - startX), Abs(y - startY))
		needsUpdate := true
	}

}

WM_RBUTTONDOWN(wParam, lParam, msg, hwnd) {
	global ui, activeMonitor

	if (!drawingMode || !IsObject(ui.overlay) || hwnd != ui.overlay.Hwnd)
		return

	if (IsObject(ui.settings))
		_DestroySettings()

	ui.settings := Gui("+AlwaysOnTop +ToolWindow -Caption Border")
	ui.settings.Title := "Drawing Settings"
	ui.settings.OnEvent("Close", (*) => (ui.settings := ""))
	_ResetUISettingsFont()
	activeRGB := drawColor & 0xFFFFFF
	margin := 10
	btnSize := 30
	gap := 4
	colorColumnCount := 3
	colW := btnSize + gap

	curY := margin
	for i, item in colorList {
		val := item.val
		hex := Format("{:06X}", val)
		col := Mod(i - 1, colorColumnCount)
		row := (i - 1) // colorColumnCount

		bx := margin + col * colW
		by := curY + row * (btnSize + gap)
		btn := ui.settings.Add("Text", "x" bx " y" by " w" btnSize " h" btnSize " +Border +0x0100 Background" hex)
		if (val = activeRGB) {
			luminance := GetLuminance(val)
			markColor := (luminance > 128) ? "000000" : "FFFFFF"
			ui.settings.SetFont("s16 w1000")
			ui.settings.Add("Text", "xp yp wp hp +Center +0x200 c" markColor " BackgroundTrans", "✓")
			_ResetUISettingsFont()
		}
		btn.OnEvent("Click", ColorSelect.Bind(val, ui.settings))
	}

	rowCount := Ceil(colorList.Length / colorColumnCount)
	gridBottom := curY + rowCount * (btnSize + gap)

	; Line width control
	ui.settings.AddText("x" margin " y" (gridBottom + 5), "Line width:")
	ui.settings.AddEdit("vLineWidth yp-5 w40 x+2 Number", cfg.line.width).OnEvent("Change", (*) => UpdateLineWidth(ui.settings))
	ui.settings.AddUpDown("Range" cfg.line.minWidth "-" cfg.line.maxWidth, cfg.line.width).OnEvent("Change", (*) => UpdateLineWidth(ui.settings))

	; Opacity control
	ui.settings.AddText("x" margin " y+12", "Opacity:")
	ui.settings.AddEdit("vDrawAlpha yp-5 w50 x+6 Number", cfg.drawAlpha).OnEvent("Change", (*) => UpdateDrawAlpha(ui.settings))
	ui.settings.AddUpDown("Range0-255", cfg.drawAlpha).OnEvent("Change", (*) => UpdateDrawAlpha(ui.settings))

	; Quick actions (symbol buttons)
	btnOpt := " w30 h32 +Border +Center +0x200 +0x100 BackgroundFAFAFA"
	ui.settings.SetFont("s15 c2b8600", "Segoe MDL2 Assets")
	btnUndo := ui.settings.AddText("x10 y+5" btnOpt, Chr(0xE7A7))
	ui.settings.SetFont("c0059ff")
	btnExitDraw := ui.settings.AddText("x+" gap " yp" btnOpt, Chr(0xEE56))
	ui.settings.SetFont("cff0000")
	btnExitApp := ui.settings.AddText("x+" gap " yp" btnOpt, Chr(0xE7E8)) ; ⏻
	btnExitDraw.GetPos(&dX, &dY, &dW, &dH)
	ui.settings.SetFont("s20")
	ui.settings.AddText("x" dX - 5 " y" dY - 10 " w" dW " h" dH " +Center +0x200 BackgroundTrans +E0x20", "✕")
	_ResetUISettingsFont()
	btnUndo.OnEvent("Click", (*) => DeleteLastShape())
	btnExitDraw.OnEvent("Click", (*) => ExitDrawingFromSettings())
	btnExitApp.OnEvent("Click", (*) => ExitAppFromSettings())

	MouseGetPos(&mX, &mY)
	ui.settings.Show("AutoSize x" mX " y" mY)
	WinGetPos(, , &w, &h, "ahk_id " ui.settings.Hwnd)
	minX := activeMonitor.left
	minY := activeMonitor.top
	maxX := Max(minX, activeMonitor.right - w)
	maxY := Max(minY, activeMonitor.bottom - h)
	finalX := Min(Max(mX, minX), maxX)
	finalY := Min(Max(mY, minY), maxY)
	if (finalX != mX || finalY != mY)
		WinMove(finalX, finalY, , , "ahk_id " ui.settings.Hwnd)
}

; Toolbar & Color Operations
ColorSelect(colorVal, gui, *) {
	global drawColor
	drawColor := ARGB(colorVal, cfg.drawAlpha)
	_DestroySettings(gui)
}

UpdateLineWidth(gui, *) {
	newWidth := gui["LineWidth"].Value
	if (newWidth >= cfg.line.minWidth && newWidth <= cfg.line.maxWidth)
		cfg.line.width := newWidth
}

UpdateDrawAlpha(gui, *) {
	global drawColor
	newAlpha := gui["DrawAlpha"].Value
	if (newAlpha >= 0 && newAlpha <= 255) {
		cfg.drawAlpha := newAlpha
		drawColor := ARGB(drawColor & 0xFFFFFF, cfg.drawAlpha)
	}
}

ExitDrawingFromSettings(*) {
	_DestroySettings()
	ExitDrawingMode(false)
}

ExitAppFromSettings(*) {
	_DestroySettings()
	ExitApp()
}

ClearDrawing(*) {
	global ui
	global allShapes, needsUpdate
	if (!drawingMode)
		return
	allShapes := []
	RefreshBakedBuffer()
	UpdateBuffer()
	if (IsObject(ui.overlay))
		DllCall("InvalidateRect", "Ptr", ui.overlay.Hwnd, "Ptr", 0, "Int", 0)
	needsUpdate := false
}

DeleteLastShape(*) {
	global ui
	global allShapes
	if (!drawingMode || !allShapes.Length)
		return
	allShapes.Pop()
	RefreshBakedBuffer()
	UpdateBuffer()
	if (IsObject(ui.overlay))
		DllCall("InvalidateRect", "Ptr", ui.overlay.Hwnd, "Ptr", 0, "Int", 0)
}

AdjustLineWidth(delta) {
	if (!drawingMode)
		return
	cfg.line.width := Max(Min(cfg.line.width + delta, cfg.line.maxWidth), cfg.line.minWidth)
	ToolTip("Width: " cfg.line.width)
	SetTimer(HideToolTip, -1000)
}

HideToolTip() {
	ToolTip()
}

SetDrawColor(colorRGB, *) {
	global drawColor
	if (!drawingMode)
		return false
	rgb := colorRGB & 0xFFFFFF
	drawColor := ARGB(rgb, cfg.drawAlpha)
	return true
}

; Timer & Buffer Update
UpdateTimer() {
	global ui
	global needsUpdate
	if (!drawingMode || !IsObject(ui.overlay)) {
		SetTimer(UpdateTimer, 0)
		return
	}
	if (needsUpdate) {
		needsUpdate := false
		UpdateBuffer()
		DllCall("InvalidateRect", "Ptr", ui.overlay.Hwnd, "Ptr", 0, "Int", 0)
	}
}

UpdateBuffer() {
	global gdi, currentShape, drawing, activeMonitor
	if (!gdi.G_Mem || !gdi.hdcBaked || !gdi.hdcMem || activeMonitor.width <= 0 || activeMonitor.height <= 0)
		return

	DllCall("BitBlt",
		"Ptr", gdi.hdcMem, "Int", 0, "Int", 0, "Int", activeMonitor.width, "Int", activeMonitor.height,
		"Ptr", gdi.hdcBaked, "Int", 0, "Int", 0, "UInt", 0x00CC0020)  ; SRCCOPY

	if (drawing && IsObject(currentShape) && currentShape.HasProp("type"))
		DrawShapesToGraphics(gdi.G_Mem, [currentShape])
}

RefreshBakedBuffer() {
	global gdi, activeMonitor
	if (!gdi.G_Baked || !gdi.hBitmapBackground || activeMonitor.width <= 0 || activeMonitor.height <= 0)
		return
	Gdip_DrawImage(gdi.G_Baked, gdi.hBitmapBackground, 0, 0, activeMonitor.width, activeMonitor.height)
	DrawShapesToGraphics(gdi.G_Baked, allShapes)
}

_AppendShapeToBaked(shape) {
	global gdi, activeMonitor
	if (!IsObject(shape) || !shape.HasProp("type"))
		return false
	if (!gdi.G_Baked || !gdi.hBitmapBackground || activeMonitor.width <= 0 || activeMonitor.height <= 0)
		return false
	DrawShapesToGraphics(gdi.G_Baked, [shape])
	return true
}

IsMouseOnActiveMonitor() {
	global activeMonitor
	if (!IsObject(activeMonitor) || activeMonitor.width <= 0 || activeMonitor.height <= 0)
		return false
	MouseGetPos(&mX, &mY)
	return (mX >= activeMonitor.left && mX < activeMonitor.right && mY >= activeMonitor.top && mY < activeMonitor.bottom)
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
	global activeMonitor

	x := SignedInt16(lParam & 0xFFFF)
	y := SignedInt16((lParam >> 16) & 0xFFFF)

	if (!clampToOverlay || activeMonitor.width <= 0 || activeMonitor.height <= 0)
		return

	x := Max(0, Min(x, activeMonitor.width - 1))
	y := Max(0, Min(y, activeMonitor.height - 1))
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
	Loop points.Length - 1
		str .= "|" points[A_Index + 1][1] "," points[A_Index + 1][2]
	return str
}

DrawShapesToGraphics(G, shapesArray) {
	lastPenColor := -1, lastPenWidth := -1, pPen := 0

	for index, shape in shapesArray {
		if (!IsObject(shape) || !shape.HasProp("type"))
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

		try {
			switch shape.type {
				case "free":
					if (shape.HasProp("points") && shape.points.Length >= 2) {
						if (!shape.HasProp("pointsStr"))
							shape.pointsStr := BuildPointsStr(shape.points)
						Gdip_DrawLines(G, pPen, shape.pointsStr)
					}
				case "rect":
					if (_ShapeHasCoords(shape))
						Gdip_DrawRectangle(G, pPen,
							Min(shape.startX, shape.endX),
							Min(shape.startY, shape.endY),
							Abs(shape.endX - shape.startX),
							Abs(shape.endY - shape.startY))
				case "line":
					if (_ShapeHasCoords(shape))
						Gdip_DrawLine(G, pPen, shape.startX, shape.startY, shape.endX, shape.endY)
				case "ellipse":
					if (_ShapeHasCoords(shape))
						Gdip_DrawEllipse(G, pPen,
							Min(shape.startX, shape.endX),
							Min(shape.startY, shape.endY),
							Abs(shape.endX - shape.startX),
							Abs(shape.endY - shape.startY))
				case "circle":
					if (_ShapeHasCenterRadius(shape))
						Gdip_DrawEllipse(G, pPen,
							shape.startX - shape.radius, shape.startY - shape.radius,
							shape.radius * 2, shape.radius * 2)
				case "arrow":
					if (_ShapeHasCoords(shape))
						DrawArrowGdip(G, pPen, shape.startX, shape.startY, shape.endX, shape.endY, shape.width,
							shape.color
						)
			}
		} catch Error as e {
			OutputDebug("GDI+ Drawing Error [type=" shape.type ", idx=" index "]: " e.Message "`n")
		}
	}

	if (pPen)
		Gdip_DeletePen(pPen)
}

; Common coordinate check for rect / line / ellipse / arrow
_ShapeHasCoords(shape) {
	return shape.HasProp("startX") && shape.HasProp("startY")
		&& shape.HasProp("endX") && shape.HasProp("endY")
}

; Common coordinate check for circle
_ShapeHasCenterRadius(shape) {
	return shape.HasProp("startX") && shape.HasProp("startY")
		&& shape.HasProp("radius")
}

; Draw an arrow from (x1, y1) to (x2, y2) with specified width and color
DrawArrowGdip(G, pPen, x1, y1, x2, y2, width, color) {
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
	pBrush := Gdip_BrushCreateSolid(color)
	Gdip_FillPolygon(G, pBrush, pPoints)
	Gdip_DeleteBrush(pBrush)
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

; Initialize GDI+ — call this before using any GDI+ functions
GdiStartup() {
	global gdi
	try {
		gdi.token := Gdip_Startup()
	} catch Error as e {
		MsgBox("GDI+ Error: " e.Message, "Error", 48)
		ExitApp
	}
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

About(*) {
  msg := "
	(
	AkcanSoft On Screen Drawing Tool v1.0.2`n
	©2026 Mesut Akcan 
	makcan@gmail.com
	github.com/akcansoft
	mesutakcan.blogspot.com
	youtube.com/mesutakcan
	)"  
  MsgBox(msg, "About", "Iconi Owner") ; ui.overlay.Hwnd)
}
