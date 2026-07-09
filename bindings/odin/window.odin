package window

foreign import lib {"../../zig-out/lib/libwindow.a", "system:wayland-client", "system:wayland-cursor", "system:xkbcommon", "system:X11"}

Event_Kind :: enum u32 {
	None         = 0,
	Close        = 1,
	Resize       = 2,
	Key          = 3,
	Mouse_Button = 4,
	Mouse_Move   = 5,
	Mouse_Scroll = 6,
	Mouse_Enter  = 7,
	Mouse_Leave  = 8,
}

Action :: enum u32 {
	Press   = 0,
	Release = 1,
}

Mouse_Button :: enum u32 {
	Left   = 0,
	Right  = 1,
	Middle = 2,
}

Key :: enum u32 {
	Unknown = 0,
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	Num_0,
	Num_1,
	Num_2,
	Num_3,
	Num_4,
	Num_5,
	Num_6,
	Num_7,
	Num_8,
	Num_9,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	Escape,
	Enter,
	Tab,
	Backspace,
	Space,
	Minus,
	Equals,
	Left_Bracket,
	Right_Bracket,
	Backslash,
	Semicolon,
	Apostrophe,
	Grave,
	Comma,
	Period,
	Slash,
	Caps_Lock,
	Up,
	Down,
	Left,
	Right,
	Left_Shift,
	Right_Shift,
	Left_Control,
	Right_Control,
	Left_Alt,
	Right_Alt,
	Left_Super,
	Right_Super,
	Insert,
	Delete,
	Home,
	End,
	Page_Up,
	Page_Down,
	KP_0,
	KP_1,
	KP_2,
	KP_3,
	KP_4,
	KP_5,
	KP_6,
	KP_7,
	KP_8,
	KP_9,
	KP_Decimal,
	KP_Divide,
	KP_Multiply,
	KP_Subtract,
	KP_Add,
	KP_Enter,
	KP_Equal,
	Print_Screen,
	Scroll_Lock,
	Pause,
	Menu,
}

Event :: struct {
	kind:   Event_Kind,
	key:    Key,
	action: Action,
	button: Mouse_Button,
	x:      f32,
	y:      f32,
	dx:     f32,
	dy:     f32,
	width:  u32,
	height: u32,
}

Handles_Kind :: enum u32 {
	Wayland = 0,
	X11     = 1,
	Win32   = 2,
	Metal   = 3,
}

Native_Handles :: struct {
	kind:    Handles_Kind,
	display: rawptr,
	surface: rawptr,
	window:  u64,
}

@(default_calling_convention = "c", link_prefix = "window_")
foreign lib {
	init :: proc(width, height: u32, title: cstring) -> i32 ---
	deinit :: proc() ---
	should_close :: proc() -> u32 ---
	poll_events :: proc() ---
	next_event :: proc(out: ^Event) -> u32 ---
	native_handles :: proc(out: ^Native_Handles) -> u32 ---
	size :: proc(w, h: ^u32) ---
}
