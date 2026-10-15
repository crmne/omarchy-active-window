#!/usr/bin/python3
"""Capture the production widget with synthetic window data for preview.png.

Run through an exclusive GPU lock (the maintainer uses gpu-lock). Requires the
installed Omarchy shell, Quickshell and an OpenGL-capable GPU. Everything runs
on Qt's offscreen platform with its own HOME and runtime directory, so no
window appears and no Hyprland session is read or changed.

Only screenshot-host copies are adapted: the widget's Hyprland and Wayland
toplevel sources are replaced with a synthetic window (PID 0, so the
executable lookup Process never starts), the workspaces widget gets synthetic
workspaces, and PopupCard's popup-window plumbing becomes an offscreen window.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent
OMARCHY = Path("/usr/share/omarchy")
SHELL = OMARCHY / "shell"
WALLPAPER = OMARCHY / "themes/ristretto/backgrounds/0-launch.png"

# Invented titles. The desktop entries (and so the icons) are installed apps.
FIXTURES = {
    "titled": {
        "title": "garden-plan.md - Typora",
        "class": "typora",
        "settings": {"iconSaturation": 100, "iconSize": 16, "maxWidth": 280, "showTitle": True},
    },
    "iconOnly": {
        "title": "Projects",
        "class": "org.gnome.Nautilus",
        "settings": {"iconSaturation": 0, "iconSize": 18, "maxWidth": 280, "showTitle": False},
    },
    "workspaces": {"focused": 3, "occupied": [1, 2, 3, 5]},
}


def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)


def drop_block(text, start_pattern):
    match = re.search(start_pattern, text, re.M)
    if not match: raise SystemExit("pattern not found: " + start_pattern)
    depth = 0
    for index in range(text.index("{", match.start()), len(text)):
        if text[index] == "{": depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0: return text[:match.start()] + text[text.index("\n", index) + 1:]
    raise SystemExit("unbalanced block")


def offscreen_popup(path):
    """PopupCard is a PopupWindow anchored to the bar; offscreen Qt has no
    parent surface for it. Keep the card (BorderSurface, colors, border,
    padding, radius) verbatim and only swap the window plumbing."""
    text = path.read_text()
    text = replace_once(text, "PopupWindow {\n  id: root\n", "FloatingWindow {\n  id: root\n  property alias captureCard: card\n")
    text = drop_block(text, r"^  HyprlandFocusGrab \{")
    text = drop_block(text, r"^  anchor \{")
    path.write_text(text)


def capture_widget(path):
    text = path.read_text()
    text = replace_once(text, "readonly property var waylandToplevel: ToplevelManager.activeToplevel",
                        "property var waylandToplevel: null")
    text = replace_once(text, "readonly property var hyprlandToplevel: Hyprland.activeToplevel",
                        "property var hyprlandToplevel: null")
    path.write_text(text)


def capture_workspaces(path):
    text = path.read_text()
    text = replace_once(text, 'moduleName: "omarchy.workspaces"\n',
                        'moduleName: "omarchy.workspaces"\n  property var captureWorkspaces: []\n  property var captureFocused: null\n')
    assert text.count("Hyprland.workspaces.values") == 2
    text = text.replace("Hyprland.workspaces.values", "root.captureWorkspaces")
    text = text.replace("Hyprland.focusedWorkspace", "root.captureFocused")
    path.write_text(text)


def wait_for(predicate, description, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate(): return
        time.sleep(.1)
    raise RuntimeError("Timed out: " + description)


def complete_png(path):
    if not path.exists() or path.stat().st_size < 12: return False
    with path.open("rb") as image:
        image.seek(-12, 2)
        return image.read() == b"\x00\x00\x00\x00IEND\xaeB`\x82"


def main():
    output = Path(os.environ.get("CAPTURE_OUTPUT", ROOT / "screenshots"))
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="active-window-capture-", dir=os.environ.get("CAPTURE_TMP")) as work_path:
        work = Path(work_path)
        home, shell, plugin = (work / name for name in ["home", "shell", "plugin"])
        # Quickshell's IPC socket path must stay short, so the runtime dir
        # lives under the user's own runtime directory.
        runtime = Path(tempfile.mkdtemp(prefix="aw-", dir=os.environ.get("XDG_RUNTIME_DIR")))
        theme = home / ".local/state/omarchy/current/next-theme"
        theme.mkdir(parents=True)
        shutil.copy(OMARCHY / "themes/ristretto/colors.toml", theme / "colors.toml")
        env = dict(HOME=str(home), PATH="/usr/bin:/bin", LANG="C.UTF-8",
                   XDG_RUNTIME_DIR=str(runtime), OMARCHY_PATH=str(OMARCHY),
                   DISPLAY=os.environ.get("DISPLAY", ":0"))
        # Offscreen OpenGL needs a display connection for its context; no window is mapped.
        if "XAUTHORITY" in os.environ: env["XAUTHORITY"] = os.environ["XAUTHORITY"]
        subprocess.run(["omarchy-theme-set-templates"], env=env, check=True, stdout=subprocess.DEVNULL)
        shutil.copytree(theme, theme.with_name("theme"))
        fonts = home / ".config/fontconfig"
        fonts.mkdir(parents=True)
        (fonts / "fonts.conf").write_text('''<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig>
<match target="pattern"><test name="family"><string>monospace</string></test>
<edit name="family" mode="assign" binding="strong"><string>JetBrainsMono Nerd Font</string></edit></match>
</fontconfig>''')
        shell.mkdir()
        for name in ["Commons", "Ui"]: shutil.copytree(SHELL / name, shell / name)
        offscreen_popup(shell / "Ui/PopupCard.qml")
        # The real shell resolves app icons through its AppLibrary service.
        for name in ["AppLibrary.qml", "AppSearch.js"]: shutil.copy(SHELL / "services" / name, shell / name)
        shutil.copy(SHELL / "plugins/bar/widgets/Workspaces.qml", shell / "Workspaces.qml")
        capture_workspaces(shell / "Workspaces.qml")
        plugin.mkdir()
        for name in ["BarWidget.qml", "AppIconModel.js"]: shutil.copy(ROOT / name, plugin / name)
        capture_widget(plugin / "BarWidget.qml")
        shutil.copy(TOOLS / "shell.qml", shell / "shell.qml")
        (work / "fixtures.json").write_text(json.dumps(FIXTURES))
        (work / "screen.json").write_text(json.dumps({"screens": [dict(
            name="CAPTURE", x=0, y=0, width=6400, height=4000, logicalDpi=96, logicalBaseDpi=96, dpr=1)]}))
        env.update(QT_QPA_PLATFORM=f"offscreen:configfile={work / 'screen.json'}",
                   QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", QSG_INFO="1", QT_SCALE_FACTOR="4",
                   CAPTURE_PLUGIN=str(plugin), CAPTURE_FIXTURES=str(work / "fixtures.json"),
                   CAPTURE_OUTPUT=str(output), CAPTURE_WALLPAPER=str(WALLPAPER))

        def call(method, *args):
            result = subprocess.run(["qs", "ipc", "-p", str(shell), "call", "--", "capture", method, *map(str, args)],
                                    env=env, capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                if method != "ready": print(result.stderr, file=sys.stderr, flush=True)
                return ""
            return result.stdout.strip()

        def grab(method, filename, *args):
            path = output / filename
            path.unlink(missing_ok=True)
            result = call(method, path, *args)
            if result != "ok": raise RuntimeError(f"{filename}: {result}")
            wait_for(lambda: complete_png(path), filename)
            print(path, file=sys.stderr, flush=True)
            return path

        log = work / "qs.log"
        with log.open("w") as stream:
            proc = subprocess.Popen(["qs", "-p", str(shell)], env=env, stdout=stream, stderr=subprocess.STDOUT)
            try:
                wait_for(lambda: call("ready") == "true", "capture host")
                for name, popup in [("iconOnly", False), ("titled", True)]:
                    state = json.loads(call("show", name, "true" if popup else "false"))
                    assert state["entry"] and state["icon"] and state["pidLookup"] == 0, state
                    time.sleep(.8)
                    grab("grabBar", f"bar-{name}.png")
                    if popup: grab("grabPopup", "settings.png")
                call("preparePreview")
                time.sleep(.8)
                preview = grab("grabPreview", "preview.png")
                shutil.copy(preview, ROOT / "preview.png")
            finally:
                proc.terminate()
                proc.wait(timeout=5)
                shutil.rmtree(runtime, ignore_errors=True)
                log_text = log.read_text()
                (output / "capture.log").write_text(log_text)
                for line in log_text.splitlines():
                    if "OpenGL VENDOR" in line or "WARN" in line or "ERROR" in line: print(line, file=sys.stderr)
        if "NVIDIA" not in log_text or "llvmpipe" in log_text or "Software" in log_text:
            raise RuntimeError("Capture must use NVIDIA GPU rendering; inspect capture.log")


if __name__ == "__main__": main()
