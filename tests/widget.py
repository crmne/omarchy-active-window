#!/usr/bin/python3
"""Run the real widget in an offscreen Quickshell with a synthetic window.

Needs the installed Omarchy shell (OMARCHY_PATH, /usr/share/omarchy by default)
and Quickshell. The widget's Hyprland and Wayland toplevel sources are replaced
with a synthetic window (PID 0, so no process is started), settings writes go
to a recording host instead of shell.json, and an empty runtime directory keeps
Hyprland and running Quickshell instances out of the test.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SHELL = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
# A failed check, or a QML error or binding warning anywhere in the widget.
FAILURE = re.compile(r"WIDGET_TEST_FAIL|TypeError|ReferenceError|Error loading|is not a function|Unable to assign")


def stage_widget(source, target):
    text = source.read_text()
    for old, new in [
        ("readonly property var waylandToplevel: ToplevelManager.activeToplevel", "property var waylandToplevel: null"),
        ("readonly property var hyprlandToplevel: Hyprland.activeToplevel", "property var hyprlandToplevel: null"),
        # The desktop entry's icon, set by the test instead of the installed apps.
        ('readonly property string iconName: desktopEntry ? String(desktopEntry.icon || "") : ""',
         'property string iconName: ""'),
    ]:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    target.write_text(text)


def main():
    if not (SHELL / "Ui").is_dir():
        sys.exit(f"Omarchy shell not found at {SHELL}")
    with tempfile.TemporaryDirectory(prefix="active-window-test-") as work:
        stage = Path(work) / "shell"
        stage.mkdir()
        for name in ["Commons", "Ui"]:
            (stage / name).symlink_to(SHELL / name)
        stage_widget(ROOT / "BarWidget.qml", stage / "BarWidget.qml")
        for script in ROOT.glob("*.js"):
            shutil.copy(script, stage)
        shutil.copy(ROOT / "tests/widget.qml", stage / "shell.qml")
        # Quickshell's socket path must stay short, so this lives under the
        # user's runtime directory rather than the temporary one.
        runtime = tempfile.mkdtemp(prefix="aw-test-", dir=os.environ.get("XDG_RUNTIME_DIR"))
        # Icon paths a desktop entry could name: a FIFO, which blocks whoever
        # opens it, and a regular image file.
        fifo = Path(work) / "icon-fifo.png"
        os.mkfifo(fifo)
        image = Path(work) / "icon.png"
        image.write_bytes(bytes.fromhex(
            "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
            "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082"))
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=runtime,
                   WIDGET_TEST_FIFO_ICON=str(fifo), WIDGET_TEST_FILE_ICON=str(image))
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        try:
            result = subprocess.run(["quickshell", "-p", str(stage), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=60)
        finally:
            shutil.rmtree(runtime, ignore_errors=True)
        output = result.stdout + result.stderr
        if result.returncode != 0 or "WIDGET_TEST_PASS" not in output or FAILURE.search(output):
            print(output, file=sys.stderr)
            sys.exit("Widget test failed")
        print("Widget test passed")


if __name__ == "__main__":
    main()
