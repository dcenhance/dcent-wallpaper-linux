from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).parents[1] / "plasma-plugin" / "contents" / "pyext.py"
spec = importlib.util.spec_from_file_location("dcent_properties_pyext", MODULE_PATH)
pyext = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(pyext)


def _write_project(path: Path, payload: dict) -> None:
    path.mkdir(parents=True, exist_ok=True)
    (path / "project.json").write_text(json.dumps(payload), encoding="utf-8")


def test_property_parser_normalizes_every_supported_editor_kind(tmp_path):
    wallpaper = tmp_path / "431960" / "10"
    _write_project(
        wallpaper,
        {
            "title": "All controls",
            "type": "web",
            "file": "index.html",
            "general": {
                "properties": {
                    "heading": {"type": "group", "text": "Appearance", "order": 0},
                    "enabled": {"type": "bool", "text": "Enabled", "value": 1, "order": 2},
                    "amount": {
                        "type": "slider", "text": "Amount", "value": "1.25",
                        "min": 0, "max": 2, "step": 0.05, "precision": 2, "order": 3,
                    },
                    "mode": {
                        "type": "combo", "text": "Mode", "value": 2,
                        "options": [{"label": "One", "value": 1}, {"label": "Two", "value": 2}],
                        "order": 4,
                    },
                    "tint": {"type": "color", "text": "Tint", "value": "1 0.5 0", "order": 5},
                    "caption": {"type": "textinput", "text": "Caption", "value": "Hi", "order": 6},
                    "picture": {"type": "file", "text": "Picture", "fileType": "image", "order": 7},
                    "folder": {"type": "directory", "text": "Folder", "mode": "folder", "order": 8},
                    "texture": {"type": "scenetexture", "text": "Texture", "value": "materials/a.tex", "order": 9},
                    "shortcut": {"type": "usershortcut", "text": "Shortcut", "value": "Ctrl+K", "order": 10},
                    "note": {"type": "Text", "text": "Read me", "order": 11},
                    "legacy_label": {"text": "Legacy section", "order": 1},
                }
            },
        },
    )
    (wallpaper / "index.html").write_text("<html></html>")

    project = pyext.inspect_wallpaper_project(str(wallpaper))
    props = {entry["name"]: entry for entry in project["properties"]}

    assert project["ok"] is True
    assert project["kind"] == "web"
    assert [entry["name"] for entry in project["properties"]][:3] == [
        "heading", "legacy_label", "enabled"
    ]
    assert props["enabled"]["type"] == "bool" and props["enabled"]["default"] is True
    assert props["amount"]["default"] == 1.25
    assert props["amount"]["precision"] == 2
    assert props["mode"]["options"][1] == {"label": "Two", "value": 2}
    assert props["picture"]["type"] == "file"
    assert props["folder"]["type"] == "directory"
    assert props["texture"]["type"] == "scenetexture"
    assert props["shortcut"]["type"] == "usershortcut"
    assert props["note"]["type"] == "text"
    assert props["legacy_label"]["type"] == "label"


def test_preset_values_overlay_dependency_defaults_and_keep_extra_keys(tmp_path):
    root = tmp_path / "431960"
    base = root / "20"
    _write_project(
        base,
        {
            "title": "Base",
            "type": "web",
            "file": "index.html",
            "general": {
                "properties": {
                    "enabled": {"type": "bool", "value": True},
                    "image": {"type": "file", "value": ""},
                    "amount": {"type": "slider", "value": 1, "min": 0, "max": 10},
                }
            },
        },
    )
    (base / "index.html").write_text("<html></html>")
    preset = root / "21"
    _write_project(
        preset,
        {
            "title": "Preset",
            "dependency": "20",
            "preset": {
                "enabled": 0,
                "image": "files/custom.png",
                "amount": "2.5",
                "legacy_runtime_key": "keep-me",
            },
        },
    )
    (preset / "files").mkdir()
    (preset / "files" / "custom.png").write_bytes(b"png")

    project = pyext.inspect_wallpaper_project(str(preset))
    props = {entry["name"]: entry for entry in project["properties"]}

    assert project["kind"] == "web"
    assert project["sourceProjectId"] == "20"
    assert project["isPreset"] is True
    assert props["enabled"]["value"] is False
    assert props["amount"]["value"] == 2.5
    assert props["image"]["value"] == "files/custom.png"
    assert project["runtimeOverrides"]["legacy_runtime_key"] == "keep-me"
    assert project["presetOverrides"]["image"] == "files/custom.png"
    assert project["runtimeOverrides"]["image"] == str(preset / "files" / "custom.png")


def test_scene_texture_preset_resolves_against_preset_owner(tmp_path):
    root = tmp_path / "431960"
    dependency = root / "100"
    _write_project(
        dependency,
        {
            "title": "Scene",
            "type": "scene",
            "file": "scene.json",
            "general": {"properties": {"custombackground": {"type": "scenetexture", "value": ""}}},
        },
    )
    (dependency / "scene.pkg").write_bytes(b"packed")
    preset = root / "101"
    _write_project(
        preset,
        {"title": "Preset", "dependency": "100", "preset": {"custombackground": "files/1.jpg"}},
    )
    (preset / "files").mkdir()
    texture = preset / "files" / "1.jpg"
    texture.write_bytes(b"image")

    project = pyext.inspect_wallpaper_project(preset)

    assert project["presetOverrides"]["custombackground"] == "files/1.jpg"
    assert project["runtimeOverrides"]["custombackground"] == str(texture)
    assert project["properties"][0]["sceneValue"] == str(texture)


def test_web_file_uri_is_delivered_as_native_path(tmp_path):
    image = tmp_path / "custom image.png"
    image.write_bytes(b"image")
    spec = {"type": "file", "valueRoot": str(tmp_path)}

    assert pyext._web_property_value(spec, image.as_uri()) == str(image)


def test_user_overrides_are_coerced_and_unknown_keys_are_rejected(tmp_path):
    wallpaper = tmp_path / "30"
    _write_project(
        wallpaper,
        {
            "title": "Typed",
            "type": "scene",
            "file": "scene.json",
            "general": {
                "properties": {
                    "enabled": {"type": "bool", "value": True},
                    "amount": {"type": "slider", "value": 1, "min": 0, "max": 10},
                    "mode": {
                        "type": "combo", "value": "a",
                        "options": [{"label": "A", "value": "a"}, {"label": "B", "value": "b"}],
                    },
                    "note": {"type": "text", "text": "not editable"},
                }
            },
        },
    )
    (wallpaper / "scene.pkg").write_bytes(b"packed")

    project = pyext.inspect_wallpaper_project(str(wallpaper))
    values = pyext.normalize_property_overrides(
        project["properties"],
        {"enabled": "0", "amount": "99", "mode": "b", "note": "bad", "unknown": 4},
    )

    assert values == {"enabled": False, "amount": 10, "mode": "b"}


def test_renderer_property_arguments_are_typed_and_deterministic(tmp_path):
    command = pyext.build_scene_video_renderer_command(
        tmp_path / "renderer",
        tmp_path / "wallpaper",
        tmp_path / "assets",
        1920,
        1080,
        "fit",
        properties={"z": "a=b", "enabled": False, "amount": 1.25},
    )

    pairs = [command[index + 1] for index, value in enumerate(command) if value == "--set-property"]
    assert pairs == ["amount=1.25", "enabled=0", "z=a=b"]


def test_static_and_video_scene_commands_accept_same_property_overrides(tmp_path):
    args = dict(
        renderer=tmp_path / "renderer",
        wallpaper=tmp_path / "wallpaper",
        assets=tmp_path / "assets",
        width=1920,
        height=1080,
        scaling="fill",
        properties={"enabled": True},
    )
    static = pyext.build_scene_fallback_command(screenshot=tmp_path / "shot.png", **args)
    video = pyext.build_scene_video_renderer_command(**args)

    assert static[static.index("--set-property") + 1] == "enabled=1"
    assert video[video.index("--set-property") + 1] == "enabled=1"


def test_project_property_overrides_persist_compactly_and_reset_safely(tmp_path):
    wallpaper = tmp_path / "431960" / "40"
    _write_project(
        wallpaper,
        {
            "title": "Persistent",
            "type": "web",
            "file": "index.html",
            "general": {
                "properties": {
                    "enabled": {"type": "bool", "value": True},
                    "amount": {"type": "slider", "value": 2, "min": 0, "max": 10},
                }
            },
        },
    )
    (wallpaper / "index.html").write_text("<html></html>")
    store = pyext.Main(config_dir=tmp_path / "config")
    store.write_wallpaper_config("40", {"display_mode": 2})
    original_store = pyext.M
    pyext.M = store
    try:
        saved = pyext.write_wallpaper_properties(
            "40", str(wallpaper), {"enabled": "0", "amount": 2, "unknown": "drop"}
        )
        loaded = pyext.get_wallpaper_project(str(wallpaper), "40")

        assert saved["ok"] is True
        assert saved["userOverrides"] == {"enabled": False}
        assert loaded["userOverrides"] == {"enabled": False}
        assert loaded["runtimeOverrides"] == {"enabled": False}
        assert store.read_wallpaper_config("40") == {
            "display_mode": 2,
            "property_overrides": {"enabled": False},
        }

        reset = pyext.reset_wallpaper_properties("40", str(wallpaper))
        assert reset["userOverrides"] == {}
        assert store.read_wallpaper_config("40") == {"display_mode": 2}
    finally:
        pyext.M = original_store


def test_wallpaper_config_rejects_unsafe_identifier(tmp_path):
    store = pyext.Main(config_dir=tmp_path / "config")

    try:
        store.write_wallpaper_config("../outside", {"property_overrides": {}})
    except ValueError as error:
        assert "identifier" in str(error)
    else:
        raise AssertionError("unsafe wallpaper identifier was accepted")


def test_project_inspection_accepts_declared_nonstandard_scene_package(tmp_path):
    wallpaper = tmp_path / "431960" / "50"
    _write_project(wallpaper, {"title": "GIF scene", "type": "scene", "file": "gifscene.json"})
    (wallpaper / "gifscene.pkg").write_bytes(b"packed")

    result = pyext.inspect_wallpaper_project(wallpaper)

    assert result["ok"] is True
    assert result["source"] == str(wallpaper / "gifscene.json")
    assert pyext._scene_package(wallpaper, {"file": "gifscene.json"}) == wallpaper / "gifscene.pkg"


def test_fractional_slider_without_step_derives_precision():
    spec = pyext._normalize_property(
        "position", {"type": "slider", "value": 1045.8641, "min": -10000, "max": 10000}, 0
    )

    assert spec["precision"] == 4
    assert spec["step"] == 0.0001


def test_slider_preserves_declared_high_precision():
    spec = pyext._normalize_property(
        "intensity", {"type": "slider", "value": 0.123456789, "min": 0, "max": 1, "precision": 10}, 0
    )

    assert spec["precision"] == 10


def test_combo_option_condition_is_preserved():
    spec = pyext._normalize_property(
        "mode",
        {
            "type": "combo",
            "value": 1,
            "options": [{"label": "Conditional", "value": 1, "condition": "enabled.value"}],
        },
        0,
    )

    assert spec["options"] == [
        {"label": "Conditional", "value": 1, "condition": "enabled.value"}
    ]


def test_combo_values_keep_bool_number_and_string_types_distinct():
    spec = pyext._normalize_property(
        "hideWhenSilent",
        {
            "type": "combo",
            "value": 1,
            "options": [
                {"label": "False", "value": False},
                {"label": "True", "value": True},
                {"label": "Special", "value": 1},
                {"label": "Text one", "value": "1"},
            ],
        },
        0,
    )

    assert pyext._coerce_property_value(spec, 1) == 1
    assert type(pyext._coerce_property_value(spec, 1)) is int
    assert pyext._coerce_property_value(spec, True) is True
    assert pyext._coerce_property_value(spec, "1") == "1"


def test_255_color_values_are_normalized_instead_of_clamped_white():
    spec = pyext._normalize_property(
        "tint", {"type": "color", "text": "Tint", "value": "255 128 0"}, 0
    )

    channels = [float(value) for value in spec["default"].split()]
    assert channels == [1.0, pytest.approx(128 / 255), 0.0]


def test_project_localization_translates_property_and_combo_labels(tmp_path, monkeypatch):
    wallpaper = tmp_path / "60"
    _write_project(
        wallpaper,
        {
            "title": "Localized",
            "type": "web",
            "file": "index.html",
            "general": {
                "localization": {
                    "en-us": {
                        "ui_mode": "<b>Display mode</b>",
                        "ui_mode_one": "Calm",
                    }
                },
                "properties": {
                    "mode": {
                        "type": "combo", "text": "ui_mode", "value": 1,
                        "options": [{"label": "ui_mode_one", "value": 1}],
                    }
                },
            },
        },
    )
    (wallpaper / "index.html").write_text("<html></html>")
    monkeypatch.setenv("LANG", "en_US.UTF-8")

    project = pyext.inspect_wallpaper_project(wallpaper)
    prop = project["properties"][0]

    assert prop["label"] == "Display mode"
    assert prop["rawText"] == "ui_mode"
    assert prop["options"][0]["label"] == "Calm"
    assert project["locales"] == ["en-us"]


def test_property_directory_listing_is_bounded_filtered_and_contained(tmp_path):
    selected = tmp_path / "selected"
    selected.mkdir()
    (selected / "b.jpg").write_bytes(b"jpg")
    (selected / "a.png").write_bytes(b"png")
    (selected / "movie.mp4").write_bytes(b"video")
    (selected / "note.txt").write_text("ignore")
    outside = tmp_path / "outside.jpg"
    outside.write_bytes(b"outside")
    (selected / "escape.jpg").symlink_to(outside)

    result = pyext.list_property_directory(selected.as_uri(), "image", 1)

    assert result["ok"] is True
    assert result["truncated"] is True
    assert result["files"] == [str(selected / "a.png")]


def test_project_reports_property_capabilities_and_type_counts(tmp_path):
    wallpaper = tmp_path / "70"
    _write_project(
        wallpaper,
        {
            "title": "Capabilities",
            "type": "web",
            "file": "index.html",
            "general": {
                "supportsaudioprocessing": True,
                "supportsvideo": True,
                "supportsvideoflags": 3,
                "properties": {
                    "enabled": {"type": "bool", "text": "Enabled", "value": True},
                    "amount": {"type": "slider", "text": "Amount", "value": 1, "min": 0, "max": 2},
                    "heading": {"type": "group", "text": "Heading"},
                },
            },
        },
    )
    (wallpaper / "index.html").write_text("<html></html>")

    project = pyext.inspect_wallpaper_project(wallpaper)

    assert project["supportsAudioProcessing"] is True
    assert project["supportsVideo"] is True
    assert project["videoFlags"] == 3
    assert project["propertyTypeCounts"] == {"bool": 1, "group": 1, "slider": 1}


def test_unknown_future_property_types_are_read_only():
    spec = pyext._normalize_property(
        "future", {"type": "brand-new-control", "text": "Future", "value": "x"}, 0
    )

    assert spec["type"] == "unknown"
    assert spec["editable"] is False


def test_video_metadata_properties_are_not_exposed_as_runtime_controls(tmp_path):
    wallpaper = tmp_path / "80"
    _write_project(
        wallpaper,
        {
            "title": "Video",
            "type": "video",
            "file": "wallpaper.mp4",
            "general": {"properties": {"schemecolor": {"type": "color", "value": "0 0 0"}}},
        },
    )
    (wallpaper / "wallpaper.mp4").write_bytes(b"video")

    project = pyext.inspect_wallpaper_project(wallpaper)

    assert project["properties"][0]["runtimeSupported"] is False
    assert project["properties"][0]["editable"] is False
    assert project["editablePropertyCount"] == 0


def test_file_property_discovers_included_background_assets_per_wallpaper(tmp_path):
    wallpaper = tmp_path / "90"
    _write_project(
        wallpaper,
        {
            "title": "Multiple backgrounds",
            "type": "web",
            "file": "index.html",
            "general": {
                "properties": {
                    "background": {
                        "type": "file",
                        "text": "Background",
                        "fileType": "image",
                        "value": "backgrounds/day.jpg",
                    }
                }
            },
        },
    )
    (wallpaper / "index.html").write_text("<html></html>")
    (wallpaper / "backgrounds").mkdir()
    (wallpaper / "backgrounds" / "day.jpg").write_bytes(b"day")
    (wallpaper / "backgrounds" / "night.png").write_bytes(b"night")
    (wallpaper / "backgrounds" / "clip.webm").write_bytes(b"video")
    (wallpaper / "preview.jpg").write_bytes(b"preview")

    project = pyext.inspect_wallpaper_project(wallpaper)
    prop = project["properties"][0]

    assert prop["assetOptions"] == [
        {"label": "backgrounds/day.jpg", "value": str(wallpaper / "backgrounds" / "day.jpg")},
        {"label": "backgrounds/night.png", "value": str(wallpaper / "backgrounds" / "night.png")},
    ]


def test_audio_spectrum_produces_wallpaper_engine_stereo_bands():
    sample_rate = 48000
    frames = 2048
    pcm = []
    for index in range(frames):
        value = math.sin(2 * math.pi * 440 * index / sample_rate) * 0.75
        pcm.extend((value, value))

    bands = pyext._audio_spectrum_from_pcm(pcm, channels=2, sample_rate=sample_rate)

    assert len(bands) == 128
    assert all(0.0 <= value <= 1.0 for value in bands)
    assert max(bands) > 0.1
