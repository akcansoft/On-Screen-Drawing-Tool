/*
Adds a standard Windows tooltip to a Gui control.
version: 1.0
author: Mesut Akcan
date: 2026-04-04
GitHub repository: https://github.com/akcansoft/CtrlToolTip

Usage:
1. Include this file in your AutoHotkey v2 script with #Include CtrlToolTip.ahk.
2. Call CtrlToolTip(ctrl, text) for the target Gui.Control.

Example:
    CtrlToolTip(myControl, "Tooltip text")
*/

#Requires AutoHotkey v2.0


; ctrl: Target Gui.Control that should display the tooltip.
; text: Tooltip text to show when the mouse hovers the control.
CtrlToolTip(ctrl, text) {
	static tipHandles := Map()         ; Map to store tooltip control handles for each parent Gui HWND
	static textBuffers := Map() 			 ; Map to store text buffers for each control to prevent garbage collection
	static registeredControls := Map() ; Map to track which controls have been registered with the tooltip control
	static GWL_STYLE := -16            ; Offset for GetWindowLongPtr to retrieve the window style
	static SS_NOTIFY := 0x0100 			   ; Style flag for static controls to receive notification messages (required for tooltips)
	guiHwnd := 0                       ; Variable to hold the parent Gui's HWND
	hTip := 0											     ; Variable to hold the tooltip control's HWND

	; Ensure the provided control is a Gui.Control object
	if !(ctrl is Gui.Control)
		throw TypeError("CtrlToolTip: Gui.Control expected.", -1)

	guiHwnd := ctrl.Gui.Hwnd ; Get the parent Gui's HWND to associate the tooltip with it.

	; Ensure static text controls have the SS_NOTIFY style for tooltip support.
	if (ctrl.Type = "Text") {  ; If the control is a Text control, check and set the SS_NOTIFY style
		; Get the current window style of the control
		style := DllCall("GetWindowLongPtr", "Ptr", ctrl.Hwnd, "Int", GWL_STYLE, "Ptr")
		; If the control does not already have the SS_NOTIFY style, add it
		if !(style & SS_NOTIFY)
			; Add the SS_NOTIFY style to the control's window style
			DllCall("SetWindowLongPtr", "Ptr", ctrl.Hwnd, "Int", GWL_STYLE, "Ptr", style | SS_NOTIFY, "Ptr")
	}

	; Check if a tooltip control already exists for this Gui, and create one if not.
	if tipHandles.Has(guiHwnd)
		hTip := tipHandles[guiHwnd] ; Retrieve the existing tooltip control handle for this Gui

	; Get or create the tooltip window handle for this Gui.
	if !hTip || !DllCall("IsWindow", "Ptr", hTip, "Int") { ; If the tooltip control does not exist or is not a valid window, create it
		; Create the tooltip control for this Gui with standard tooltip window styles.
		hTip := DllCall(
			"CreateWindowEx"            ; lpExStyle
			, "UInt", 0                 ; dwExStyle
			, "Str", "tooltips_class32" ; lpClassName
			, "Ptr", 0                  ; lpWindowName
			, "UInt", 0x80000003        ; Tooltip window styles
			, "Int", 0x80000000         ; CW_USEDEFAULT
			, "Int", 0x80000000         ; CW_USEDEFAULT
			, "Int", 0x80000000         ; CW_USEDEFAULT
			, "Int", 0x80000000         ; CW_USEDEFAULT
			, "Ptr", guiHwnd						; hwndParent
			, "Ptr", 0                  ; hMenu
			, "Ptr", 0                  ; hInstance
			, "Ptr", 0                  ; lpParam
			, "Ptr"                     ; Return value is the tooltip control's HWND
		)

		; CreateWindowEx failed, throw an error.
		if !hTip
			throw Error("CtrlToolTip: Failed to create tooltip control.", -1)

		; Set the maximum tooltip width so the text can wrap to multiple lines.
		SendMessage(0x0418, 0, A_ScreenWidth, hTip) ; TTM_SETMAXTIPWIDTH
		; Store the tooltip handle for this Gui's HWND.
		tipHandles[guiHwnd] := hTip
	}

	; Prepare the buffer for the tooltip text.
	ti := Buffer(24 + (A_PtrSize * 6), 0)                ; Size of TOOLINFO for the current pointer size
	textBuf := Buffer(StrPut(text, "UTF-16") * 2, 0)     ; Buffer for the tooltip text in UTF-16 encoding
	StrPut(text, textBuf, "UTF-16")                      ; Write the tooltip text into the buffer

	NumPut("UInt", ti.Size, ti)                          ; cbSize
	NumPut("UInt", 0x11, ti, 4)                          ; TTF_IDISHWND | TTF_SUBCLASS
	NumPut("Ptr", guiHwnd, ti, 8)                        ; hwnd
	NumPut("Ptr", ctrl.Hwnd, ti, 8 + A_PtrSize)          ; uId (use the control's HWND as the unique identifier)
	NumPut("Ptr", textBuf.Ptr, ti, 24 + (A_PtrSize * 3)) ; lpszText

	; Update the existing tooltip text for this control.
	; If the control is not yet registered, add it to the tooltip control.
	if registeredControls.Has(ctrl.Hwnd)
		SendMessage(0x0439, 0, ti.Ptr, hTip) ; TTM_UPDATETIPTEXTW
	else {
		SendMessage(0x0432, 0, ti.Ptr, hTip) ; TTM_ADDTOOLW
		registeredControls[ctrl.Hwnd] := true ; Mark this control as registered
	}

	; Store the text buffer to prevent it from being garbage collected,
	; which would cause the tooltip to display empty text.
	textBuffers[ctrl.Hwnd] := textBuf
}