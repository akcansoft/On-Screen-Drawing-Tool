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

	DllCall("gdiplus\GdipSetPenEndCap", "UPtr", pPen, "Int", 0)  ; Flat cap
	Gdip_DrawLine(G, pPen, x1, y1, bx, by)

	pPoints := x2 "," y2 "|" (bx + W1) "," (by + W2) "|" (bx - W1) "," (by - W2)
	Gdip_FillPolygon(G, pBrush, pPoints)
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
	hhdc := 0
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
	hhdc := hhdc ? hhdc : GetDC()
	BitBlt(chdc, 0, 0, _w, _h, hhdc, _x, _y, Raster)
	ReleaseDC(hhdc)  ; Screen DC: ReleaseDC only — DeleteDC must NOT be called on GetDC handles

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
		if (IsObject(v) && v.Num = MonitorNum) {  ; Skip non-object entries (TotalCount, Primary)
			return v
		}
	}
}