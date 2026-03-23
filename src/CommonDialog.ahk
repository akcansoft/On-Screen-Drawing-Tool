#Requires AutoHotkey v2.0
; =============================================================================
; CommonDialog.ahk — Windows standard Font and Color dialog wrappers
; =============================================================================
class FontDialog {
	; Opens the Windows standard ChooseFontW dialog.
	; Parameters (all ByRef except hwndOwner):
	;   hwndOwner  — owner window handle (0 = no owner)
	;   fontName   — [in/out] face name
	;   fontSize   — [in/out] point size
	;   bold       — [in/out] bool
	;   italic     — [in/out] bool
	;   underline  — [in/out] bool
	;   charSet    — [in/out] lfCharSet byte (e.g. 162 = Turkish, 1 = Default)
	; Returns true if OK was clicked, false if cancelled.
	static Choose(hwndOwner, &fontName, &fontSize, &bold, &italic, &underline, &charSet := 1) {
		static LOGFONT_SIZE := 92          ; LOGFONTW: 28 bytes header + 64 bytes face (32 WCHARs)
		static CF_SIZE_32 := 64
		static CF_SIZE_64 := 104
		CF_SIZE := A_PtrSize = 8 ? CF_SIZE_64 : CF_SIZE_32

		LF := Buffer(LOGFONT_SIZE, 0)
		CF := Buffer(CF_SIZE, 0)

		; Pre-fill LOGFONT so the dialog opens with current values
		; lfHeight: use negative point-to-pixel conversion so dialog shows correct size
		if (fontSize > 0)
			NumPut("Int", -Round(fontSize * A_ScreenDPI / 72), LF, 0)   ; lfHeight
		NumPut("Int", bold ? 700 : 400, LF, 16)                 ; lfWeight
		NumPut("UChar", italic ? 1 : 0, LF, 20)                 ; lfItalic
		NumPut("UChar", underline ? 1 : 0, LF, 21)                 ; lfUnderline
		NumPut("UChar", charSet, LF, 23)                 ; lfCharSet
		if (fontName != "")
			StrPut(fontName, LF.Ptr + 28, 32, "UTF-16")                  ; lfFaceName

		; CHOOSEFONT struct
		NumPut("UInt", CF_SIZE, CF, 0)                               ; lStructSize
		NumPut("Ptr", hwndOwner, CF, A_PtrSize)                       ; hwndOwner
		NumPut("Ptr", LF.Ptr, CF, A_PtrSize * 3)                   ; lpLogFont
		; CF_SCREENFONTS=0x1 | CF_INITTOLOGFONTSTRUCT=0x40
		NumPut("UInt", 0x41, CF, A_PtrSize * 4 + 4)               ; Flags

		if !DllCall("comdlg32\ChooseFontW", "Ptr", CF.Ptr)
			return false

		; Read results — use iPointSize (tenths of a point) for reliable size
		iPointSize := NumGet(CF, A_PtrSize * 4 + 8, "Int")             ; iPointSize (×10)
		if (iPointSize > 0)
			fontSize := Max(6, Min(200, Round(iPointSize / 10)))
		else {
			; Fallback: derive from lfHeight
			h := NumGet(LF, 0, "Int")
			fontSize := Max(6, Min(200, Abs(Round(h * 72 / A_ScreenDPI))))
		}

		fontName := StrGet(LF.Ptr + 28, 32, "UTF-16")
		bold := (NumGet(LF, 16, "Int") >= 700)
		italic := (NumGet(LF, 20, "UChar") != 0)
		underline := (NumGet(LF, 21, "UChar") != 0)
		charSet := NumGet(LF, 23, "UChar")

		return true
	}
}

class ColorDialog {
	; Opens the Windows standard ChooseColorW dialog.
	; Parameters:
	;   initColor    — initial RGB color (0xRRGGBB)
	;   hwndOwner    — owner window handle (0 = no owner)
	;   custColors   — [in/out] Array of up to 16 custom RGB colors (persisted by caller)
	;   fullOpen     — true = show full panel with custom color area
	; Returns selected RGB color (0xRRGGBB), or -1 if cancelled.
	static Choose(initColor := 0, hwndOwner := 0, &custColors := "", fullOpen := true) {
		static p := A_PtrSize
		flags := fullOpen ? 0x3 : 0x1   ; CC_RGBINIT | CC_FULLOPEN  or  CC_RGBINIT only

		if (!IsObject(custColors))
			custColors := []
		while (custColors.Length < 16)
			custColors.Push(0)
		if (custColors.Length > 16)
			throw Error("custColors: maximum 16 entries allowed.")

		CUSTOM := Buffer(16 * 4, 0)
		loop 16
			NumPut("UInt", ColorDialog._RGBtoBGR(custColors[A_Index]), CUSTOM, (A_Index - 1) * 4)

		CC := Buffer((p = 4) ? 36 : 72, 0)
		NumPut("UInt", CC.Size, CC, 0)       ; lStructSize
		NumPut("UPtr", hwndOwner, CC, p)       ; hwndOwner
		NumPut("UInt", ColorDialog._RGBtoBGR(initColor), CC, 3 * p)  ; rgbResult
		NumPut("UPtr", CUSTOM.Ptr, CC, 4 * p)   ; lpCustColors
		NumPut("UInt", flags, CC, 5 * p)   ; Flags

		if !DllCall("comdlg32\ChooseColorW", "UPtr", CC.Ptr, "UInt")
			return -1

		; Persist custom colors back to caller's array
		custColors := []
		loop 16
			custColors.Push(ColorDialog._RGBtoBGR(NumGet(CUSTOM, (A_Index - 1) * 4, "UInt")))

		return ColorDialog._RGBtoBGR(NumGet(CC, 3 * p, "UInt"))
	}

	; Swap R and B channels: RGB <-> BGR (Windows COLORREF uses BGR)
	static _RGBtoBGR(c) {
		return ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)
	}
}