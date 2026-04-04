# On Screen Drawing Tool

[![AutoHotkey](https://img.shields.io/badge/Language-AutoHotkey_v2-green.svg)](https://www.autohotkey.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-GPL-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.8-brightgreen.svg)](https://github.com/akcansoft/On-Screen-Drawing-Tool/releases)

![GitHub stars](https://img.shields.io/github/stars/akcansoft/On-Screen-Drawing-Tool?style=social)
![GitHub forks](https://img.shields.io/github/forks/akcansoft/On-Screen-Drawing-Tool?style=social)
![GitHub issues](https://img.shields.io/github/issues/akcansoft/On-Screen-Drawing-Tool)
[![Downloads](https://img.shields.io/github/downloads/akcansoft/On-Screen-Drawing-Tool/total)](https://github.com/akcansoft/On-Screen-Drawing-Tool/releases)

Lightweight on-screen annotation tool for Windows, built with AutoHotkey v2 and GDI+.

Draw directly on top of any screen with multiple tools (freehand, line, rectangle, ellipse, circle, arrow), type text directly on the overlay, configurable hotkeys, background fill, and an INI-based settings system. Run it as source (`.ahk`) or as a compiled standalone `.exe`.

![](docs/screen-shot-1.png)

## Highlights

- Fast overlay drawing with GDI+ anti-aliased rendering
- Drawing tools: freehand, straight line, rectangle, ellipse, circle, arrow
- **Text mode** — type text directly on the overlay; click to place, Enter for new line, configurable font, size, and color
- **Ortho mode** (F8 by default) — locks line and arrow drawing to horizontal or vertical axis
- **Background fill** — fill the screen with a solid color using a modifier + color hotkey, creating whiteboard, blackboard, or colored canvas effects (undoable)
- Dynamic line width and opacity controls
- Color palette with single-key shortcuts (fully configurable via Settings)
- Built-in always-on-top help dialog with searchable hotkeys list (<kbd>F1</kbd> by default, configurable)
- **Undo / Redo** support for all drawing actions including clear and fill — full linear history, no steps lost
- Clear all drawings with a single key; clear is itself undoable/redoable
- Right-click drawing toolbar: color picker, line width, opacity, quick actions, and per-control tooltips
- Pen cursor while drawing mode is active
- **Always-on-top** help and settings windows that don't get lost behind the overlay
- Multi-monitor support — starts on the monitor the mouse cursor is on
- Per-monitor DPI awareness with multiple fallbacks for mixed-scaling setups
- Shapes are preserved across drawing sessions (within the same monitor)
- Remembers last used drawing settings (color, line width, opacity) across restarts

## Requirements

- Windows
- [AutoHotkey v2.x](https://www.autohotkey.com/) (for source usage only)
- `Gdip.ahk` in the same folder as the main script

If you use the compiled `.exe`, **AutoHotkey installation** is not required.

## Quick Start

### Option 1: Run from source

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Keep these files in the same directory:
   - `On Screen Drawing.ahk`
   - `Gdip.ahk`
   - `AppLib.ahk`
   - `CommonDialog.ahk`
   - `Settings.ahk`
   - `Help.ahk`
   - `DrawText.ahk`
   - `CtrlToolTip.ahk`
   - `settings.ini` (optional — defaults are applied automatically)
   - `app_icon.ico` (optional — used for the tray icon)
3. Run `On Screen Drawing.ahk`.
4. Press <kbd>Ctrl</kbd>+<kbd>F9</kbd> (default) to start drawing mode.

### Option 2: Run compiled EXE

1. Download the latest release `.exe` from the [Releases](https://github.com/akcansoft/On-Screen-Drawing-Tool/releases) page.
2. Optionally place `settings.ini` next to the `.exe` for custom settings.
3. Run the executable.

## Default Controls

### Global hotkeys (always active)

| Hotkey | Action |
| --- | --- |
| <kbd>Ctrl</kbd>+<kbd>F9</kbd> | Toggle drawing mode on/off |
| <kbd>F1</kbd> | Show hotkeys help |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F12</kbd> | Exit the application |

### While in drawing mode

| Hotkey / Action | Description |
| --- | --- |
| <kbd>Esc</kbd> | Clear all drawings (undoable) |
| <kbd>Ctrl</kbd>+<kbd>Z</kbd> | Undo last action (shape, clear or fill) |
| <kbd>Ctrl</kbd>+<kbd>Y</kbd> | Redo last undone action |
| <kbd>XButton1</kbd> (Mouse Back) | Undo last action |
| <kbd>XButton2</kbd> (Mouse Forward) | Redo last undone action |
| <kbd>F8</kbd> | Toggle Ortho mode (line/arrow only) |
| <kbd>t</kbd> | Enter text mode |
| <kbd>Ctrl</kbd>+<kbd>NumpadAdd</kbd> | Increase line width |
| <kbd>Ctrl</kbd>+<kbd>NumpadSub</kbd> | Decrease line width |
| <kbd>WheelUp</kbd> / <kbd>WheelDown</kbd> | Increase / decrease line width |
| Right-click on overlay | Open drawing toolbar |

### While in text mode

| Hotkey / Action | Description |
| --- | --- |
| Left-click on overlay | Commit current text (if any) and place cursor at new position |
| <kbd>Enter</kbd> | New line |
| <kbd>Esc</kbd> | Commit text and exit text mode |
| <kbd>F2</kbd> | Decrease font size |
| <kbd>F3</kbd> | Increase font size |
| <kbd>F4</kbd> | Cycle through palette colors |

### Tool selection (hold modifier while clicking to draw)

| Modifier | Tool |
| --- | --- |
| *(none)* | Freehand |
| <kbd>Shift</kbd> | Straight line |
| <kbd>Ctrl</kbd> | Rectangle |
| <kbd>Alt</kbd> | Ellipse |
| <kbd>Ctrl</kbd>+<kbd>Alt</kbd> | Circle (radius = max of X/Y drag distance) |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd> | Arrow (with auto-sized filled arrowhead) |

### Color hotkeys (default, configurable in Settings)

| Key | Color | Key | Color | Key | Color |
| --- | --- | --- | --- | --- | --- |
| <kbd>r</kbd> | Red | <kbd>m</kbd> | Magenta | <kbd>s</kbd> | Brown |
| <kbd>g</kbd> | Green | <kbd>c</kbd> | Cyan | <kbd>w</kbd> | White |
| <kbd>b</kbd> | Blue | <kbd>o</kbd> | Orange | <kbd>n</kbd> | Gray |
| <kbd>y</kbd> | Yellow | <kbd>v</kbd> | Violet | <kbd>k</kbd> | Black |

> Color hotkeys are only active while drawing mode is on and the mouse cursor is on the active monitor.
> Press <kbd>Shift</kbd> + a color key (modifier configurable in Settings) to fill the entire background with that color — useful for whiteboard, blackboard, or colored canvas effects. The fill is undoable.

## Text Mode

Press <kbd>t</kbd> (configurable) while in drawing mode to enter text mode. The cursor changes to an I-beam.

Click anywhere on the overlay to place a text cursor. Type your text — <kbd>Enter</kbd> inserts a new line. Clicking a different position commits the current text and starts a new one at the clicked location. Press <kbd>Esc</kbd> to commit and exit text mode. Committed text is added to the undo/redo history.

While in text mode:
- <kbd>F2</kbd> / <kbd>F3</kbd> decrease / increase the font size on the fly.
- <kbd>F4</kbd> cycles through the configured color palette.
- Font, size, bold, italic, and underline are configured in **Settings > Text** tab.

## Background Fill

Press the fill modifier key (default: <kbd>Shift</kbd>) together with a color hotkey to fill the screen background with a solid color — great for whiteboard, blackboard, or colored canvas effects. The fill is treated as a step in the undo/redo history — press <kbd>Ctrl</kbd>+<kbd>Z</kbd> to revert it.

The fill modifier key can be changed to Ctrl, Alt, or Win in Settings > Hotkeys.

When a fill is active, pressing <kbd>Esc</kbd> (Clear) preserves the background fill color and only removes the shapes drawn on top of it.

## Ortho Mode

Press <kbd>F8</kbd> (configurable) while in drawing mode to toggle Ortho mode on/off. A tooltip confirms the current state.

When Ortho mode is active, **line** and **arrow** tools are constrained to the dominant axis — horizontal if the horizontal drag distance is greater, vertical otherwise. All other tools (freehand, rect, ellipse, circle) are unaffected.

## Undo / Redo

The undo/redo system treats every action — including **Clear** and **Fill** — as a step in a single linear history. You can freely undo and redo across clear and fill operations without losing any shapes.

The history size limit (`MaxHistorySize`, default 200) applies to the total number of entries including clear and fill markers.

## Drawing Toolbar

Right-clicking anywhere on the overlay opens a compact floating toolbar:

![](docs/screen-shot-2.png) ![](docs/screen-shot-3.png)

- **Color grid** — configured colors in a 3-column grid. Active color marked with ✓; hotkey hints shown on each swatch (configurable).
- **Line width** — numeric edit field with up/down spinner.
- **Opacity** — numeric edit field with up/down spinner (0–255).
- **Quick action buttons:** Undo, Redo, Clear, Help, Stop Drawing, Exit App
- **Tooltips:** line width, opacity, and action buttons show hover hints; configured hotkeys are included where applicable

The toolbar snaps within the active monitor's bounds. Press <kbd>Esc</kbd> or click away to close it.

## Tray Menu

Right-clicking the tray icon shows:

- **Help** — displays the help window (app info, hotkeys, author links)
- **Settings** — opens the application settings window
- **Restart Application** — reloads the script
- **Start / Stop Drawing** — toggles drawing mode
- **Exit** — closes the app

## Settings Window

Open via tray menu or the Settings button in the Help window. Changes to hotkeys or colors require a restart to take effect (the app will prompt you).

Tabs:
- **General** — numeric settings and behavior toggles
- **Hotkeys** — all configurable hotkeys
- **Colors** — color palette management (add, edit, delete entries)
- **Text** — font picker (family, size, bold, italic, underline) with live preview

## settings.ini Reference

The app reads `settings.ini` from the script/exe directory on startup. Missing keys fall back to defaults.

> All settings can also be edited through the built-in **Settings window** (tray menu → Settings). Changes are saved back to `settings.ini` automatically.

### [Settings] keys

| Key | Description | Default |
| --- | --- | --- |
| `MinLineWidth` | Minimum allowed stroke width | `1` |
| `MaxLineWidth` | Maximum allowed stroke width | `10` |
| `DrawAlpha` | Drawing opacity (0–255) | `200` |
| `FrameIntervalMs` | Overlay redraw interval (ms) | `16` |
| `MinPointStep` | Min pixel distance between freehand points | `3` |
| `MaxHistorySize` | Maximum undo/redo steps | `200` |
| `ClearOnExitDraw` | Discard shapes when exiting drawing mode | `false` |
| `ShowColorHints` | Show hotkey hints on color swatches | `true` |
| `SaveLastUsedOnExit` | Remember color, width, opacity on exit | `true` |
| `showHelpOnStartup` | Show help window on application start | `true` |
| `TextFont` | Font family for text mode | `Segoe UI` |
| `TextSize` | Font size for text mode (6–200) | `18` |
| `TextBold` | Bold text | `false` |
| `TextItalic` | Italic text | `false` |
| `TextUnderline` | Underline text | `false` |

### [Hotkeys] keys

| Key | Description | Default |
| --- | --- | --- |
| `ToggleDrawingMode` | Start/Stop drawing | `^F9` |
| `ExitApp` | Close application | `^+F12` |
| `ClearDrawing` | Clear all shapes | `Esc` |
| `UndoDrawing` | Undo last action | `^z` |
| `RedoDrawing` | Redo last undone action | `^y` |
| `IncreaseLineWidth` | Line width + | `^NumpadAdd` |
| `DecreaseLineWidth` | Line width - | `^NumpadSub` |
| `OrthoMode` | Toggle ortho mode | `F8` |
| `HotkeysHelp` | Show help window | `F1` |
| `FillModifier` | Modifier key for background fill | `+` (Shift) |
| `TextMode` | Enter text mode | `t` |
| `ExitTextMode` | Commit text and exit text mode | `Esc` |
| `DecreaseTextSize` | Decrease font size in text mode | `F2` |
| `IncreaseTextSize` | Increase font size in text mode | `F3` |
| `CycleTextColor` | Cycle text color through palette | `F4` |

Hotkey syntax: `^` = Ctrl, `+` = Shift, `!` = Alt, `#` = Win. Example: `^+F9` = Ctrl+Shift+F9.

## Project Structure

```
On Screen Drawing.ahk           — Main script
AppLib.ahk                      — Config classes and shared helpers
CommonDialog.ahk                — Font and color picker dialog wrappers
Settings.ahk                    — Settings window
Help.ahk                        — Help window
DrawText.ahk                    — Text mode implementation
CtrlToolTip.ahk                 — Helper for standard Windows tooltips on GUI controls
Gdip.ahk                        — GDI+ wrapper library
settings.ini                    — User configuration
app_icon.ico                    — Tray icon
```
## Version History

### v1.8 04/04/2026

- **Toolbar tooltips**: Added standard Windows tooltips to the compact drawing toolbar controls using `CtrlToolTip.ahk`.
- **Better toolbar guidance**: Hovering line width, opacity, undo, redo, clear, help, stop drawing, and exit app controls now explains each action and shows assigned hotkeys where relevant.
- **Help/About polish**: The always-on-top Help window remains the central searchable reference for app actions and hotkeys.

### v1.7 23/03/2026

- **Text Mode**: Press `t` (configurable) in drawing mode to enter text mode. Click anywhere on the overlay to place a text cursor and start typing. Enter inserts a new line; Esc commits the text and exits text mode. Committed text is fully undoable/redoable.
- **Font settings**: Font family, size, bold, italic, and underline are configurable in Settings > Text tab via a native font picker dialog with live preview.
- **Text mode hotkeys**: Decrease/increase font size (F2/F3), cycle through palette colors (F4) — all configurable.
- **New file**: `DrawText.ahk` contains all text mode logic. `CommonDialog.ahk` provides font and color picker dialog wrappers.
- **Help window search**: The hotkeys list in the Help window now has a live search box — type to filter actions or hotkeys instantly.

### v1.6 20/03/2026

- **Background Fill**: Press Shift (configurable) + a color hotkey to fill the screen background with a solid color — useful for whiteboard, blackboard, or colored canvas effects. The fill is fully undoable/redoable. Clear (Esc) preserves the active fill color.
- **Configurable fill modifier**: The fill modifier key (Shift, Ctrl, Alt, Win) can be changed in Settings > Hotkeys.
- **Freehand fix**: A very short freehand stroke (2 points) is no longer discarded.

### v1.5 19/03/2026

- **Settings Window**: All application settings (general options, hotkeys, color palette) can now be edited through a built-in GUI. Changes are saved to `settings.ini` automatically; hotkey and color changes take effect after restart.
- **Help Window**: The separate About dialog and hotkeys help message box have been merged into a single always-on-top Help window. Includes app info, author links, full hotkey list, and a startup visibility toggle.
- **Ortho Mode**: New F8 toggle (configurable) constrains line and arrow drawing to horizontal or vertical axis, similar to CAD ortho mode.
- **Undo/Redo overhaul**: Clear is now a fully undoable/redoable step in the linear history. No shapes are lost when undoing or redoing across clear operations.
- **Standard undo/redo hotkeys**: Changed from Backspace/Shift+Backspace to Ctrl+Z / Ctrl+Y.

### v1.4 12/03/2026

- **Persistent Settings**: Automatically saves last used color, line width, and opacity on exit and restores them on next launch.
- **Performance Optimization**: Major improvements to freehand drawing to avoid memory bottlenecks.
- **Code Organization**: Restructured configuration classes and grouped global variables.

### v1.3 08/03/2026

- **UI Enhancement**: Added hotkey hints to color swatches in the right-click settings panel.
- **New Setting**: `ShowColorHints` option to disable color hotkey hints.

### v1.2.2 07/03/2026

- **Enhanced Undo/Redo**: Added support for undoing Clear Drawing actions.
- **Interaction Fixes**: Mouse wheel no longer interferes with numeric edit boxes in the settings panel.
- **Code Refactoring**: Centralized application state using a unified `App` object and `DrawingColors` class.

### v1.2.0 06/03/2026

- **Redo Support**: Added `RedoLastShape` functionality with a redo stack.
- **Mouse Shortcuts**: Undo/redo via mouse side buttons (XButton1/XButton2).
- **Improved Settings GUI**: Added Clear and Help buttons; reordered action buttons.

### v1.1.0 05/03/2026

- Added configurable `HotkeysHelp` action (F1 default).
- Added pen cursor while drawing mode is active.
- Improved floating settings panel (hide/reopen instead of recreate).
- Updated tray menu labels to show assigned hotkeys.

### v1.0.0 05/03/2026

- Initial public release.
- Overlay drawing tools: freehand, line, rectangle, ellipse, circle, arrow.
- Configurable hotkeys, color shortcuts, tray menu, `settings.ini` support.

## Troubleshooting

**Nothing happens when pressing the toggle hotkey**
- Check `ToggleDrawingMode` in `settings.ini`.
- Ensure no other application is capturing the same hotkey.

**Error about GDI+ on startup**
- Verify that `Gdip.ahk` exists in the same folder as the script and is compatible with AHK v2.

**Wrong position or scale on multi-monitor / mixed-DPI setups**
- The script applies per-monitor DPI awareness with multiple fallbacks. Restart after changing monitor layout or DPI settings.

**Color hotkeys do not work while drawing**
- Confirm all `[Colors]` entries use the `0xRRGGBB` format.
- Make sure the mouse cursor is on the active drawing monitor.

**Shapes disappear when re-entering drawing mode**
- Check that `ClearOnExitDraw` is set to `false` in `settings.ini`.
- Note: switching to a different monitor always resets the shape history.

**Text mode does not accept keyboard input**
- Make sure no other window has focus. The overlay must be the active window while in text mode.
- Try clicking on the overlay again to re-place the text cursor.

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/akcansoft/On-Screen-Drawing-Tool).

When reporting a bug, please include:
- Windows version
- AutoHotkey version (if running from source)
- Your `settings.ini` contents
- Steps to reproduce

## Credits

- [Gdip_All.ahk](https://github.com/buliasz/AHKv2-Gdip/blob/master/Gdip_All.ahk) by [buliasz](https://github.com/buliasz) — GDI+ wrapper library for AutoHotkey v2. `Gdip.ahk` included in this project contains only the functions required by this project, extracted from the original.

## Author

**Mesut Akcan**

- GitHub: [akcansoft](https://github.com/akcansoft)
- Blog: [mesutakcan.blogspot.com](https://mesutakcan.blogspot.com)
- YouTube: [youtube.com/mesutakcan](https://www.youtube.com/mesutakcan)
