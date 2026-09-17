from __future__ import annotations

import asyncio
import importlib.util
import json
import struct
import sys
import threading
import time
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "plasma-plugin" / "contents" / "pyext.py"
spec = importlib.util.spec_from_file_location("dcent_pyext", MODULE_PATH)
pyext = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(pyext)


def test_live_settings_script_preserves_selection_and_output_scope():
    import subprocess
    desktops = [
        {"screen": 0, "wallpaperPlugin": "org.dcentwallpapers.plasma", "config": {"WallpaperWorkShopId": "42", "WallpaperPath": "/scene", "WallpaperSource": "/scene/scene.json+scene", "Fps": 30}},
        {"screen": 1, "wallpaperPlugin": "org.dcentwallpapers.plasma", "config": {"WallpaperWorkShopId": "99", "WallpaperPath": "/other", "Fps": 30}},
        {"screen": 2, "wallpaperPlugin": "org.dcentwallpapers.plasma", "config": {"WallpaperWorkShopId": "42", "WallpaperPath": "/scene", "Fps": 30}},
    ]
    for d in (desktops[0], desktops[2]):
        d["config"].update({"WallpaperSource": "/scene/scene.json+scene", "MediaPath": "/scene/scene.json", "WallpaperType": "scene"})
    for targets, expected in [([0], [60, 30, 30]), ([0, 1, 2], [60, 30, 60]), ([1], [30, 30, 30])]:
        script = pyext.build_live_settings_script({**desktops[0]["config"], "Fps": 60, "MultiScreenMode": "span"}, "42", "/scene", targets)
        harness = 'const ds = ' + json.dumps(desktops) + ''';
        ds.forEach(d => { d.readConfig = k => d.config[k]; d.writeConfig = (k,v) => d.config[k]=v; d.reloadConfig = () => {}; });
        function desktops() { return ds; }
        function print(v) {}
        ''' + script + '\nconsole.log(JSON.stringify(ds));'
        result = subprocess.run(["node", "-e", harness], capture_output=True, text=True, check=True)
        updated = json.loads(result.stdout)
        assert [d["config"]["Fps"] for d in updated] == expected
        assert updated[0]["config"]["WallpaperSource"] == "/scene/scene.json+scene"
        assert all("MultiScreenMode" not in d["config"] for d in updated)


def test_live_settings_reject_mixed_source_identity():
    import subprocess
    config = {"WallpaperWorkShopId": "42", "WallpaperPath": "/scene", "WallpaperSource": "/other/scene.json+scene", "MediaPath": "/other/scene.json", "WallpaperType": "scene", "Fps": 30}
    script = pyext.build_live_settings_script({**config, "Fps": 60}, "42", "/scene", [0])
    harness = 'const config = ' + json.dumps(config) + ''';
    const d = {screen: 0, wallpaperPlugin: "org.dcentwallpapers.plasma", readConfig: k => config[k], writeConfig: (k,v) => config[k]=v, reloadConfig: () => {}};
    function desktops() { return [d]; }
    ''' + script + '\nconsole.log(JSON.stringify(config));'
    result = subprocess.run(["node", "-e", harness], capture_output=True, text=True, check=True)
    assert json.loads(result.stdout)["Fps"] == 30


def test_live_settings_accept_resolved_preset_dependency(tmp_path):
    preset = tmp_path / "42"
    base = tmp_path / "99"
    preset.mkdir(); base.mkdir()
    (preset / "project.json").write_text(json.dumps({"dependency": "99", "preset": {"clock": True}}))
    (base / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json"}))
    (base / "scene.json").write_text("{}")
    media = str(base / "scene.json")
    script = pyext.build_live_settings_script({"WallpaperSource": media + "+scene", "MediaPath": media, "WallpaperType": "scene", "Fps": 60}, "42", str(preset), [0])
    assert 'desktop.writeConfig("Fps", 60)' in script


def test_live_settings_rpc_resolves_named_and_all_screen_targets(monkeypatch):
    captured = []
    monkeypatch.setattr(pyext, "list_screens", lambda: [
        {"index": 0, "name": "DP-1"}, {"index": 1, "name": "HDMI-A-1"},
    ])

    def fake_run(command, **kwargs):
        captured.append(command[-1])
        count = 2 if "var targets = [0, 1]" in command[-1] else 1
        return pyext.subprocess.CompletedProcess(command, 0, f"DCENT_LIVE_UPDATED={count}\n", "")

    monkeypatch.setattr(pyext.subprocess, "run", fake_run)
    config = {
        "WallpaperSource": "/scene/scene.json+scene", "MediaPath": "/scene/scene.json",
        "WallpaperType": "scene", "Fps": 60,
    }
    assert pyext.update_active_settings(config, "42", "/scene", "DP-1", False)["ok"]
    assert "var targets = [0]" in captured[-1]
    assert pyext.update_active_settings(config, "42", "/scene", "DP-1", True)["ok"]
    assert "var targets = [0, 1]" in captured[-1]


def test_qml_rpc_signatures_preserve_live_scope_and_scene_duration():
    source = (MODULE_PATH.parent / "ui/Pyext.qml").read_text()
    assert "function update_active_settings(configuration, workshopId, wallpaperFolder, screenTarget, allScreens)" in source
    assert "screenTarget || \"\", Boolean(allScreens)" in source
    assert "function render_scene_video_fallback(wallpaper, assets, mode, scaling, fps, duration," in source
    assert "fps, duration || 45, properties || {}" in source
    assert 'send("preflight_scene", [source, assets], 120000)' in source


def test_preflight_is_network_isolated_limited_and_hashes_full_source(tmp_path, monkeypatch):
    tools = tmp_path / "tools"
    tools.mkdir()
    helper = tools / "dcent-scene-preflight"
    helper.write_text("#!/bin/sh\nexit 0\n")
    helper.chmod(0o755)
    scene = tmp_path / "scene.json"
    scene.write_bytes(b"a" * 300_000)
    assets = tmp_path / "assets"
    assets.mkdir()
    calls = []

    monkeypatch.setattr(pyext, "__file__", str(tmp_path / "pyext.py"))
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: tmp_path))
    monkeypatch.setattr(pyext.shutil, "which", lambda name: "/usr/bin/" + name)

    def fake_run(command, **kwargs):
        calls.append(command)
        return pyext.subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(pyext.subprocess, "run", fake_run)
    assert pyext._preflight_scene(str(scene), str(assets))["safe"]
    command = calls[-1]
    assert "/usr/bin/prlimit" in command
    assert "/usr/bin/bwrap" in command
    assert "--unshare-net" in command
    assert "--unshare-pid" in command
    assert "--as=17179869184" in command
    assert "PULSE_SERVER" in command
    assert "PIPEWIRE_REMOTE" in command

    scene.write_bytes(b"a" * 299_999 + b"b")
    assert pyext._preflight_scene(str(scene), str(assets))["safe"]
    assert len(calls) == 2, "A change beyond the old prefix must invalidate safety cache"

    def fake_gpu_loss(command, **kwargs):
        calls.append(command)
        return pyext.subprocess.CompletedProcess(command, 0, "", 'ERROR VkResult is "VK_ERROR_DEVICE_LOST"')

    monkeypatch.setattr(pyext.subprocess, "run", fake_gpu_loss)
    scene.write_bytes(b"c" + b"a" * 299_999)
    result = pyext._preflight_scene(str(scene), str(assets))
    assert not result["safe"]
    assert "fatal GPU" in result["status"]


def test_background_rpc_does_not_block_fast_requests():
    rpc = pyext.Jsonrpc()
    started = threading.Event()
    release = threading.Event()

    @rpc.add_method
    def render_scene_video_fallback():
        started.set()
        release.wait(timeout=2)
        return "rendered"

    @rpc.add_method
    def get_wallpaper_project():
        return "metadata"

    async def exercise():
        slow = asyncio.create_task(rpc.handle_async(json.dumps({"id": 1, "method": "render_scene_video_fallback"})))
        assert await asyncio.to_thread(started.wait, 1)
        fast_response = await asyncio.wait_for(
            rpc.handle_async(json.dumps({"id": 2, "method": "get_wallpaper_project"})),
            timeout=0.25,
        )
        release.set()
        slow_response = await asyncio.wait_for(slow, timeout=1)
        return json.loads(fast_response), json.loads(slow_response)

    fast, slow = asyncio.run(exercise())
    assert fast == {"id": 2, "result": "metadata"}
    assert slow == {"id": 1, "result": "rendered"}


def test_scene_render_coordinator_cancels_stale_processes():
    class FakeProcess:
        def __init__(self):
            self.returncode = None
            self.terminate_count = 0

        def poll(self):
            return self.returncode

        def terminate(self):
            self.terminate_count += 1
            self.returncode = -15

    coordinator = pyext.SceneRenderCoordinator()
    stale = coordinator.begin()
    stale_process = FakeProcess()
    stale.track(stale_process)

    current = coordinator.begin()

    assert stale.cancelled is True
    assert stale_process.terminate_count == 1
    assert current.cancelled is False
    assert coordinator.cancel() is True
    assert current.cancelled is True
    coordinator.finish(stale)
    assert coordinator.active is current
    coordinator.finish(current)
    assert coordinator.active is None


def test_cancel_scene_render_rpc_cancels_the_active_job():
    job = pyext.SCENE_RENDERS.begin()
    try:
        result = pyext.cancel_scene_render()
        assert result == {"ok": True, "cancelled": True}
        assert job.cancelled is True
    finally:
        pyext.SCENE_RENDERS.finish(job)


def test_targeted_scene_cancellation_is_race_safe():
    coordinator = pyext.SceneRenderCoordinator()

    assert coordinator.cancel("queued") is True
    queued = coordinator.begin("queued")
    assert queued.cancelled is True

    current = coordinator.begin("current")
    assert current.cancelled is False
    coordinator.finish("queued", queued)
    assert coordinator.active is current

    assert coordinator.cancel("old") is True
    assert current.cancelled is False
    assert coordinator.cancel("current") is True
    assert current.cancelled is True
    coordinator.finish("current", current)
    assert coordinator.active is None


def test_cancellable_process_reaps_the_tracked_child():
    job = pyext.SceneRenderJob("capture-test")
    outcome = []

    def run_child():
        try:
            pyext.run_cancellable_process(
                job,
                [sys.executable, "-c", "import time; time.sleep(30)"],
                timeout=60,
                capture_output=True,
                text=True,
            )
        except BaseException as error:
            outcome.append(error)

    worker = threading.Thread(target=run_child)
    started = time.monotonic()
    worker.start()
    while job.process_count == 0 and time.monotonic() - started < 2:
        time.sleep(0.01)

    assert job.process_count == 1
    job.cancel()
    worker.join(timeout=2)

    assert worker.is_alive() is False
    assert len(outcome) == 1
    assert isinstance(outcome[0], pyext.SceneRenderCancelled)
    assert job.process_count == 0


def test_parse_output_bounds_handles_negative_geometry_and_scaling():
    output = """
Output: 1 DP-2 uuid
\x1b[01;33m    Geometry: \x1b[0;0m-2560,0 2560x1440
    Scale: 1.5
Output: 2 DP-1 uuid
\x1b[01;33m    Geometry: \x1b[0;0m0,0 2560x1440
    Scale: 1
"""
    assert pyext.parse_output_bounds(output) == {
        "VirtualDesktopX": -2560,
        "VirtualDesktopY": 0,
        "VirtualDesktopWidth": 5120,
        "VirtualDesktopHeight": 1440,
    }
    assert pyext.parse_outputs(output) == [
        {"index": 0, "name": "DP-2", "x": -2560, "y": 0, "width": 2560, "height": 1440, "scale": 1.5},
        {"index": 1, "name": "DP-1", "x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1.0},
    ]
    outputs = pyext.parse_outputs(output)
    assert pyext.choose_scene_fallback_resolution(outputs, "mirror") == (3840, 2160)
    assert pyext.choose_scene_fallback_resolution(outputs, "span") == (7680, 2160)
    assert pyext.bound_video_decoder_resolution(7680, 2160) == (4096, 1152)
    assert pyext.choose_scene_fallback_resolution(outputs, "mirror", 60) == (2560, 1440)
    high_width, high_height = pyext.choose_scene_fallback_resolution(outputs, "mirror", 240)
    assert high_width * high_height * 240 <= 250_000_000
    assert high_width < 2560 and high_height < 1440


def test_scene_video_fallback_caps_capture_rate_to_preserve_resolution():
    assert pyext.effective_scene_video_fps(240) == 30
    assert pyext.effective_scene_video_fps(30) == 30


def test_scene_fallback_command_uses_explicit_high_resolution_window(tmp_path):
    renderer = tmp_path / "linux-wallpaperengine"
    wallpaper = tmp_path / "431960" / "2904412422"
    assets = tmp_path / "wallpaper_engine" / "assets"
    screenshot = tmp_path / "fallback.png"
    command = pyext.build_scene_fallback_command(
        renderer, wallpaper, assets, screenshot, 3840, 2160, "fill"
    )
    assert command[0] == str(renderer)
    assert command[command.index("--window") + 1] == "16384x0x3840x2160"
    assert command[command.index("--screenshot") + 1] == str(screenshot)
    assert command[command.index("--assets-dir") + 1] == str(assets)
    assert command[command.index("--scaling") + 1] == "fill"
    assert command[-1] == str(wallpaper)


def test_scene_video_renderer_command_is_windowed_and_noninteractive(tmp_path):
    renderer = tmp_path / "linux-wallpaperengine"
    wallpaper = tmp_path / "431960" / "2904412422"
    assets = tmp_path / "wallpaper_engine" / "assets"

    command = pyext.build_scene_video_renderer_command(
        renderer, wallpaper, assets, 3840, 2160, "fill", fps=240
    )

    assert command[0] == str(renderer)
    assert command[command.index("--window") + 1] == "16384x0x3840x2160"
    assert command[command.index("--assets-dir") + 1] == str(assets)
    assert command[command.index("--scaling") + 1] == "fill"
    assert command[command.index("--fps") + 1] == "240"
    assert "--disable-mouse" in command
    assert "--no-fullscreen-pause" in command
    assert "--screenshot" not in command
    assert command[-1] == str(wallpaper)


def test_scene_video_renderer_commands_use_verified_external_renderer_only(tmp_path):
    renderer = tmp_path / "linux-wallpaperengine"
    wallpaper = tmp_path / "431960" / "3012694124"
    assets = tmp_path / "wallpaper_engine" / "assets"

    commands = pyext.build_scene_video_renderer_commands(
        renderer, wallpaper, assets, 1920, 1080, "fill", 60,
        {"audiobar": False}, False, False,
    )

    assert len(commands) == 1
    assert commands[0][0] == str(renderer)
    assert "--host" not in commands[0]


def test_scene_video_smoothing_command_produces_exact_cfr(tmp_path):
    ffmpeg = tmp_path / "ffmpeg"
    captured = tmp_path / "captured.mp4"
    destination = tmp_path / "smoothed.mp4"

    command = pyext.build_scene_video_smoothing_command(
        ffmpeg, captured, destination, 60, "h264_nvenc", 12
    )

    assert command[0] == str(ffmpeg)
    assert command[command.index("-i") + 1] == str(captured)
    filter_graph = command[command.index("-filter_complex") + 1]
    assert "minterpolate=fps=60:mi_mode=blend" in filter_graph
    assert "xfade=transition=fade:duration=3" in filter_graph
    assert command[command.index("-fps_mode") + 1] == "cfr"
    assert command[command.index("-c:v") + 1] == "h264_nvenc"
    assert command[-1] == str(destination)


def test_scene_capture_duration_keeps_long_loop_requests():
    assert pyext.normalize_scene_capture_duration(45) == 45
    assert pyext.normalize_scene_capture_duration(999) == 180
    assert pyext.normalize_scene_capture_duration("invalid") == 45
    assert pyext.scene_loop_overlap(12) == 3
    assert pyext.scene_loop_overlap(45) == 3


def test_scene_fallback_cache_tracks_the_private_renderer_library():
    source = MODULE_PATH.read_text(encoding="utf-8")
    # v7 invalidates captures produced before a user-local renderer-library
    # repair. The executable timestamp alone misses shared-library fixes.
    assert '"animated-v7"' in source
    assert '"animated-v6"' not in source
    assert 'liblinux-wallpaperengine-lib.so' in source
    # Unpacked scenes are identified by their own files: no package file exists.
    assert "_scene_identity_stamp" in source


def test_video_frame_count_rejects_stuttery_high_fps_cache():
    assert pyext.video_frame_count_is_smooth(717, 11.95, 60) is True
    assert pyext.video_frame_count_is_smooth(495, 11.98, 60) is False
    assert pyext.video_frame_count_is_smooth(354, 12.0, 30) is True


def test_scene_video_capture_command_records_only_the_renderer_window(tmp_path):
    ffmpeg = tmp_path / "ffmpeg"
    destination = tmp_path / "fallback.mp4"

    command = pyext.build_scene_video_capture_command(
        ffmpeg, ":0", 71303175, destination, 3840, 2160, 30, 24, "h264_nvenc"
    )

    assert command[0] == str(ffmpeg)
    assert command[command.index("-window_id") + 1] == "71303175"
    assert command[command.index("-video_size") + 1] == "3840x2160"
    assert command[command.index("-framerate") + 1] == "30"
    assert command[command.index("-i") + 1] == ":0"
    assert command[command.index("-t") + 1] == "24"
    assert command[command.index("-c:v") + 1] == "h264_nvenc"
    assert "-an" in command
    assert command[-1] == str(destination)


def test_scene_video_fallback_rejects_non_scene_project(tmp_path):
    wallpaper = tmp_path / "wallpaper"
    assets = tmp_path / "assets"
    wallpaper.mkdir()
    assets.mkdir()
    (wallpaper / "project.json").write_text('{"type": "video"}')
    (wallpaper / "scene.pkg").write_bytes(b"packed")

    result = pyext.render_scene_video_fallback(str(wallpaper), str(assets))

    assert result["ok"] is False
    assert result["status"] == "animated fallback requires a packed scene"


def test_cache_only_scene_apply_never_starts_external_renderer(tmp_path, monkeypatch):
    home = tmp_path / "home"
    renderer = home / ".local" / "bin" / "linux-wallpaperengine"
    renderer.parent.mkdir(parents=True)
    renderer.write_text("#!/bin/sh\nexit 99\n", encoding="utf-8")
    renderer.chmod(0o755)
    wallpaper = tmp_path / "431960" / "1234567890"
    wallpaper.mkdir(parents=True)
    (wallpaper / "project.json").write_text(
        json.dumps({"title": "Scene", "type": "scene", "file": "scene.json"}),
        encoding="utf-8",
    )
    (wallpaper / "scene.pkg").write_bytes(b"packed")
    assets = tmp_path / "assets"
    assets.mkdir()
    monkeypatch.setattr(pyext.Path, "home", classmethod(lambda cls: home))
    monkeypatch.setattr(pyext, "_list_screens_for_render", lambda job: [])
    monkeypatch.setattr(
        pyext.subprocess,
        "Popen",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("renderer started")),
    )

    still = pyext._render_scene_fallback(str(wallpaper), str(assets), cache_only=True)
    video = pyext._render_scene_video_fallback(str(wallpaper), str(assets), cache_only=True)

    assert still == {"ok": False, "cacheMiss": True, "status": "no cached scene still is ready"}
    assert video == {"ok": False, "cacheMiss": True, "status": "no cached animated scene is ready"}


def test_run_plasma_script_retries_transient_dbus_failures(monkeypatch):
    calls = []

    class Result:
        def __init__(self, returncode, stdout="", stderr=""):
            self.returncode = returncode
            self.stdout = stdout
            self.stderr = stderr

    def fake_run(command, **kwargs):
        calls.append(command)
        if len(calls) == 1:
            return Result(1, "", "org.freedesktop.DBus.Error.NoReply")
        return Result(0, "\\n", "")

    monkeypatch.setattr(pyext.subprocess, "run", fake_run)
    result = pyext.run_plasma_script("var items = desktops();", attempts=2)
    assert result.returncode == 0
    assert len(calls) == 2


def test_apply_plasma_script_retries_until_readback_matches(monkeypatch):
    calls = []

    class Result:
        returncode = 0
        stdout = "\n"
        stderr = ""

    monkeypatch.setattr(pyext, "run_plasma_script", lambda script: calls.append(script) or Result())
    reads = iter([(False, {}), (True, {"wallpaperPlugin": "org.dcentwallpapers.plasma"})])
    monkeypatch.setattr(pyext, "wait_for_wallpaper_readback", lambda *args, **kwargs: next(reads))
    ok, result, readback = pyext.apply_plasma_script("var x = 1;", [0], {}, attempts=2)
    assert ok is True
    assert result.returncode == 0
    assert readback["wallpaperPlugin"] == "org.dcentwallpapers.plasma"
    assert len(calls) == 2


def test_apply_script_targets_one_selected_desktop_only():
    script = pyext.build_apply_screen_script(
        {
            "WallpaperSource": "/tmp/right.jpg+image",
            "WallpaperType": "image",
            "MultiScreenMode": "single",
            "UntrustedKey": "must-not-be-written",
        },
        1,
    )
    assert "if (desktop.screen !== 1) continue;" in script
    assert 'if (desktop.wallpaperPlugin !== "org.dcentwallpapers.plasma") continue;' in script
    assert 'desktop.writeConfig("VirtualDesktopWidth", 0);' in script
    assert 'desktop.writeConfig("WallpaperSource", "/tmp/right.jpg+image")' in script
    assert 'desktop.writeConfig("MultiScreenMode", "single")' in script
    assert script.count("desktop.reloadConfig();") == 2
    assert script.index('desktop.writeConfig("WallpaperSource", "/tmp/right.jpg+image")') < script.rindex("desktop.reloadConfig();")
    assert "UntrustedKey" not in script


def test_screen_target_accepts_kde_output_name_or_numeric_index():
    screens = [
        {"index": 0, "name": "DP-2"},
        {"index": 1, "name": "DP-1"},
    ]

    assert pyext.resolve_screen_target(screens, "DP-1") == screens[1]
    assert pyext.resolve_screen_target(screens, "0") == screens[0]
    assert pyext.resolve_screen_target(screens, 1) == screens[1]
    assert pyext.resolve_screen_target(screens, "missing") is None


def test_apply_script_targets_every_desktop_and_filters_keys():
    script = pyext.build_apply_all_script(
        {
            "WallpaperSource": "/tmp/a.jpg+image",
            "WallpaperType": "image",
            "MultiScreenMode": "span",
            "PropertyOverrides": '{"enabled":false}',
            "DisableParallax": True,
            "UntrustedKey": "must-not-be-written",
        }
    )
    assert "var items = desktops()" in script
    assert 'desktop.wallpaperPlugin = "org.dcentwallpapers.plasma"' in script
    assert 'desktop.writeConfig("WallpaperSource", "/tmp/a.jpg+image")' in script
    assert 'desktop.writeConfig("MultiScreenMode", "span")' in script
    assert 'desktop.writeConfig("PropertyOverrides", "{\\"enabled\\":false}")' in script
    assert 'desktop.writeConfig("DisableParallax", true)' in script
    assert script.count("desktop.reloadConfig();") == 1
    assert script.rindex('desktop.writeConfig("WallpaperSource", "/tmp/a.jpg+image")') < script.index("desktop.reloadConfig();")
    assert "UntrustedKey" not in script


def test_wallpaper_readback_requires_the_exact_staged_source_and_id():
    parsed = pyext.parse_wallpaper_readback("""wallpaperPlugin: org.dcentwallpapers.plasma
WallpaperSource: /tmp/right.jpg+image
WallpaperType: image
WallpaperWorkShopId: 1234
MediaPath: /tmp/right.jpg
""")
    assert pyext.wallpaper_readback_matches(parsed, {
        "WallpaperSource": "/tmp/right.jpg+image",
        "WallpaperType": "image",
        "WallpaperWorkShopId": "1234",
        "MediaPath": "/tmp/right.jpg",
    }) is True
    assert pyext.wallpaper_readback_matches(parsed, {
        "WallpaperSource": "/tmp/other.jpg+image",
        "WallpaperWorkShopId": "9999",
    }) is False


def test_login_commands_use_fixed_programs_and_switch_provider_last(tmp_path):
    prepared = tmp_path / "login-preview.jpg"
    destination = Path("/var/lib/plasmalogin/wallpapers/dcent-login-test.jpg")
    commands = pyext.build_login_wallpaper_commands(prepared, destination)

    assert len(commands) == 4
    assert all(command[0] == "/usr/bin/pkexec" for command in commands)
    assert all("sh" not in command[1] for command in commands)
    assert commands[1][-2:] == [str(prepared), str(destination)]
    assert commands[2][-1] == f"file://{destination}"
    assert commands[3][-1] == "org.kde.image"
    assert commands[3][-3:-1] == ["--key", "WallpaperPlugin"]


def test_known_black_scene_uses_high_resolution_external_fallback():
    source = Path("/data/SteamLibrary/steamapps/workshop/content/431960/2929592935/scene.json")

    assert pyext.scene_compatibility_fallback(source) == "external"
    assert pyext.scene_compatibility_fallback(source.parent.parent / "9999999999" / "scene.json") == ""
    assert pyext.effective_scene_scaling("2929592935", "fit") == "stretch"
    assert pyext.effective_scene_scaling("9999999999", "fit") == "fit"


def test_runtime_scene_loader_rechecks_isolated_captsilver_preflight_and_only_queries_cache():
    root = Path(__file__).resolve().parents[1]
    main = (root / "plasma-plugin/contents/ui/main.qml").read_text()
    helper = (root / "tools/scene_preflight.cpp").read_text()

    assert "pyext.preflight_scene(requestedSource, assetsPath)" in main
    assert "function loadSceneAfterPreflight(generation)" in main
    assert "loadSceneAnimatedFallback(generation, true)" in main
    assert "Boolean(cacheOnly)" in main
    assert "background.fps,\n            24,\n            background.projectPropertyOverrides" in main
    assert "import com.github.captsilver.wallpaperEngineKde 1.2" in helper


def test_scene_preflight_helper_is_a_bounded_validator_only():
    root = Path(__file__).resolve().parents[1]
    helper = (root / "tools/scene_preflight.cpp").read_text()

    assert 'QString::fromLatin1(argv[1]) == "--host"' not in helper
    assert "--host" not in helper
    assert "20000" in helper
    assert "onTriggered: Qt.quit()" in helper


def test_scene_preflight_helper_never_runs_native_teardown():
    root = Path(__file__).resolve().parents[1]
    helper = (root / "tools/scene_preflight.cpp").read_text()

    # A probe owns renderer/audio workers from the untrusted scene; both on
    # timeout and after a first frame, destroying them natively segfaults
    # (reproduced with a Workshop scene that renders a frame and then crashes
    # in teardown). Exit the process instead: the probe is disposable.
    assert "DCENT_PREFLIGHT_NO_FRAME" in helper
    assert "DCENT_PREFLIGHT_FIRST_FRAME" in helper
    assert "std::_Exit(66)" in helper
    assert "std::_Exit(0)" in helper
    assert "window->releaseResources()" not in helper
    assert "window->hide()" not in helper
    assert "return 0;" not in helper
    assert helper.index("std::_Exit(66)") < helper.index("std::_Exit(0)")


def test_preflight_scene_reports_a_no_frame_probe_as_unsafe(monkeypatch, tmp_path):
    source = tmp_path / "431960" / "123" / "scene.json"
    source.parent.mkdir(parents=True)
    source.write_text("{}")
    (source.parent / "project.json").write_text('{"file":"scene.json","type":"scene"}')
    assets = tmp_path / "assets"
    assets.mkdir()
    helper = pyext.Path(__file__).resolve().parents[1] / "plasma-plugin/contents/tools/dcent-scene-preflight"

    class FakeCompleted:
        returncode = 66
        stderr = ""

    monkeypatch.setattr(pyext.Path, "home", classmethod(lambda cls: tmp_path))
    monkeypatch.setattr(pyext.subprocess, "run", lambda *a, **k: FakeCompleted())
    monkeypatch.setattr(pyext.os, "access", lambda *a, **k: True)
    monkeypatch.setattr(pyext.shutil, "which", lambda name: "/usr/bin/" + name)

    result = pyext.preflight_scene(str(source), str(assets))

    assert result["safe"] is False
    assert result["returncode"] == 66
    assert "no first frame" in result["status"]


def test_paused_web_wallpaper_snapshot_is_stored_before_it_is_shown():
    root = Path(__file__).resolve().parents[1]
    qml = (root / "plasma-plugin/contents/ui/backend/QtWebView.qml").read_text()

    # QQuickItemGrabResult::url uses Qt's internal "itemgrabber:" protocol (see
    # tests/qml/tst_pause_snapshot.qml) which Qt Quick's Image cannot load, so
    # the paused frame has to reach the disk before it is displayed. The frozen
    # view may only be hidden once the still really loaded, otherwise pausing a
    # web wallpaper leaves an empty desktop.
    assert "pauseImage.source = result.url" not in qml
    assert "result.saveToFile(snapshotPath)" in qml
    assert 'pauseImage.source = "file://" + snapshotPath' in qml
    assert "if (status === Image.Ready && web.paused)" in qml
    assert "cache: false" in qml


def test_pause_snapshot_never_relies_on_the_internal_itemgrabber_url():
    root = Path(__file__).resolve().parents[1]
    test_file = (root / "tests/qml/tst_pause_snapshot.qml").read_text()

    assert 'compare(url.indexOf("itemgrabber:"), 0)' in test_file
    assert "result.saveToFile(testCase.snapshotPath)" in test_file


def test_identical_concurrent_preflights_share_one_native_probe(tmp_path, monkeypatch):
    import concurrent.futures
    import threading

    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    calls = []
    release = threading.Event()

    def slow_probe(source, assets):
        calls.append((source, assets))
        release.wait(10)
        return {"safe": True, "status": "native parser passed"}

    monkeypatch.setattr(pyext, "_preflight_scene", slow_probe)

    with concurrent.futures.ThreadPoolExecutor(3) as pool:
        futures = [pool.submit(pyext.preflight_scene, "/scene/scene.json", "/assets") for _ in range(3)]
        # Give the followers time to join the running probe before it finishes.
        time.sleep(0.3)
        release.set()
        results = [future.result(timeout=20) for future in futures]

    assert len(calls) == 1, "one scene must not start several native renderers"
    assert all(result["safe"] for result in results)
    assert sum(1 for result in results if result.get("shared")) == 2


def test_preflight_never_blocks_the_rpc_event_loop(tmp_path, monkeypatch):
    import asyncio
    import threading

    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    release = threading.Event()

    def slow_probe(source, assets):
        release.wait(10)
        return {"safe": True, "status": "native parser passed"}

    monkeypatch.setattr(pyext, "_preflight_scene", slow_probe)

    rpc = pyext.Jsonrpc()

    def preflight_scene(source, assets):
        return pyext.preflight_scene(source, assets)

    @rpc.add_method
    def audio_spectrum():
        return {"bands": [0.0, 1.0]}

    rpc.add_method(preflight_scene)

    async def exercise():
        probe = asyncio.create_task(
            rpc.handle_async(json.dumps({"id": 1, "method": "preflight_scene", "params": ["/scene/scene.json", "/assets"]}))
        )
        await asyncio.sleep(0.1)
        # The wallpaper keeps its audio reactivity while a cold scene is probed.
        fast = await asyncio.wait_for(rpc.handle_async(json.dumps({"id": 2, "method": "audio_spectrum", "params": []})), timeout=2)
        assert json.loads(fast)["result"]["bands"] == [0.0, 1.0]
        assert not probe.done(), "the probe must still be running off the loop"
        release.set()
        answer = json.loads(await asyncio.wait_for(probe, timeout=10))
        assert answer["result"]["safe"] is True

    asyncio.run(exercise())


def _fake_scene_renderer_png(width: int, height: int) -> bytes:
    """A PNG whose header and size satisfy the fallback readiness checks."""
    header = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height)
    header += bytes([8, 6, 0, 0, 0])
    return header + b"\x00" * 4096


def test_unpacked_scene_projects_can_still_render_a_fallback(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    root = tmp_path / "431960"
    wallpaper = root / "3308516304"
    wallpaper.mkdir(parents=True)
    # Modern Wallpaper Engine scenes ship as scene.json plus model/material
    # folders: no scene.pkg exists, and the renderer takes the project folder.
    (wallpaper / "project.json").write_text(json.dumps({"type": "scene", "file": "scene.json", "title": "Clock"}))
    (wallpaper / "scene.json").write_text(json.dumps({"objects": []}))
    assets = tmp_path / "assets"
    assets.mkdir()
    renderer = tmp_path / "linux-wallpaperengine"
    renderer.write_text("#!/bin/sh\n")
    renderer.chmod(0o755)

    monkeypatch.setattr(pyext.Path, "home", classmethod(lambda cls: home))
    monkeypatch.setattr(pyext, "_list_screens_for_render", lambda job: [])
    monkeypatch.setattr(pyext, "scene_video_renderer", lambda: renderer)

    def fake_popen(command, *args, **kwargs):
        target = Path(command[command.index("--screenshot") + 1])
        target.write_bytes(_fake_scene_renderer_png(3840, 2160))

        class Finished:
            pid = 4242
            returncode = 0

            def poll(self):
                return 0

            def terminate(self):
                pass

        return Finished()

    monkeypatch.setattr(pyext.subprocess, "Popen", fake_popen)

    still = pyext._render_scene_fallback(str(wallpaper), str(assets))

    assert still.get("ok") is True, still
    assert (still["width"], still["height"]) == (3840, 2160)
    assert Path(still["path"]).is_file()
    assert Path(still["path"]).stat().st_size > 1024
