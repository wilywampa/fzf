// +build tcell windows

package tui

import (
	"time"
	"unicode/utf8"

	"runtime"

	// https://github.com/gdamore/tcell/pull/135
	"github.com/junegunn/tcell"
	"github.com/junegunn/tcell/encoding"

	"github.com/junegunn/go-runewidth"
)

func (p ColorPair) style() tcell.Style {
	style := tcell.StyleDefault
	return style.Foreground(tcell.Color(p.Fg())).Background(tcell.Color(p.Bg()))
}

type Attr tcell.Style

type TcellWindow struct {
	color      bool
	top        int
	left       int
	width      int
	height     int
	lastX      int
	lastY      int
	moveCursor bool
	border     bool
}

func (w *TcellWindow) Top() int {
	return w.top
}

func (w *TcellWindow) Left() int {
	return w.left
}

func (w *TcellWindow) Width() int {
	return w.width
}

func (w *TcellWindow) Height() int {
	return w.height
}

func (w *TcellWindow) Refresh() {
	if w.moveCursor {
		_screen.ShowCursor(w.left+w.lastX, w.top+w.lastY)
		w.moveCursor = false
	}
	w.lastX = 0
	w.lastY = 0
	if w.border {
		w.drawBorder()
	}
}

func (w *TcellWindow) FinishFill() {
	// NO-OP
}

const (
	Bold      Attr = Attr(tcell.AttrBold)
	Dim            = Attr(tcell.AttrDim)
	Blink          = Attr(tcell.AttrBlink)
	Reverse        = Attr(tcell.AttrReverse)
	Underline      = Attr(tcell.AttrUnderline)
	Italic         = Attr(tcell.AttrNone) // Not supported
)

const (
	AttrRegular Attr = 0
)

func (r *FullscreenRenderer) defaultTheme() *ColorTheme {
	if _screen.Colors() >= 256 {
		return Dark256
	}
	return Default16
}

var (
	_colorToAttribute = []tcell.Color{
		tcell.ColorBlack,
		tcell.ColorRed,
		tcell.ColorGreen,
		tcell.ColorYellow,
		tcell.ColorBlue,
		tcell.ColorDarkMagenta,
		tcell.ColorLightCyan,
		tcell.ColorWhite,
	}
)

func (c Color) Style() tcell.Color {
	if c <= colDefault {
		return tcell.ColorDefault
	} else if c >= colBlack && c <= colWhite {
		return _colorToAttribute[int(c)]
	} else {
		return tcell.Color(c)
	}
}

func (a Attr) Merge(b Attr) Attr {
	return a | b
}

var (
	_screen tcell.Screen
)

func (r *FullscreenRenderer) initScreen() {
	s, e := tcell.NewScreen()
	if e != nil {
		errorExit(e.Error())
	}
	if e = s.Init(); e != nil {
		errorExit(e.Error())
	}
	if r.mouse {
		s.EnableMouse()
	} else {
		s.DisableMouse()
	}
	_screen = s
}

func (r *FullscreenRenderer) Init() {
	encoding.Register()

	r.initScreen()
	initTheme(r.theme, r.defaultTheme(), r.forceBlack)
}

func (r *FullscreenRenderer) MaxX() int {
	ncols, _ := _screen.Size()
	return int(ncols)
}

func (r *FullscreenRenderer) MaxY() int {
	_, nlines := _screen.Size()
	return int(nlines)
}

func (w *TcellWindow) X() int {
	return w.lastX
}

func (r *FullscreenRenderer) DoesAutoWrap() bool {
	return false
}

func (r *FullscreenRenderer) IsOptimized() bool {
	return false
}

func (r *FullscreenRenderer) Clear() {
	_screen.Sync()
	_screen.Clear()
}

func (r *FullscreenRenderer) Refresh() {
	// noop
}

func (r *FullscreenRenderer) GetChar() Event {
	ev := _screen.PollEvent()
	switch ev := ev.(type) {
	case *tcell.EventResize:
		return Event{Resize, 0, nil}

	// process mouse events:
	case *tcell.EventMouse:
		x, y := ev.Position()
		button := ev.Buttons()
		mod := ev.Modifiers() != 0
		if button&tcell.WheelDown != 0 {
			return Event{Mouse, 0, &MouseEvent{y, x, -1, false, false, mod}}
		} else if button&tcell.WheelUp != 0 {
			return Event{Mouse, 0, &MouseEvent{y, x, +1, false, false, mod}}
		} else if runtime.GOOS != "windows" {
			// double and single taps on Windows don't quite work due to
			// the console acting on the events and not allowing us
			// to consume them.

			down := button&tcell.Button1 != 0 // left
			double := false
			if down {
				now := time.Now()
				if now.Sub(r.prevDownTime) < doubleClickDuration {
					r.clickY = append(r.clickY, x)
				} else {
					r.clickY = []int{x}
					r.prevDownTime = now
				}
			} else {
				if len(r.clickY) > 1 && r.clickY[0] == r.clickY[1] &&
					time.Now().Sub(r.prevDownTime) < doubleClickDuration {
					double = true
				}
			}

			return Event{Mouse, 0, &MouseEvent{y, x, 0, down, double, mod}}
		}

		// process keyboard:
	case *tcell.EventKey:
		alt := (ev.Modifiers() & tcell.ModAlt) > 0
		switch ev.Key() {
		case tcell.KeyCtrlA:
			return Event{CtrlA, 0, nil}
		case tcell.KeyCtrlB:
			return Event{CtrlB, 0, nil}
		case tcell.KeyCtrlC:
			return Event{CtrlC, 0, nil}
		case tcell.KeyCtrlD:
			return Event{CtrlD, 0, nil}
		case tcell.KeyCtrlE:
			return Event{CtrlE, 0, nil}
		case tcell.KeyCtrlF:
			return Event{CtrlF, 0, nil}
		case tcell.KeyCtrlG:
			return Event{CtrlG, 0, nil}
		case tcell.KeyCtrlJ:
			return Event{CtrlJ, 0, nil}
		case tcell.KeyCtrlK:
			return Event{CtrlK, 0, nil}
		case tcell.KeyCtrlL:
			return Event{CtrlL, 0, nil}
		case tcell.KeyCtrlM:
			if alt {
				return Event{AltEnter, 0, nil}
			}
			return Event{CtrlM, 0, nil}
		case tcell.KeyCtrlN:
			return Event{CtrlN, 0, nil}
		case tcell.KeyCtrlO:
			return Event{CtrlO, 0, nil}
		case tcell.KeyCtrlP:
			return Event{CtrlP, 0, nil}
		case tcell.KeyCtrlQ:
			return Event{CtrlQ, 0, nil}
		case tcell.KeyCtrlR:
			return Event{CtrlR, 0, nil}
		case tcell.KeyCtrlS:
			return Event{CtrlS, 0, nil}
		case tcell.KeyCtrlT:
			return Event{CtrlT, 0, nil}
		case tcell.KeyCtrlU:
			return Event{CtrlU, 0, nil}
		case tcell.KeyCtrlV:
			return Event{CtrlV, 0, nil}
		case tcell.KeyCtrlW:
			return Event{CtrlW, 0, nil}
		case tcell.KeyCtrlX:
			return Event{CtrlX, 0, nil}
		case tcell.KeyCtrlY:
			return Event{CtrlY, 0, nil}
		case tcell.KeyCtrlZ:
			return Event{CtrlZ, 0, nil}
		case tcell.KeyBackspace, tcell.KeyBackspace2:
			if alt {
				return Event{AltBS, 0, nil}
			}
			return Event{BSpace, 0, nil}

		case tcell.KeyUp:
			return Event{Up, 0, nil}
		case tcell.KeyDown:
			return Event{Down, 0, nil}
		case tcell.KeyLeft:
			return Event{Left, 0, nil}
		case tcell.KeyRight:
			return Event{Right, 0, nil}

		case tcell.KeyHome:
			return Event{Home, 0, nil}
		case tcell.KeyDelete:
			return Event{Del, 0, nil}
		case tcell.KeyEnd:
			return Event{End, 0, nil}
		case tcell.KeyPgUp:
			return Event{PgUp, 0, nil}
		case tcell.KeyPgDn:
			return Event{PgDn, 0, nil}

		case tcell.KeyTab:
			return Event{Tab, 0, nil}
		case tcell.KeyBacktab:
			return Event{BTab, 0, nil}

		case tcell.KeyF1:
			return Event{F1, 0, nil}
		case tcell.KeyF2:
			return Event{F2, 0, nil}
		case tcell.KeyF3:
			return Event{F3, 0, nil}
		case tcell.KeyF4:
			return Event{F4, 0, nil}
		case tcell.KeyF5:
			return Event{F5, 0, nil}
		case tcell.KeyF6:
			return Event{F6, 0, nil}
		case tcell.KeyF7:
			return Event{F7, 0, nil}
		case tcell.KeyF8:
			return Event{F8, 0, nil}
		case tcell.KeyF9:
			return Event{F9, 0, nil}
		case tcell.KeyF10:
			return Event{F10, 0, nil}
		case tcell.KeyF11:
			return Event{F11, 0, nil}
		case tcell.KeyF12:
			return Event{F12, 0, nil}

		// ev.Ch doesn't work for some reason for space:
		case tcell.KeyRune:
			r := ev.Rune()
			if alt {
				switch r {
				case ' ':
					return Event{AltSpace, 0, nil}
				case '/':
					return Event{AltSlash, 0, nil}
				}
				if r >= 'a' && r <= 'z' {
					return Event{AltA + int(r) - 'a', 0, nil}
				}
				if r >= '0' && r <= '9' {
					return Event{Alt0 + int(r) - '0', 0, nil}
				}
			}
			return Event{Rune, r, nil}

		case tcell.KeyEsc:
			return Event{ESC, 0, nil}

		}
	}

	return Event{Invalid, 0, nil}
}

func (r *FullscreenRenderer) Pause() {
	_screen.Fini()
}

func (r *FullscreenRenderer) Resume() bool {
	r.initScreen()
	return true
}

func (r *FullscreenRenderer) Close() {
	_screen.Fini()
}

func (r *FullscreenRenderer) RefreshWindows(windows []Window) {
	// TODO
	for _, w := range windows {
		w.Refresh()
	}
	_screen.Show()
}

func (r *FullscreenRenderer) NewWindow(top int, left int, width int, height int, border bool) Window {
	// TODO
	return &TcellWindow{
		color:  r.theme != nil,
		top:    top,
		left:   left,
		width:  width,
		height: height,
		border: border}
}

func (w *TcellWindow) Close() {
	// TODO
}

func fill(x, y, w, h int, r rune) {
	for ly := 0; ly <= h; ly++ {
		for lx := 0; lx <= w; lx++ {
			_screen.SetContent(x+lx, y+ly, r, nil, ColDefault.style())
		}
	}
}

func (w *TcellWindow) Erase() {
	// TODO
	fill(w.left, w.top, w.width, w.height, ' ')
}

func (w *TcellWindow) Enclose(y int, x int) bool {
	return x >= w.left && x < (w.left+w.width) &&
		y >= w.top && y < (w.top+w.height)
}

func (w *TcellWindow) Move(y int, x int) {
	w.lastX = x
	w.lastY = y
	w.moveCursor = true
}

func (w *TcellWindow) MoveAndClear(y int, x int) {
	w.Move(y, x)
	for i := w.lastX; i < w.width; i++ {
		_screen.SetContent(i+w.left, w.lastY+w.top, rune(' '), nil, ColDefault.style())
	}
	w.lastX = x
}

func (w *TcellWindow) Print(text string) {
	w.printString(text, ColDefault, 0)
}

func (w *TcellWindow) printString(text string, pair ColorPair, a Attr) {
	t := text
	lx := 0

	var style tcell.Style
	if w.color {
		style = pair.style().
			Reverse(a&Attr(tcell.AttrReverse) != 0).
			Underline(a&Attr(tcell.AttrUnderline) != 0)
	} else {
		style = ColDefault.style().
			Reverse(a&Attr(tcell.AttrReverse) != 0 || pair == ColCurrent || pair == ColCurrentMatch).
			Underline(a&Attr(tcell.AttrUnderline) != 0 || pair == ColMatch || pair == ColCurrentMatch)
	}
	style = style.
		Blink(a&Attr(tcell.AttrBlink) != 0).
		Bold(a&Attr(tcell.AttrBold) != 0).
		Dim(a&Attr(tcell.AttrDim) != 0)

	for {
		if len(t) == 0 {
			break
		}
		r, size := utf8.DecodeRuneInString(t)
		t = t[size:]

		if r < rune(' ') { // ignore control characters
			continue
		}

		if r == '\n' {
			w.lastY++
			lx = 0
		} else {

			if r == '\u000D' { // skip carriage return
				continue
			}

			var xPos = w.left + w.lastX + lx
			var yPos = w.top + w.lastY
			if xPos < (w.left+w.width) && yPos < (w.top+w.height) {
				_screen.SetContent(xPos, yPos, r, nil, style)
			}
			lx += runewidth.RuneWidth(r)
		}
	}
	w.lastX += lx
}

func (w *TcellWindow) CPrint(pair ColorPair, attr Attr, text string) {
	w.printString(text, pair, attr)
}

func (w *TcellWindow) fillString(text string, pair ColorPair, a Attr) FillReturn {
	lx := 0

	var style tcell.Style
	if w.color {
		style = pair.style()
	} else {
		style = ColDefault.style()
	}
	style = style.
		Blink(a&Attr(tcell.AttrBlink) != 0).
		Bold(a&Attr(tcell.AttrBold) != 0).
		Dim(a&Attr(tcell.AttrDim) != 0).
		Reverse(a&Attr(tcell.AttrReverse) != 0).
		Underline(a&Attr(tcell.AttrUnderline) != 0)

	for _, r := range text {
		if r == '\n' {
			w.lastY++
			w.lastX = 0
			lx = 0
		} else {
			var xPos = w.left + w.lastX + lx

			// word wrap:
			if xPos >= (w.left + w.width) {
				w.lastY++
				w.lastX = 0
				lx = 0
				xPos = w.left
			}
			var yPos = w.top + w.lastY

			if yPos >= (w.top + w.height) {
				return FillSuspend
			}

			_screen.SetContent(xPos, yPos, r, nil, style)
			lx += runewidth.RuneWidth(r)
		}
	}
	w.lastX += lx

	return FillContinue
}

func (w *TcellWindow) Fill(str string) FillReturn {
	return w.fillString(str, ColDefault, 0)
}

func (w *TcellWindow) CFill(fg Color, bg Color, a Attr, str string) FillReturn {
	return w.fillString(str, ColorPair{fg, bg, -1}, a)
}

func (w *TcellWindow) drawBorder() {
	left := w.left
	right := left + w.width
	top := w.top
	bot := top + w.height

	var style tcell.Style
	if w.color {
		style = ColBorder.style()
	} else {
		style = ColDefault.style()
	}

	for x := left; x < right; x++ {
		_screen.SetContent(x, top, tcell.RuneHLine, nil, style)
		_screen.SetContent(x, bot-1, tcell.RuneHLine, nil, style)
	}

	for y := top; y < bot; y++ {
		_screen.SetContent(left, y, tcell.RuneVLine, nil, style)
		_screen.SetContent(right-1, y, tcell.RuneVLine, nil, style)
	}

	_screen.SetContent(left, top, tcell.RuneULCorner, nil, style)
	_screen.SetContent(right-1, top, tcell.RuneURCorner, nil, style)
	_screen.SetContent(left, bot-1, tcell.RuneLLCorner, nil, style)
	_screen.SetContent(right-1, bot-1, tcell.RuneLRCorner, nil, style)
}
