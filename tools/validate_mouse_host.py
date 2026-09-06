#!/usr/bin/env python3
"""Inject real X11 pointer/key events into one uniquely titled probe window."""

from __future__ import annotations

import argparse
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any, Callable


Display = ctypes.c_void_p
Window = ctypes.c_ulong
Atom = ctypes.c_ulong
Status = ctypes.c_int

CAPTURED = 2
VISIBLE = 0
CURRENT_TIME = 0
REVERT_TO_PARENT = 2
BUTTON_LEFT = 1
KEY_PRESS = True
KEY_RELEASE = False
XK_ESCAPE = 0xFF1B


class X11:
    def __init__(self) -> None:
        self.x11 = ctypes.CDLL("libX11.so.6")
        self.xtst = ctypes.CDLL("libXtst.so.6")
        self._configure()
        self.display = self.x11.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError("XOpenDisplay failed; an X11 display is required")
        self.screen = self.x11.XDefaultScreen(self.display)
        self.root = self.x11.XRootWindow(self.display, self.screen)
        self.net_wm_name = self.x11.XInternAtom(self.display, b"_NET_WM_NAME", False)

    def _configure(self) -> None:
        self.x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x11.XOpenDisplay.restype = Display
        self.x11.XCloseDisplay.argtypes = [Display]
        self.x11.XCloseDisplay.restype = ctypes.c_int
        self.x11.XDefaultScreen.argtypes = [Display]
        self.x11.XDefaultScreen.restype = ctypes.c_int
        self.x11.XRootWindow.argtypes = [Display, ctypes.c_int]
        self.x11.XRootWindow.restype = Window
        self.x11.XQueryTree.argtypes = [
            Display,
            Window,
            ctypes.POINTER(Window),
            ctypes.POINTER(Window),
            ctypes.POINTER(ctypes.POINTER(Window)),
            ctypes.POINTER(ctypes.c_uint),
        ]
        self.x11.XQueryTree.restype = Status
        self.x11.XFetchName.argtypes = [Display, Window, ctypes.POINTER(ctypes.c_char_p)]
        self.x11.XFetchName.restype = Status
        self.x11.XInternAtom.argtypes = [Display, ctypes.c_char_p, ctypes.c_int]
        self.x11.XInternAtom.restype = Atom
        self.x11.XGetWindowProperty.argtypes = [
            Display,
            Window,
            Atom,
            ctypes.c_long,
            ctypes.c_long,
            ctypes.c_int,
            Atom,
            ctypes.POINTER(Atom),
            ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte)),
        ]
        self.x11.XGetWindowProperty.restype = ctypes.c_int
        self.x11.XFree.argtypes = [ctypes.c_void_p]
        self.x11.XFree.restype = ctypes.c_int
        self.x11.XSetInputFocus.argtypes = [Display, Window, ctypes.c_int, ctypes.c_ulong]
        self.x11.XSetInputFocus.restype = ctypes.c_int
        self.x11.XRaiseWindow.argtypes = [Display, Window]
        self.x11.XRaiseWindow.restype = ctypes.c_int
        self.x11.XGetInputFocus.argtypes = [Display, ctypes.POINTER(Window), ctypes.POINTER(ctypes.c_int)]
        self.x11.XGetInputFocus.restype = ctypes.c_int
        self.x11.XQueryPointer.argtypes = [
            Display,
            Window,
            ctypes.POINTER(Window),
            ctypes.POINTER(Window),
            ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_uint),
        ]
        self.x11.XQueryPointer.restype = ctypes.c_int
        self.x11.XWarpPointer.argtypes = [Display, Window, Window, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint, ctypes.c_int, ctypes.c_int]
        self.x11.XWarpPointer.restype = ctypes.c_int
        self.x11.XGetGeometry.argtypes = [
            Display,
            Window,
            ctypes.POINTER(Window),
            ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_uint),
            ctypes.POINTER(ctypes.c_uint),
            ctypes.POINTER(ctypes.c_uint),
            ctypes.POINTER(ctypes.c_uint),
        ]
        self.x11.XGetGeometry.restype = Status
        self.x11.XKeysymToKeycode.argtypes = [Display, ctypes.c_ulong]
        self.x11.XKeysymToKeycode.restype = ctypes.c_uint
        self.x11.XSync.argtypes = [Display, ctypes.c_int]
        self.x11.XSync.restype = ctypes.c_int

        self.xtst.XTestFakeRelativeMotionEvent.argtypes = [Display, ctypes.c_int, ctypes.c_int, ctypes.c_ulong, ctypes.c_void_p]
        self.xtst.XTestFakeRelativeMotionEvent.restype = Status
        self.xtst.XTestFakeButtonEvent.argtypes = [Display, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.xtst.XTestFakeButtonEvent.restype = Status
        self.xtst.XTestFakeKeyEvent.argtypes = [Display, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.xtst.XTestFakeKeyEvent.restype = Status

    def close(self) -> None:
        if self.display:
            self.x11.XCloseDisplay(self.display)
            self.display = None

    def _window_name(self, window: Window) -> str:
        # Modern compositors expose the visible title as UTF8 _NET_WM_NAME;
        # XFetchName alone often returns Godot's initial WM_NAME instead.
        actual_type = Atom()
        actual_format = ctypes.c_int()
        item_count = ctypes.c_ulong()
        bytes_after = ctypes.c_ulong()
        property_data = ctypes.POINTER(ctypes.c_ubyte)()
        status = self.x11.XGetWindowProperty(
            self.display,
            window,
            self.net_wm_name,
            0,
            1024,
            False,
            Atom(0),
            ctypes.byref(actual_type),
            ctypes.byref(actual_format),
            ctypes.byref(item_count),
            ctypes.byref(bytes_after),
            ctypes.byref(property_data),
        )
        if status == 0 and property_data and item_count.value:
            try:
                return ctypes.string_at(property_data, item_count.value).decode("utf-8", errors="replace")
            finally:
                self.x11.XFree(property_data)
        name = ctypes.c_char_p()
        if not self.x11.XFetchName(self.display, window, ctypes.byref(name)) or not name.value:
            return ""
        try:
            return name.value.decode("utf-8", errors="replace")
        finally:
            self.x11.XFree(name)

    def find_exact_title(self, title: str) -> Window | None:
        def walk(window: Window) -> Window | None:
            if self._window_name(window) == title:
                return window
            root_return = Window()
            parent_return = Window()
            children = ctypes.POINTER(Window)()
            count = ctypes.c_uint()
            if not self.x11.XQueryTree(
                self.display,
                window,
                ctypes.byref(root_return),
                ctypes.byref(parent_return),
                ctypes.byref(children),
                ctypes.byref(count),
            ):
                return None
            try:
                for index in range(count.value):
                    found = walk(children[index])
                    if found is not None:
                        return found
            finally:
                if children:
                    self.x11.XFree(children)
            return None

        return walk(self.root)

    def focus(self, window: Window) -> None:
        self.x11.XRaiseWindow(self.display, window)
        self.x11.XSetInputFocus(self.display, window, REVERT_TO_PARENT, CURRENT_TIME)
        self.x11.XSync(self.display, False)

    def geometry(self, window: Window) -> tuple[int, int, int, int]:
        root = Window()
        x = ctypes.c_int()
        y = ctypes.c_int()
        width = ctypes.c_uint()
        height = ctypes.c_uint()
        border = ctypes.c_uint()
        depth = ctypes.c_uint()
        if not self.x11.XGetGeometry(self.display, window, ctypes.byref(root), ctypes.byref(x), ctypes.byref(y), ctypes.byref(width), ctypes.byref(height), ctypes.byref(border), ctypes.byref(depth)):
            raise RuntimeError("XGetGeometry failed for probe window")
        return x.value, y.value, width.value, height.value

    def save_pointer(self) -> tuple[int, int]:
        root_return = Window()
        child_return = Window()
        root_x = ctypes.c_int()
        root_y = ctypes.c_int()
        win_x = ctypes.c_int()
        win_y = ctypes.c_int()
        mask = ctypes.c_uint()
        self.x11.XQueryPointer(self.display, self.root, ctypes.byref(root_return), ctypes.byref(child_return), ctypes.byref(root_x), ctypes.byref(root_y), ctypes.byref(win_x), ctypes.byref(win_y), ctypes.byref(mask))
        return root_x.value, root_y.value

    def save_focus(self) -> Window:
        focus = Window()
        revert = ctypes.c_int()
        self.x11.XGetInputFocus(self.display, ctypes.byref(focus), ctypes.byref(revert))
        return focus

    def restore_pointer(self, position: tuple[int, int]) -> None:
        self.x11.XWarpPointer(self.display, Window(0), self.root, 0, 0, 0, 0, position[0], position[1])
        self.x11.XSync(self.display, False)

    def restore_focus(self, window: Window) -> None:
        focus_value = window.value if hasattr(window, "value") else int(window)
        if focus_value and focus_value != 0x1:
            self.x11.XSetInputFocus(self.display, window, REVERT_TO_PARENT, CURRENT_TIME)
            self.x11.XSync(self.display, False)

    def relative_motion(self, dx: int, dy: int) -> None:
        self.xtst.XTestFakeRelativeMotionEvent(self.display, dx, dy, 0, None)
        self.x11.XSync(self.display, False)

    def button(self, button: int, pressed: bool) -> None:
        self.xtst.XTestFakeButtonEvent(self.display, button, int(pressed), 0)
        self.x11.XSync(self.display, False)

    def click(self, button: int = BUTTON_LEFT) -> None:
        self.button(button, True)
        self.button(button, False)

    def key(self, keysym: int, pressed: bool) -> None:
        keycode = self.x11.XKeysymToKeycode(self.display, keysym)
        if not keycode:
            raise RuntimeError(f"XKeysymToKeycode failed for {keysym:#x}")
        self.xtst.XTestFakeKeyEvent(self.display, keycode, int(pressed), 0)
        self.x11.XSync(self.display, False)

    def press_key(self, keysym: int) -> None:
        self.key(keysym, KEY_PRESS)
        self.key(keysym, KEY_RELEASE)


def read_state(path: Path) -> dict[str, Any] | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def wait_for(path: Path, predicate: Callable[[dict[str, Any]], bool], timeout: float, label: str) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = read_state(path)
        if state is not None and predicate(state):
            return state
        time.sleep(0.05)
    state = read_state(path)
    raise RuntimeError(f"timed out waiting for {label}; last state={state}")


def launch_probe(args: argparse.Namespace, title: str, artifact: Path) -> subprocess.Popen[str]:
    godot = args.godot_bin or os.environ.get("GODOT_BIN") or str(args.project_root / ".tools/godot/4.7.2/godot")
    command = [godot, "--path", str(args.project_root), "--display-driver", "x11", "--script", "tools/mouse_probe.gd"]
    env = os.environ.copy()
    env["MOUSE_PROBE_TITLE"] = title
    env["MOUSE_PROBE_ARTIFACT"] = str(artifact)
    if args.flight:
        env["MOUSE_PROBE_FLIGHT"] = "1"
    if args.screen_filter:
        env["MOUSE_PROBE_SCREEN_FILTER"] = args.screen_filter
    return subprocess.Popen(command, cwd=args.project_root, env=env, text=True)


def run(args: argparse.Namespace) -> int:
    project_root = args.project_root.resolve()
    artifact = args.artifact if args.artifact.is_absolute() else project_root / args.artifact
    artifact.parent.mkdir(parents=True, exist_ok=True)
    artifact.unlink(missing_ok=True)
    title = args.title or f"Infinity Reality Mouse Probe {os.getpid()}"
    process: subprocess.Popen[str] | None = None
    x11: X11 | None = None
    old_pointer: tuple[int, int] | None = None
    old_focus: Window | None = None
    try:
        x11 = X11()
        old_pointer = x11.save_pointer()
        old_focus = x11.save_focus()
        process = None if args.no_launch else launch_probe(args, title, artifact)
        deadline = time.monotonic() + args.timeout
        window = None
        while time.monotonic() < deadline:
            window = x11.find_exact_title(title)
            if window is not None:
                break
            time.sleep(0.1)
        if window is None:
            raise RuntimeError(f"could not find the uniquely titled probe window {title!r}")
        x11.focus(window)
        geometry = x11.geometry(window)
        x11.x11.XWarpPointer(x11.display, Window(0), window, 0, 0, 0, 0, geometry[2] // 2, geometry[3] // 2)
        x11.x11.XSync(x11.display, False)

        ready = wait_for(artifact, lambda state: bool(state.get("ready")), args.timeout, "probe ready")
        controller = str(ready.get("controller", "player"))
        yaw_key = "ship_yaw" if controller == "ship" else "camera_yaw"
        pitch_key = "ship_pitch" if controller == "ship" else "camera_pitch"
        yaw_before = float(ready.get(yaw_key, 0.0))
        pitch_before = float(ready.get(pitch_key, 0.0))
        x11.relative_motion(args.look_dx, args.look_dy)
        if args.expect_look_blocked:
            time.sleep(args.blocked_wait)
            blocked = read_state(artifact)
            if blocked is None:
                raise RuntimeError("probe state disappeared during blocked-look comparison")
            yaw_after = float(blocked.get(yaw_key, yaw_before))
            pitch_after = float(blocked.get(pitch_key, pitch_before))
            delta = abs(yaw_after - yaw_before) + abs(pitch_after - pitch_before)
            print(f"CAUSAL_STOP yaw_before={yaw_before} yaw_after={yaw_after} pitch_after={pitch_after} delta={delta}")
            if delta > 1e-6:
                raise RuntimeError("STOP filter did not block camera motion")
            print("CAUSAL_STOP_BLOCKED_OK")
            return 0
        moved = wait_for(
            artifact,
            lambda state: abs(float(state.get(yaw_key, yaw_before)) - yaw_before) > 1e-5
            or abs(float(state.get(pitch_key, pitch_before)) - pitch_before) > 1e-5,
            args.timeout,
            "camera change after native relative motion",
        )
        print(f"NATIVE_LOOK_OK controller={controller} yaw={moved[yaw_key]} pitch={moved[pitch_key]}")

        attacks_before = int(moved.get("attack_count", 0))
        x11.click()
        if controller == "ship":
            clicked = wait_for(artifact, lambda state: int(state.get("mouse_mode", -1)) == CAPTURED, args.timeout, "ship cursor capture after native left click")
            print(f"NATIVE_CLICK_OK controller=ship cursor={clicked['mouse_mode']}")
        else:
            clicked = wait_for(artifact, lambda state: int(state.get("attack_count", 0)) > attacks_before, args.timeout, "attack after native left click")
            print(f"NATIVE_CLICK_OK attacks={clicked['attack_count']}")

        x11.press_key(XK_ESCAPE)
        paused = wait_for(artifact, lambda state: int(state.get("mouse_mode", -1)) == VISIBLE, args.timeout, "visible cursor after Escape")
        print(f"NATIVE_ESCAPE_OK mode={paused.get('mode')} cursor={paused.get('mouse_mode')}")

        # Use the control rectangle published by the probe so a translated or
        # resized pause layout is still clicked at the actual Resume button.
        resume_rect = paused.get("resume_rect")
        if not isinstance(resume_rect, dict):
            raise RuntimeError(f"probe did not publish a Resume button rectangle: {resume_rect!r}")
        viewport_size = paused.get("viewport_size")
        if not isinstance(viewport_size, dict) or float(viewport_size.get("x", 0.0)) <= 0.0 or float(viewport_size.get("y", 0.0)) <= 0.0:
            raise RuntimeError(f"probe did not publish a usable logical viewport size: {viewport_size!r}")
        logical_x = float(resume_rect["x"]) + float(resume_rect["width"]) * 0.5
        logical_y = float(resume_rect["y"]) + float(resume_rect["height"]) * 0.5
        resume_x = int(logical_x / float(viewport_size["x"]) * geometry[2])
        resume_y = int(logical_y / float(viewport_size["y"]) * geometry[3])
        x11.x11.XWarpPointer(x11.display, Window(0), window, 0, 0, 0, 0, resume_x, resume_y)
        x11.x11.XSync(x11.display, False)
        x11.click()
        resumed = wait_for(artifact, lambda state: int(state.get("mouse_mode", -1)) == CAPTURED, args.timeout, "captured cursor after centered Resume click")
        print(f"NATIVE_RESUME_OK mode={resumed.get('mode')} cursor={resumed.get('mouse_mode')}")
        print("NATIVE_MOUSE_VALIDATION_OK")
        return 0
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        if x11 is not None:
            if old_focus is not None:
                x11.restore_focus(old_focus)
            if old_pointer is not None:
                x11.restore_pointer(old_pointer)
            x11.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--godot-bin", type=Path)
    parser.add_argument("--artifact", type=Path, default=Path("artifacts/mouse_probe.json"))
    parser.add_argument("--title")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--look-dx", type=int, default=120)
    parser.add_argument("--look-dy", type=int, default=-45)
    parser.add_argument("--no-launch", action="store_true", help="attach to an already running probe")
    parser.add_argument("--flight", action="store_true", help="board the probe ship and validate ship look controls")
    parser.add_argument("--screen-filter", choices=["stop", "ignore"], help="override the probe HUD pointer filter for regression checks")
    parser.add_argument("--expect-look-blocked", action="store_true", help="assert that the injected motion leaves camera state unchanged")
    parser.add_argument("--blocked-wait", type=float, default=0.7, help="seconds to wait for a blocked-look regression sample")
    args = parser.parse_args()
    try:
        return run(args)
    except (OSError, RuntimeError) as error:
        print(f"NATIVE_MOUSE_VALIDATION_FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
