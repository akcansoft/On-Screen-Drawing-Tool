#Requires AutoHotkey v2.0

; ==============================================================================
; Text Mode Functions for On Screen Drawing Tool
; ==============================================================================

global GWL_EXSTYLE := -20
global WS_EX_TRANSPARENT := 0x20
global WS_EX_NOACTIVATE := 0x8000000

EnterTextMode(*) {
	if (!state.drawingMode || state.textMode)
		return
	if (_IsAppSettingsOpen() || _GuiExists(ui.helpGui))
		return

	_ManageDrawToolbar("hide", false)
	state.textMode := true
	state.textInput.active := false
	state.textInput.buffer := ""
	state.textInput.color := draw.color

	hIBeam := LoadSystemCursor(32513) ; IDC_IBEAM
	if (hIBeam)
		DllCall("SetCursor", "Ptr", hIBeam)

	ToolTip("Text mode — click to place text | Esc = exit")
	SetTimer(() => ToolTip(), -1500)
}

ExitTextMode(*) {
	if (!state.textMode)
		return

	if (state.textInput.active)
		CommitText()

	_StopTextInput()

	state.textMode := false

	EnableDrawingCursor()
	UpdateBuffer()
	InvalidateOverlay()
}

CommitText() {
	buf := state.textInput.buffer
	_StopCursorBlink()
	_StopTextInput()
	state.textInput.active := false
	state.textInput.buffer := ""

	if (Trim(buf) = "") {
		UpdateBuffer()
		InvalidateOverlay()
		return
	}

	lines := StrSplit(buf, "`n")

	shape := {
		type: "text",
		lines: lines,
		x: state.textInput.x,
		y: state.textInput.y,
		color: state.textInput.color,
		font: cfg.text.font,
		size: cfg.text.size,
		bold: cfg.text.bold,
		italic: cfg.text.italic,
		underline: cfg.text.underline,
		width: 0
	}

	draw.redoStack := []
	while (draw.history.Length >= cfg.maxHistorySize)
		draw.history.RemoveAt(1)
	draw.history.Push(shape)
	_AppendShapeToBaked(shape)

	UpdateBuffer()
	InvalidateOverlay()
}

AdjustTextSize(delta) {
	static _clearTip := () => ToolTip()
	cfg.text.size := Max(Min(cfg.text.size + delta, 200), 6)
	ToolTip("Font size: " cfg.text.size)
	SetTimer(_clearTip, -1000)
	if (state.textInput.active) {
		UpdateBuffer()
		InvalidateOverlay()
	}
}

_StartCursorBlink() {
	state.textInput.cursorVisible := true
	SetTimer(_CursorBlinkTick, 530)
}

_StopCursorBlink() {
	SetTimer(_CursorBlinkTick, 0)
	state.textInput.cursorVisible := false
}

_CursorBlinkTick() {
	if (!state.textMode || !state.textInput.active) {
		SetTimer(_CursorBlinkTick, 0)
		return
	}
	state.textInput.cursorVisible := !state.textInput.cursorVisible
	UpdateBuffer()
	InvalidateOverlay()
}

_StartTextInput() {
	_StopTextInput()

	if (!_GuiExists(ui.overlayGui))
		return

	hwnd := ui.overlayGui.Hwnd

	exStyle := DllCall("GetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int")
	exStyle &= ~WS_EX_TRANSPARENT
	exStyle &= ~WS_EX_NOACTIVATE
	DllCall("SetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int", exStyle)

	WinActivate("ahk_id " hwnd)
	OnMessage(0x100, _TextSink_KeyDown)
	OnMessage(0x102, _TextSink_Char)
}

_StopTextInput() {
	OnMessage(0x100, _TextSink_KeyDown, 0)
	OnMessage(0x102, _TextSink_Char, 0)

	if (_GuiExists(ui.overlayGui)) {
		hwnd := ui.overlayGui.Hwnd
		exStyle := DllCall("GetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int")
		exStyle |= WS_EX_TRANSPARENT
		exStyle |= WS_EX_NOACTIVATE
		DllCall("SetWindowLong", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Int", exStyle)
	}
}

_TextSink_KeyDown(wParam, lParam, msg, hwnd) {
	if (!state.textMode || !state.textInput.active)
		return
	if (hwnd != _SafeHwnd(ui.overlayGui))
		return
	switch wParam {
		case 0x08: ; Backspace
			buf := state.textInput.buffer
			if (StrLen(buf) > 0)
				state.textInput.buffer := SubStr(buf, 1, -1)
			state.textInput.cursorVisible := true
			UpdateBuffer()
			InvalidateOverlay()
			return 0
		case 0x0D: ; Enter
			state.textInput.buffer .= "`n"
			state.textInput.cursorVisible := true
			UpdateBuffer()
			InvalidateOverlay()
			return 0
	}
}

_TextSink_Char(wParam, lParam, msg, hwnd) {
	if (!state.textMode || !state.textInput.active)
		return
	if (hwnd != _SafeHwnd(ui.overlayGui))
		return
	if (wParam < 32)
		return
	state.textInput.buffer .= Chr(wParam)
	state.textInput.cursorVisible := true
	UpdateBuffer()
	InvalidateOverlay()
	return 0
}

DrawLiveText(G) {
	if (!state.textMode || !state.textInput.active)
		return

	if (state.textInput.buffer = "" && !state.textInput.cursorVisible)
		return

	liveShape := {
		type: "text",
		x: state.textInput.x,
		y: state.textInput.y,
		color: state.textInput.color,
		font: cfg.text.font,
		size: cfg.text.size,
		bold: cfg.text.bold,
		italic: cfg.text.italic,
		underline: cfg.text.underline,
		width: 0
	}

	if (state.textInput.buffer != "") {
		liveShape.lines := StrSplit(state.textInput.buffer, "`n")
		liveShape.showCursor := state.textInput.cursorVisible
	} else {
		liveShape.lines := ["|"]
		liveShape.showCursor := false
	}

	DrawShapesToGraphics(G, [liveShape])
}

CycleTextColor(*) {
	if (!state.textMode)
		return

	currentRGB := state.textInput.color & 0xFFFFFF
	idx := 0
	for i, item in cfg.colors.List {
		if (item.val == currentRGB) {
			idx := i
			break
		}
	}

	idx++
	if (idx > cfg.colors.List.Length)
		idx := 1

	state.textInput.color := ARGB(cfg.colors.List[idx].val, cfg.drawAlpha)

	if (state.textInput.active) {
		UpdateBuffer()
		InvalidateOverlay()
	}
}