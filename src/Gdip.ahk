; Selected functions extracted from Gdip_All.ahk by buliasz
; Source: https://github.com/buliasz/AHKv2-Gdip/blob/master/Gdip_All.ahk
; Only the functions required by this project are included.

#Requires AutoHotkey v2.0

;==============================================================================
; GDI+ Startup/Shutdown
;==============================================================================
Gdip_Startup() {
	if (!DllCall("LoadLibrary", "str", "gdiplus", "UPtr")) {
		throw Error("Could not load GDI+ library")
	}

	si := Buffer(A_PtrSize = 4 ? 20 : 32, 0) ; sizeof(GdiplusStartupInputEx) = 20, 32
	NumPut("uint", 0x2, si)
	NumPut("uint", 0x4, si, A_PtrSize = 4 ? 16 : 24)
	DllCall("gdiplus\GdiplusStartup", "UPtr*", &pToken := 0, "Ptr", si, "UPtr", 0)
	if (!pToken) {
		throw Error("Gdiplus failed to start. Please ensure you have gdiplus on your system")
	}

	return pToken
}

Gdip_Shutdown(pToken) {
	DllCall("gdiplus\GdiplusShutdown", "UPtr", pToken)
	hModule := DllCall("GetModuleHandle", "str", "gdiplus", "UPtr")
	if (!hModule) {
		throw Error("GDI+ library was unloaded before shutdown")
	}
	if (!DllCall("FreeLibrary", "UPtr", hModule)) {
		throw Error("Could not free GDI+ library")
	}

	return 0
}

;==============================================================================
; GDI Context Class (Moved from AppClasses.ahk)
;==============================================================================
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

		hdcScreen := GetDC()
		this.hdcMem := CreateCompatibleDC(hdcScreen)
		this.hbmBuffer := CreateCompatibleBitmap(hdcScreen, width, height)
		this.hdcBaked := CreateCompatibleDC(hdcScreen)
		this.hbmBaked := CreateCompatibleBitmap(hdcScreen, width, height)
		ReleaseDC(hdcScreen)

		if (!this.hdcMem || !this.hbmBuffer || !this.hdcBaked || !this.hbmBaked) {
			this.DestroyBuffer()
			throw Error("Failed to create memory DC or bitmap.")
		}

		this.hbmDefault := SelectObject(this.hdcMem, this.hbmBuffer)
		this.hbmBakedDefault := SelectObject(this.hdcBaked, this.hbmBaked)

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
					SelectObject(this.hdcMem, this.hbmDefault)
				DeleteObject(this.hbmBuffer)
				this.hbmBuffer := 0
			}
			this.hbmDefault := 0
			DeleteDC(this.hdcMem)
			this.hdcMem := 0
		}
		if (this.G_Baked) {
			Gdip_DeleteGraphics(this.G_Baked)
			this.G_Baked := 0
		}
		if (this.hdcBaked) {
			if (this.hbmBaked) {
				if (this.hbmBakedDefault && this.hbmBakedDefault != -1)
					SelectObject(this.hdcBaked, this.hbmBakedDefault)
				DeleteObject(this.hbmBaked)
				this.hbmBaked := 0
			}
			this.hbmBakedDefault := 0
			DeleteDC(this.hdcBaked)
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

;==============================================================================
; Project-Specific Helpers (Moved from main script)
;==============================================================================
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

	DllCall("gdiplus\GdipSetPenEndCap", "UPtr", pPen, "Int", 0) ; Flat cap
	Gdip_DrawLine(G, pPen, x1, y1, bx, by)

	pPoints := x2 "," y2 "|" (bx + W1) "," (by + W2) "|" (bx - W1) "," (by - W2)
	Gdip_FillPolygon(G, pBrush, pPoints)
}

DrawTextShapeGdip(G, shape) {
	DllCall("gdiplus\GdipSetTextRenderingHint", "UPtr", G, "Int", 4) ; AntiAlias

	fontName := shape.HasProp("font") ? shape.font : "Segoe UI"

	DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", fontName, "UPtr", 0, "UPtr*", &pFamily := 0)
	if (!pFamily) {
		DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Arial", "UPtr", 0, "UPtr*", &pFamily := 0)
	}
	if (!pFamily)
		return

	style := 0
	if (shape.HasProp("bold") && shape.bold)
		style |= 1
	if (shape.HasProp("italic") && shape.italic)
		style |= 2
	if (shape.HasProp("underline") && shape.underline)
		style |= 4

	fontSize := shape.HasProp("size") ? shape.size : 18
	DllCall("gdiplus\GdipCreateFont", "UPtr", pFamily, "Float", fontSize, "Int", style, "Int", 3, "UPtr*", &pFont := 0)
	if (!pFont) {
		DllCall("gdiplus\GdipDeleteFontFamily", "UPtr", pFamily)
		return
	}

	pBrush := Gdip_BrushCreateSolid(shape.color)
	DllCall("gdiplus\GdipCreateStringFormat", "Int", 0, "Int", 0, "UPtr*", &pFormat := 0)

	lineH := Round(fontSize * A_ScreenDPI / 72 * 1.35)

	for i, line in shape.lines {
		displayLine := line
		isLast := (i = shape.lines.Length)

		if (shape.HasProp("showCursor") && shape.showCursor && isLast)
			displayLine .= "|"
		if (displayLine = "")
			continue

		lineY := shape.y + (i - 1) * lineH

		rectF := Buffer(16, 0)
		NumPut("Float", Float(shape.x), rectF, 0)
		NumPut("Float", Float(lineY), rectF, 4)
		NumPut("Float", 8000.0, rectF, 8)
		NumPut("Float", Float(lineH * 2), rectF, 12)

		DllCall("gdiplus\GdipDrawString",
			"UPtr", G, "WStr", displayLine, "Int", -1,
			"UPtr", pFont, "UPtr", rectF.Ptr, "UPtr", pFormat, "UPtr", pBrush)
	}

	DllCall("gdiplus\GdipFlush", "UPtr", G, "Int", 1)

	if (pFormat)
		DllCall("gdiplus\GdipDeleteStringFormat", "UPtr", pFormat)
	if (pBrush)
		Gdip_DeleteBrush(pBrush)
	if (pFont)
		DllCall("gdiplus\GdipDeleteFont", "UPtr", pFont)
	if (pFamily)
		DllCall("gdiplus\GdipDeleteFontFamily", "UPtr", pFamily)
}

UpdateBuffer() {
	if (!gdi.G_Mem || !gdi.hdcBaked || !gdi.hdcMem || state.monitor.width <= 0 || state.monitor.height <= 0)
		return

	DllCall("BitBlt",
		"Ptr", gdi.hdcMem, "Int", 0, "Int", 0, "Int", state.monitor.width, "Int", state.monitor.height,
		"Ptr", gdi.hdcBaked, "Int", 0, "Int", 0, "UInt", 0x00CC0020)

	if (state.drawing && IsObject(draw.currentShape) && draw.currentShape.HasProp("type"))
		DrawShapesToGraphics(gdi.G_Mem, [draw.currentShape])

	if (state.textMode)
		DrawLiveText(gdi.G_Mem)
}

RefreshBakedBuffer() {
	if (!gdi.G_Baked || !gdi.hBitmapBackground || state.monitor.width <= 0 || state.monitor.height <= 0)
		return

	_FindLastClearOrFill(&lastClearIdx, &lastFillColor)

	if (lastFillColor >= 0) {
		solidColor := 0xFF000000 | lastFillColor
		DllCall("gdiplus\GdipGraphicsClear", "UPtr", gdi.G_Baked, "Int", solidColor)
	} else {
		Gdip_DrawImage(gdi.G_Baked, gdi.hBitmapBackground, 0, 0, state.monitor.width, state.monitor.height)
	}

	if (lastClearIdx < draw.history.Length) {
		visibleShapes := []
		loop draw.history.Length - lastClearIdx
			visibleShapes.Push(draw.history[lastClearIdx + A_Index])
		DrawShapesToGraphics(gdi.G_Baked, visibleShapes)
	}
}

_AppendShapeToBaked(shape) {
	if (!IsObject(shape) || !shape.HasProp("type") || shape.type == "clear" || shape.type == "fill")
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

GetOverlayPointFromLParam(lParam, &x, &y, clampToOverlay := false) {
	x := lParam << 48 >> 48
	y := lParam << 32 >> 48
	if (!clampToOverlay || state.monitor.width <= 0 || state.monitor.height <= 0)
		return
	x := Max(0, Min(x, state.monitor.width - 1))
	y := Max(0, Min(y, state.monitor.height - 1))
}

_FindLastClearOrFill(&outIdx, &outColor) {
	outIdx := 0
	outColor := -1
	i := draw.history.Length
	while (i > 0) {
		item := draw.history[i]
		if (IsObject(item) && item.HasProp("type")) {
			if (item.type == "clear") {
				outIdx := i
				outColor := -1
				return
			} else if (item.type == "fill") {
				outIdx := i
				outColor := item.color
				return
			}
		}
		i--
	}
}

DrawShapesToGraphics(G, shapesArray) {
	lastPenColor := -1, lastPenWidth := -1, pPen := 0
	lastFreePenColor := -1, lastFreePenWidth := -1, pFreePen := 0
	lastBrushColor := -1, pBrush := 0

	static LineCapRound := 1
	static LineJoinRound := 2

	for index, shape in shapesArray {
		if (!IsObject(shape) || !shape.HasProp("type") || shape.type == "clear" || shape.type == "fill")
			continue

		if (shape.type = "text") {
			try DrawTextShapeGdip(G, shape)
			continue
		}

		if (shape.type = "free") {
			if (shape.color != lastFreePenColor || shape.width != lastFreePenWidth) {
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
		} else {
			if (shape.color != lastPenColor || shape.width != lastPenWidth) {
				if (pPen)
					Gdip_DeletePen(pPen)
				pPen := Gdip_CreatePen(shape.color, shape.width)
				if (!pPen)
					continue
				lastPenColor := shape.color
				lastPenWidth := shape.width
			}
		}

		if (shape.type = "arrow" && shape.color != lastBrushColor) {
			if (pBrush)
				Gdip_DeleteBrush(pBrush)
			pBrush := Gdip_BrushCreateSolid(shape.color)
			if (pBrush)
				lastBrushColor := shape.color
		}

		try {
			switch shape.type {
				case "free":
					if (shape.HasProp("points") && shape.points.Length >= 2 && pFreePen)
						Gdip_DrawLines(G, pFreePen, shape.pointsStr)
				case "rect":
					Gdip_DrawRectangle(G, pPen,
						Min(shape.startX, shape.endX), Min(shape.startY, shape.endY),
						Abs(shape.endX - shape.startX), Abs(shape.endY - shape.startY))
				case "line":
					Gdip_DrawLine(G, pPen, shape.startX, shape.startY, shape.endX, shape.endY)
				case "ellipse":
					Gdip_DrawEllipse(G, pPen,
						Min(shape.startX, shape.endX), Min(shape.startY, shape.endY),
						Abs(shape.endX - shape.startX), Abs(shape.endY - shape.startY))
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


ARGB(rgb, a) => (a << 24) | (rgb & 0xFFFFFF)

;==============================================================================
; GDI+ Drawing Functions
;==============================================================================
Gdip_DrawRectangle(pGraphics, pPen, x, y, w, h) {
	return DllCall("gdiplus\GdipDrawRectangle", "UPtr", pGraphics, "UPtr", pPen, "Float", x, "Float", y, "Float", w, "Float", h)
}

Gdip_DrawEllipse(pGraphics, pPen, x, y, w, h) {
	return DllCall("gdiplus\GdipDrawEllipse", "UPtr", pGraphics, "UPtr", pPen, "Float", x, "Float", y, "Float", w, "Float", h)
}

Gdip_DrawLine(pGraphics, pPen, x1, y1, x2, y2) {
	return DllCall("gdiplus\GdipDrawLine", "UPtr", pGraphics, "UPtr", pPen, "Float", x1, "Float", y1, "Float", x2, "Float", y2)
}

Gdip_DrawLines(pGraphics, pPen, points) {
	points := StrSplit(points, "|")
	pointF := Buffer(8 * points.Length)
	pointsLength := 0
	for point in points {
		coords := StrSplit(point, ",")
		if (coords.Length != 2) {
			if (coords.Length > 0)
				OutputDebug("Gdip_DrawLines: Skipping malformed point at index " A_Index " (length=" coords.Length ")")
			continue
		}
		; Use pointsLength (not A_Index) as offset: A_Index counts all iterations
		; including skipped ones, which would leave gaps / read uninitialised memory.
		NumPut("Float", coords[1], pointF, 8 * pointsLength)
		NumPut("Float", coords[2], pointF, 8 * pointsLength + 4)
		pointsLength += 1
	}
	return DllCall("gdiplus\GdipDrawLines", "UPtr", pGraphics, "UPtr", pPen, "UPtr", pointF.Ptr, "Int", pointsLength)
}

Gdip_FillPolygon(pGraphics, pBrush, Points, FillMode := 0) {
	Points := StrSplit(Points, "|")
	PointsLength := Points.Length
	PointF := Buffer(8 * PointsLength)
	For eachPoint, Point in Points {
		Coord := StrSplit(Point, ",")
		NumPut("Float", Coord[1], PointF, 8 * (A_Index - 1))
		NumPut("Float", Coord[2], PointF, (8 * (A_Index - 1)) + 4)
	}
	return DllCall("gdiplus\GdipFillPolygon", "UPtr", pGraphics, "UPtr", pBrush, "UPtr", PointF.Ptr, "Int", PointsLength, "Int", FillMode)
}

Gdip_DrawImage(pGraphics, pBitmap, dx := "", dy := "", dw := "", dh := "", sx := "", sy := "", sw := "", sh := "", Matrix := 1) {
	ImageAttr := 0
	if !IsNumber(Matrix)
		ImageAttr := Gdip_SetImageAttributesColorMatrix(Matrix)
	else if (Matrix != 1)
		ImageAttr := Gdip_SetImageAttributesColorMatrix("1|0|0|0|0|0|1|0|0|0|0|0|1|0|0|0|0|0|" Matrix "|0|0|0|0|0|1")

	if (sx = "" && sy = "" && sw = "" && sh = "") {
		if (dx = "" && dy = "" && dw = "" && dh = "") {
			sx := dx := 0, sy := dy := 0
			sw := dw := Gdip_GetImageWidth(pBitmap)
			sh := dh := Gdip_GetImageHeight(pBitmap)
		} else {
			sx := sy := 0
			sw := Gdip_GetImageWidth(pBitmap)
			sh := Gdip_GetImageHeight(pBitmap)
		}
	}

	_E := DllCall("gdiplus\GdipDrawImageRectRect", "UPtr", pGraphics, "UPtr", pBitmap, "Float", dx, "Float", dy, "Float", dw, "Float", dh, "Float", sx, "Float", sy, "Float", sw, "Float", sh, "Int", 2, "UPtr", ImageAttr, "UPtr", 0, "UPtr", 0)
	if ImageAttr
		Gdip_DisposeImageAttributes(ImageAttr)
	return _E
}

Gdip_SetImageAttributesColorMatrix(Matrix) {
	ColourMatrix := Buffer(100, 0)
	Matrix := RegExReplace(RegExReplace(Matrix, "^[^\d-\.]+([\d\.])", "$1", , 1), "[^\d-\.]+", "|")
	Matrix := StrSplit(Matrix, "|")

	loop 25 {
		M := (Matrix[A_Index] != "") ? Matrix[A_Index] : Mod(A_Index - 1, 6) ? 0 : 1
		NumPut("Float", M, ColourMatrix, (A_Index - 1) * 4)
	}

	DllCall("gdiplus\GdipCreateImageAttributes", "UPtr*", &ImageAttr := 0)
	DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "UPtr", ImageAttr, "Int", 1, "Int", 1, "UPtr", ColourMatrix.Ptr, "UPtr", 0, "Int", 0)

	return ImageAttr
}

Gdip_DisposeImageAttributes(ImageAttr) {
	return DllCall("gdiplus\GdipDisposeImageAttributes", "UPtr", ImageAttr)
}

;==============================================================================
; GDI+ Resource Creation/Deletion
;==============================================================================
Gdip_CreatePen(ARGB, w) {
	DllCall("gdiplus\GdipCreatePen1", "UInt", ARGB, "Float", w, "Int", 2, "UPtr*", &pPen := 0)
	return pPen
}

Gdip_DeletePen(pPen) {
	return DllCall("gdiplus\GdipDeletePen", "UPtr", pPen)
}

Gdip_BrushCreateSolid(ARGB := 0xff000000) {
	DllCall("gdiplus\GdipCreateSolidFill", "UInt", ARGB, "UPtr*", &pBrush := 0)
	return pBrush
}

Gdip_DeleteBrush(pBrush) {
	return DllCall("gdiplus\GdipDeleteBrush", "UPtr", pBrush)
}

Gdip_DisposeImage(pBitmap) {
	return DllCall("gdiplus\GdipDisposeImage", "UPtr", pBitmap)
}

Gdip_DeleteGraphics(pGraphics) {
	return DllCall("gdiplus\GdipDeleteGraphics", "UPtr", pGraphics)
}

;==============================================================================
; GDI+ Graphics/Bitmap/Context Functions
;==============================================================================
Gdip_BitmapFromScreen(Screen := 0, Raster := "") {
	if (Screen = 0) {
		_x := DllCall("GetSystemMetrics", "Int", 76)
		_y := DllCall("GetSystemMetrics", "Int", 77)
		_w := DllCall("GetSystemMetrics", "Int", 78)
		_h := DllCall("GetSystemMetrics", "Int", 79)
	} else if IsInteger(Screen) {
		M := GetMonitorInfo(Screen)
		_x := M.Left, _y := M.Top, _w := M.Right - M.Left, _h := M.Bottom - M.Top
	} else {
		S := StrSplit(Screen, "|")
		_x := S[1], _y := S[2], _w := S[3], _h := S[4]
	}

	if (_x = "" || _y = "" || _w = "" || _h = "") {
		return -1
	}

	chdc := CreateCompatibleDC()
	hbm := CreateDIBSection(_w, _h, chdc)
	obm := SelectObject(chdc, hbm)
	hhdc := GetDC()
	BitBlt(chdc, 0, 0, _w, _h, hhdc, _x, _y, Raster)
	ReleaseDC(hhdc) ; Screen DC: ReleaseDC only — DeleteDC must NOT be called on GetDC handles

	pBitmap := Gdip_CreateBitmapFromHBITMAP(hbm)

	SelectObject(chdc, obm)
	DeleteObject(hbm)
	DeleteDC(chdc)
	return pBitmap
}

Gdip_CreateBitmapFromHBITMAP(hBitmap, Palette := 0) {
	DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "UPtr", hBitmap, "UPtr", Palette, "UPtr*", &pBitmap := 0)
	return pBitmap
}

CreateDIBSection(w, h, hdc := "", bpp := 32, &ppvBits := 0) {
	hdc2 := hdc ? hdc : GetDC()
	bi := Buffer(40, 0)

	NumPut("UInt", 40, "UInt", w, "UInt", h, "ushort", 1, "ushort", bpp, "UInt", 0, bi)

	hbm := DllCall("CreateDIBSection", "UPtr", hdc2, "UPtr", bi.Ptr, "UInt", 0, "UPtr*", &ppvBits, "UPtr", 0, "UInt", 0, "UPtr")

	if (!hdc) {
		ReleaseDC(hdc2)
	}
	return hbm
}

Gdip_GraphicsFromHDC(hdc) {
	DllCall("gdiplus\GdipCreateFromHDC", "UPtr", hdc, "UPtr*", &pGraphics := 0)
	return pGraphics
}

Gdip_GetImageWidth(pBitmap) {
	DllCall("gdiplus\GdipGetImageWidth", "UPtr", pBitmap, "uint*", &Width := 0)
	return Width
}

Gdip_GetImageHeight(pBitmap) {
	DllCall("gdiplus\GdipGetImageHeight", "UPtr", pBitmap, "uint*", &Height := 0)
	return Height
}

Gdip_SetSmoothingMode(pGraphics, SmoothingMode) {
	return DllCall("gdiplus\GdipSetSmoothingMode", "UPtr", pGraphics, "Int", SmoothingMode)
}

;==============================================================================
; GDI Functions
;==============================================================================

BitBlt(ddc, dx, dy, dw, dh, sdc, sx, sy, Raster := "") {
	return DllCall("gdi32\BitBlt", "UPtr", ddc, "Int", dx, "Int", dy, "Int", dw, "Int", dh, "UPtr", sdc, "Int", sx, "Int", sy, "UInt", Raster ? Raster : 0x00CC0020)
}

CreateCompatibleBitmap(hdc, w, h) {
	return DllCall("gdi32\CreateCompatibleBitmap", "UPtr", hdc, "Int", w, "Int", h)
}

CreateCompatibleDC(hdc := 0) {
	return DllCall("CreateCompatibleDC", "UPtr", hdc)
}

SelectObject(hdc, hgdiobj) {
	return DllCall("SelectObject", "UPtr", hdc, "UPtr", hgdiobj)
}

DeleteObject(hObject) {
	return DllCall("DeleteObject", "UPtr", hObject)
}

GetDC(hwnd := 0) {
	return DllCall("GetDC", "UPtr", hwnd)
}

ReleaseDC(hdc, hwnd := 0) {
	return DllCall("ReleaseDC", "UPtr", hwnd, "UPtr", hdc)
}

DeleteDC(hdc) {
	return DllCall("DeleteDC", "UPtr", hdc)
}

;==============================================================================
; Monitor Functions
;==============================================================================
MDMF_Enum(HMON := "") {
	static EnumProc := CallbackCreate(MDMF_EnumProc)
	static Monitors := Map()

	if (HMON = "") { ; new enumeration
		Monitors := Map("TotalCount", 0)
		if !DllCall("User32.dll\EnumDisplayMonitors", "Ptr", 0, "Ptr", 0, "Ptr", EnumProc, "Ptr", ObjPtr(Monitors), "Int")
			return False
	}

	return (HMON = "") ? Monitors : Monitors.Has(HMON) ? Monitors[HMON] : False
}

MDMF_EnumProc(HMON, HDC, PRECT, ObjectAddr) {
	Monitors := ObjFromPtrAddRef(ObjectAddr)

	Monitors[HMON] := MDMF_GetInfo(HMON)
	Monitors["TotalCount"]++
	if (Monitors[HMON].Primary) {
		Monitors["Primary"] := HMON
	}

	return true
}

MDMF_FromPoint(&X := "", &Y := "", Flag := 0) {
	if (X = "") || (Y = "") {
		PT := Buffer(8, 0)
		DllCall("User32.dll\GetCursorPos", "Ptr", PT.Ptr, "Int")

		if (X = "") {
			X := NumGet(PT, 0, "Int")
		}

		if (Y = "") {
			Y := NumGet(PT, 4, "Int")
		}
	}
	return DllCall("User32.dll\MonitorFromPoint", "Int64", (X & 0xFFFFFFFF) | (Y << 32), "UInt", Flag, "Ptr")
}

MDMF_GetInfo(HMON) {
	MIEX := Buffer(40 + (32 << !!1))
	NumPut("UInt", MIEX.Size, MIEX)
	if DllCall("User32.dll\GetMonitorInfo", "Ptr", HMON, "Ptr", MIEX.Ptr, "Int") {
		return { Name: (Name := StrGet(MIEX.Ptr + 40, 32)), ; CCHDEVICENAME = 32
			Num: RegExReplace(Name, ".*(\d+)$", "$1"),
			Left: NumGet(MIEX, 4, "Int"), ; display rectangle
			Top: NumGet(MIEX, 8, "Int"), ; "
			Right: NumGet(MIEX, 12, "Int"), ; "
			Bottom: NumGet(MIEX, 16, "Int"), ; "
			WALeft: NumGet(MIEX, 20, "Int"), ; work area
			WATop: NumGet(MIEX, 24, "Int"), ; "
			WARight: NumGet(MIEX, 28, "Int"), ; "
			WABottom: NumGet(MIEX, 32, "Int"), ; "
			Primary: NumGet(MIEX, 36, "UInt") } ; contains a non-zero value for the primary monitor.
	}
	return False
}

GetMonitorInfo(MonitorNum) {
	Monitors := MDMF_Enum()
	for k, v in Monitors {
		if (IsObject(v) && v.Num = MonitorNum) { ; Skip non-object entries (TotalCount, Primary)
			return v
		}
	}
}