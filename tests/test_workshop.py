from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).parents[1] / "plasma-plugin" / "contents" / "pyext.py"
spec = importlib.util.spec_from_file_location("dcent_workshop_pyext", MODULE_PATH)
pyext = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(pyext)


SEARCH_HTML = """
<html><body>
<div>1,234 entries matching filters</div>
<div class="card">
  <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=1234567890">
    <img src="https://images.steamusercontent.com/ugc/one/?imw=288&amp;imh=288" alt="Neon &amp; Rain">
  </a>
  <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=1234567890">Neon &amp; Rain</a>
  <a href="https://steamcommunity.com/id/artist/myworkshopfiles/?appid=431960">By Artist Name</a>
</div>
<div class="card">
  <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=2234567890">
    <img src="https://images.steamusercontent.com/ugc/two/?imw=288&amp;imh=288" alt="Night City">
  </a>
  <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=2234567890">Night City</a>
  <a href="https://steamcommunity.com/profiles/7656119/myworkshopfiles/?appid=431960">By Second Artist</a>
</div>
</body></html>
"""


def _ssr_search_html() -> str:
    browse = {
        "queryKey": ["workshop_browse", {"appid": 431960}],
        "state": {"data": {
            "current_page": 2,
            "total_pages": 4,
            "total_count": 91,
            "results": [{
                "publishedfileid": "3521337568",
                "creator": "76561198000000001",
                "consumer_appid": 431960,
                "title": "Cyberpunk: Lucy",
                "short_description": "Animated city",
                "preview_url": "https://images.steamusercontent.com/ugc/preview/",
                "file_size": "33742006",
                "time_updated": 1700000000,
                "subscriptions": 1234,
                "views": 5678,
                "star_rating": 4.5,
                "tags": [{"tag": "Scene"}, {"tag": "Cyberpunk"}],
            }],
        }},
    }
    author = {
        "queryKey": ["PlayerLinkDetails", "76561198000000001"],
        "state": {"data": {"public_data": {
            "persona_name": "Artist",
            "profile_url": "artist-name",
            "steamid": "76561198000000001",
        }}},
    }
    context = {"queryData": json.dumps({"queries": [browse, author]})}
    encoded = json.dumps(json.dumps(context))
    return f'<script>window.SSR.renderContext=JSON.parse({encoded});</script>'


def test_workshop_search_parser_marks_installed_and_keeps_remote_items(tmp_path):
    installed = tmp_path / "1234567890"
    installed.mkdir()
    (installed / "project.json").write_text("{}", encoding="utf-8")

    result = pyext.parse_workshop_search_html(SEARCH_HTML, tmp_path)

    assert result["total"] == 1234
    assert [item["workshopId"] for item in result["items"]] == ["1234567890", "2234567890"]
    assert result["items"][0] == {
        "workshopId": "1234567890",
        "title": "Neon & Rain",
        "author": "Artist Name",
        "preview": "https://images.steamusercontent.com/ugc/one/?imw=512&imh=512",
        "workshopUrl": "https://steamcommunity.com/sharedfiles/filedetails/?id=1234567890",
        "installed": True,
        "folder": str(installed),
        "online": True,
    }
    assert result["items"][1]["installed"] is False
    assert result["items"][1]["folder"] == ""


def test_workshop_ssr_parser_returns_rich_metadata_and_exact_pagination(tmp_path):
    result = pyext.parse_workshop_search_html(_ssr_search_html(), tmp_path)

    assert result["total"] == 91
    assert result["currentPage"] == 2
    assert result["totalPages"] == 4
    assert result["hasMore"] is True
    item = result["items"][0]
    assert item["workshopId"] == "3521337568"
    assert item["title"] == "Cyberpunk: Lucy"
    assert item["author"] == "Artist"
    assert item["authorUrl"] == "https://steamcommunity.com/id/artist-name/"
    assert item["tags"] == ["Scene", "Cyberpunk"]
    assert item["kind"] == "scene"
    assert item["sizeBytes"] == 33742006
    assert item["updatedEpoch"] == 1700000000
    assert item["subscriptions"] == 1234
    assert item["views"] == 5678
    assert item["rating"] == 4.5


def test_changed_or_login_workshop_markup_is_an_error(tmp_path):
    with pytest.raises(ValueError, match="recognizable Workshop results"):
        pyext.parse_workshop_search_html("<html><title>Sign In</title></html>", tmp_path)


def test_workshop_optional_metadata_does_not_invent_property_labels():
    assert pyext._optional_plain_text(None) == ""
    assert pyext._optional_plain_text("") == ""
    assert pyext._optional_plain_text("<b>Hello</b>") == "Hello"


def test_workshop_search_url_is_bounded_and_encodes_filters():
    url = pyext.build_workshop_search_url("rain city", page=3, sort="toprated", kind="scene")

    assert "appid=431960" in url
    assert "searchtext=rain+city" in url
    assert "p=3" in url
    assert "browsesort=toprated" in url
    assert "requiredtags%5B%5D=Scene" in url

    with pytest.raises(ValueError):
        pyext.build_workshop_search_url("x", page=0)
    with pytest.raises(ValueError):
        pyext.build_workshop_search_url("x", sort="unsafe")


def test_workshop_identifier_validation_rejects_unsafe_values():
    assert pyext._workshop_id("3792870366") == "3792870366"
    with pytest.raises(ValueError):
        pyext._workshop_id("../../bad")


def test_workshop_status_waits_for_current_manifest_and_runnable_project(tmp_path):
    root = tmp_path / "steamapps" / "workshop" / "content" / "431960"
    folder = root / "333"
    folder.mkdir(parents=True)
    (folder / "project.json").write_text(
        '{"title":"Video","type":"video","file":"wallpaper.mp4"}', encoding="utf-8"
    )
    (folder / "wallpaper.mp4").write_bytes(b"video")
    manifest = root.parent.parent / "appworkshop_431960.acf"
    manifest.write_text(
        '"AppWorkshop"\n{\n"WorkshopItemsInstalled"\n{\n"333"\n{\n"manifest" "10"\n}\n}\n'
        '"WorkshopItemDetails"\n{\n"333"\n{\n"manifest" "10"\n"latest_manifest" "11"\n}\n}\n}',
        encoding="utf-8",
    )

    downloading = pyext.workshop_item_status("333", root)
    assert downloading["installed"] is False
    assert downloading["installState"] == "downloading"

    manifest.write_text(manifest.read_text().replace('"latest_manifest" "11"', '"latest_manifest" "10"'))
    installed = pyext.workshop_item_status("333", root)
    assert installed["installed"] is True
    assert installed["installState"] == "installed"
    assert installed["folder"] == str(folder)


def test_local_workshop_item_uses_real_source_not_preview(tmp_path):
    root = tmp_path / "431960"
    folder = root / "333"
    folder.mkdir(parents=True)
    (folder / "project.json").write_text(
        '{"title":"Local Scene","type":"scene","file":"scene.json","preview":"preview.jpg"}',
        encoding="utf-8",
    )
    (folder / "scene.pkg").write_bytes(b"packed")
    (folder / "preview.jpg").write_bytes(b"preview")

    item = pyext.local_workshop_item("333", root)

    assert item["ok"] is True
    assert item["kind"] == "scene"
    assert item["media"] == str(folder / "scene.json")
    assert item["preview"] == (folder / "preview.jpg").as_uri()
    assert item["media"] != str(folder / "preview.jpg")


def test_local_catalog_refresh_discovers_new_numeric_projects(tmp_path):
    root = tmp_path / "431960"
    for workshop_id, title in (("111", "Zulu"), ("222", "Alpha")):
        folder = root / workshop_id
        folder.mkdir(parents=True)
        (folder / "project.json").write_text(
            '{"title":"' + title + '","type":"video","file":"wallpaper.mp4","preview":"preview.jpg"}',
            encoding="utf-8",
        )
        (folder / "wallpaper.mp4").write_bytes(b"video")
        (folder / "preview.jpg").write_bytes(b"preview")
    ignored = root / "not-an-id"
    ignored.mkdir(parents=True)
    (ignored / "project.json").write_text("{}", encoding="utf-8")

    result = pyext.list_local_workshop_items(root)

    assert result["ok"] is True
    assert result["count"] == 2
    assert [item["title"] for item in result["items"]] == ["Alpha", "Zulu"]


def test_local_workshop_item_exposes_tags_size_and_timestamp(tmp_path):
    folder = tmp_path / "431960" / "3792870366"
    folder.mkdir(parents=True)
    (folder / "project.json").write_text(
        '{"title":"Test","type":"scene","file":"scene.json","tags":["Anime","Mature"],'
        '"contentrating":"Everyone","preview":"preview.jpg"}'
    )
    (folder / "scene.json").write_text("{}")
    (folder / "scene.pkg").write_bytes(b"x" * 2048)
    (folder / "preview.jpg").write_bytes(b"y" * 16)

    item = pyext.local_workshop_item("3792870366", tmp_path / "431960")

    assert item["ok"] is True
    assert item["tags"] == ["Anime", "Mature", "Everyone"]
    expected_size = sum(entry.stat().st_size for entry in folder.iterdir() if entry.is_file())
    assert item["sizeBytes"] == item["size"] == expected_size
    assert item["updatedEpoch"] > 0


def test_workshop_download_rejects_invalid_identifier():
    result = pyext.workshop_download("../../bad")
    assert result["ok"] is False
    assert result["started"] is False


def test_workshop_download_uses_steam_client_helper(monkeypatch, tmp_path):
    helper = tmp_path / "dcent-steam-workshop"
    helper.write_text("#!/bin/sh\nexit 0\n")
    helper.chmod(0o755)
    monkeypatch.setattr(pyext, "STEAM_WORKSHOP_HELPER", helper)

    result = pyext.workshop_download("3792870366", str(tmp_path / "lib"))

    assert result["ok"] is True
    assert result["started"] is True
    assert result["via"] == "steam-client"
    assert result["workshopId"] == "3792870366"


def test_workshop_download_reports_helper_failure(monkeypatch, tmp_path):
    helper = tmp_path / "dcent-steam-workshop"
    helper.write_text("#!/bin/sh\necho 'no steam client' >&2\nexit 3\n")
    helper.chmod(0o755)
    monkeypatch.setattr(pyext, "STEAM_WORKSHOP_HELPER", helper)

    result = pyext.workshop_download("3792870366", str(tmp_path / "lib"))

    assert result["ok"] is False
    assert result["started"] is False
    assert "no steam client" in result["error"]


def test_workshop_download_reports_missing_helper(monkeypatch, tmp_path):
    monkeypatch.setattr(pyext, "STEAM_WORKSHOP_HELPER", tmp_path / "no-helper")
    monkeypatch.setattr(pyext, "STEAMCMD_SCRIPT", tmp_path / "no-such-steamcmd.sh")

    result = pyext.workshop_download("3792870366", str(tmp_path / "lib"))

    assert result["ok"] is False
    assert result["started"] is False
    assert "helper" in result["error"].lower()


def test_steam_api_key_validation_and_storage(monkeypatch, tmp_path):
    monkeypatch.setattr(pyext, "DCENT_CONFIG_DIR", tmp_path)
    monkeypatch.setattr(pyext, "STEAM_API_KEY_FILE", tmp_path / "steam_api_key")

    assert pyext.steam_api_key_status()["configured"] is False
    assert pyext.set_steam_api_key("not-a-key")["ok"] is False

    valid = "a1b2c3d4e5f60718293a4b5c6d7e8f90"
    assert pyext.set_steam_api_key(valid)["ok"] is True
    assert pyext.steam_api_key_status()["configured"] is True
    assert pyext._read_steam_api_key() == valid


def test_workshop_subscribe_requires_a_configured_key(monkeypatch, tmp_path):
    monkeypatch.setattr(pyext, "STEAM_API_KEY_FILE", tmp_path / "missing-key")
    result = pyext.workshop_subscribe("3050841967")
    assert result["ok"] is False
    assert result["subscribed"] is False


def test_workshop_subscribe_rejects_invalid_identifier():
    result = pyext.workshop_subscribe("../../etc")
    assert result["ok"] is False
    assert result["subscribed"] is False

