#!/bin/python3

import asyncio
import json
import base64
import html
import math
import os
import platform
import shutil
import subprocess
import urllib.parse
import urllib.error
import urllib.request
import hashlib
import re
import signal
import struct
import threading
import time
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal, InvalidOperation
from html.parser import HTMLParser

from pathlib import Path

from typing import Callable,Any,Optional

# import functools;



class Main:
    def __init__(self, config_dir: Path | None = None):
        self.config_dir: Path = Path(config_dir) if config_dir is not None else self.__config_dir()
        self.config_wallpaper_dir: Path = self.config_dir / 'wallpaper'

        self.config_wallpaper_dir.mkdir(parents=True, exist_ok=True)

    def __config_dir(self) -> Path:
        config_name: str = "wekde"
        xdg_config_home: Optional[str] = os.getenv("XDG_CONFIG_HOME")
        if xdg_config_home:
            return Path(xdg_config_home) / config_name
        return Path.home() / ".config" / config_name
    def __wallpaper_config_file(self, id: str) -> Path:
        if not isinstance(id, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", id):
            raise ValueError("Invalid wallpaper identifier")
        return self.config_wallpaper_dir / (id + '.json')

    def read_wallpaper_config(self, id: str) -> dict:
        cfg_file: Path = self.__wallpaper_config_file(id)
        if not cfg_file.exists():
            return dict()

        try:
            with open(cfg_file, "r", encoding="utf-8") as f:
                value = json.load(f)
            return value if isinstance(value, dict) else {}
        except (OSError, json.JSONDecodeError):
            return {}

    def write_wallpaper_config(self, id: str, changed: dict) -> None:
        if not isinstance(changed, dict):
            raise TypeError("Wallpaper configuration update must be an object")
        cfg: dict = self.read_wallpaper_config(id)
        cfg.update(changed)
        cfg_file: Path = self.__wallpaper_config_file(id)
        temporary = cfg_file.with_suffix(f".json.{os.getpid()}.tmp")
        temporary.write_text(
            json.dumps(cfg, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        temporary.replace(cfg_file)

    def remove_wallpaper_config_keys(self, id: str, keys: set[str]) -> None:
        cfg = self.read_wallpaper_config(id)
        for key in keys:
            cfg.pop(key, None)
        cfg_file = self.__wallpaper_config_file(id)
        if not cfg:
            cfg_file.unlink(missing_ok=True)
            return
        temporary = cfg_file.with_suffix(f".json.{os.getpid()}.tmp")
        temporary.write_text(
            json.dumps(cfg, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        temporary.replace(cfg_file)

    def reset_wallpaper_config(self, id: str) -> None:
        cfg_file: Path = self.__wallpaper_config_file(id)
        cfg_file.unlink(missing_ok=True)

    def delete_wallpaper_config(self, id: str) -> None:
        cfg_file: Path = self.__wallpaper_config_file(id)
        if cfg_file.exists():
            cfg_file.unlink()

class Jsonrpc:
    _RENDER_METHODS = {
        "render_scene_fallback",
        "render_scene_video_fallback",
    }
    _BACKGROUND_METHODS = {
        "search_workshop",
        "list_local_workshop_items",
        "list_property_directory",
        "set_login_wallpaper",
    }

    def __init__(self):
        self.method_map = dict()
        self._render_executor = ThreadPoolExecutor(
            max_workers=1, thread_name_prefix="dcent-render"
        )
        self._background_executor = ThreadPoolExecutor(
            max_workers=2, thread_name_prefix="dcent-background"
        )

    def add_method(self, func: Callable) -> Callable:
        self.method_map[func.__name__] = func
        return func

    def add_class_method(self, obj: Any, func: Callable) -> None:
        def wrapper(*args):
            func(obj, *args)
        self.method_map[func.__name__] = wrapper

    def handle(self, msg) -> str:
        j: dict = {}
        error = None
        try:
            j = json.loads(msg)
        except Exception as e:
            error = repr(e)
            return json.dumps({"id": -1, "error": error})

        result = {"id": j.get("id")}
        method = j.get("method")
        if method in self.method_map:
            func = self.method_map[method]
            params = j.get("params") or []
            try:
                result["result"] = func(*params)
            except Exception as e:
                error = repr(e)
        else:
            error = "jsonrpc no such func"
        if error:
            result["error"] = error
        return json.dumps(result)

    async def handle_async(self, msg) -> str:
        """Run long renderer RPCs off the websocket event loop."""
        try:
            request = json.loads(msg)
            method = request.get("method") if isinstance(request, dict) else None
        except (TypeError, json.JSONDecodeError):
            method = None
        if method in self._RENDER_METHODS:
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(self._render_executor, self.handle, msg)
        if method in self._BACKGROUND_METHODS:
            loop = asyncio.get_running_loop()
            return await loop.run_in_executor(self._background_executor, self.handle, msg)
        return self.handle(msg)

    def shutdown(self) -> None:
        self._render_executor.shutdown(wait=True, cancel_futures=True)
        self._background_executor.shutdown(wait=True, cancel_futures=True)


class SceneRenderCancelled(RuntimeError):
    pass


def _terminate_process_tree(process, grace_seconds: float = 0.35) -> None:
    if process is None or process.poll() is not None:
        return
    pid = getattr(process, "pid", None)
    try:
        if pid is not None:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        else:
            process.terminate()
    except (OSError, ProcessLookupError):
        try:
            process.terminate()
        except OSError:
            return
    deadline = time.monotonic() + grace_seconds
    while process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.01)
    if process.poll() is not None:
        return
    try:
        if pid is not None:
            os.killpg(os.getpgid(pid), signal.SIGKILL)
        else:
            process.kill()
    except (OSError, ProcessLookupError):
        try:
            process.kill()
        except OSError:
            pass


class SceneRenderJob:
    def __init__(self, render_id: str = ""):
        self.render_id = str(render_id or "")
        self._cancelled = threading.Event()
        self._lock = threading.Lock()
        self._processes = set()

    @property
    def cancelled(self) -> bool:
        return self._cancelled.is_set()

    @property
    def process_count(self) -> int:
        with self._lock:
            return len(self._processes)

    def track(self, process) -> None:
        with self._lock:
            if not self.cancelled:
                self._processes.add(process)
                return
        _terminate_process_tree(process)

    def untrack(self, process) -> None:
        with self._lock:
            self._processes.discard(process)

    def cancel(self) -> None:
        self._cancelled.set()
        with self._lock:
            processes = list(self._processes)
        for process in processes:
            _terminate_process_tree(process)


class SceneRenderCoordinator:
    _MAX_TOMBSTONES = 64

    def __init__(self):
        self._lock = threading.Lock()
        self._active_jobs = {}
        self._latest_id = ""
        self._serial = 0
        self._cancelled_before_start = OrderedDict()

    @property
    def active(self):
        with self._lock:
            if self._latest_id in self._active_jobs:
                return self._active_jobs[self._latest_id]
            return next(reversed(self._active_jobs.values()), None) if self._active_jobs else None

    def begin(self, render_id: str = "") -> SceneRenderJob:
        with self._lock:
            legacy_request = not render_id
            previous_jobs = list(self._active_jobs.values()) if legacy_request else []
            if legacy_request:
                self._serial += 1
                render_id = f"legacy-{self._serial}"
            render_id = str(render_id)
            was_cancelled = self._cancelled_before_start.pop(render_id, None) is not None
            job = SceneRenderJob(render_id)
            self._active_jobs[render_id] = job
            self._latest_id = render_id
        for previous in previous_jobs:
            previous.cancel()
        if was_cancelled:
            job.cancel()
        return job

    def cancel(self, render_id: str = "") -> bool:
        render_id = str(render_id or "")
        with self._lock:
            if render_id:
                job = self._active_jobs.get(render_id)
                if job is None:
                    self._cancelled_before_start[render_id] = time.monotonic()
                    self._cancelled_before_start.move_to_end(render_id)
                    while len(self._cancelled_before_start) > self._MAX_TOMBSTONES:
                        self._cancelled_before_start.popitem(last=False)
                    return True
                jobs = [job]
            else:
                jobs = list(self._active_jobs.values())
        for job in jobs:
            job.cancel()
        return bool(jobs)

    def cancel_all(self) -> bool:
        return self.cancel("")

    def finish(self, render_id_or_job, job: SceneRenderJob | None = None) -> None:
        if job is None:
            job = render_id_or_job
            render_id = job.render_id
        else:
            render_id = str(render_id_or_job or job.render_id)
        with self._lock:
            if self._active_jobs.get(render_id) is job:
                del self._active_jobs[render_id]
            if self._latest_id == render_id:
                self._latest_id = next(reversed(self._active_jobs), "")


def run_cancellable_process(
    job: SceneRenderJob,
    command,
    *,
    timeout: float,
    capture_output: bool = False,
    text: bool = False,
    **kwargs,
) -> subprocess.CompletedProcess:
    if job.cancelled:
        raise SceneRenderCancelled("scene render cancelled")
    if capture_output:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.PIPE
    process = subprocess.Popen(
        command,
        text=text,
        start_new_session=True,
        **kwargs,
    )
    job.track(process)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        _terminate_process_tree(process)
        process.communicate()
        raise
    finally:
        job.untrack(process)
    if job.cancelled:
        raise SceneRenderCancelled("scene render cancelled")
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


M = Main()
jrpc = Jsonrpc()
SCENE_RENDERS = SceneRenderCoordinator()


@jrpc.add_method
def cancel_scene_render(render_id: str = "") -> dict:
    return {"ok": True, "cancelled": SCENE_RENDERS.cancel(render_id)}


@jrpc.add_method
def version() -> str:
    return platform.python_version()


@jrpc.add_method
def readfile(path: str) -> str:
    with open(path, "rb") as f:
        data: bytes = f.read()
        return base64.b64encode(data).decode("ascii")


RUNNABLE_PROJECT_TYPES = {"scene", "video", "web", "image"}
EDITABLE_PROPERTY_TYPES = {
    "bool", "slider", "combo", "color", "textinput", "file", "directory",
    "scenetexture", "usershortcut", "unknown",
}
PRESENTATION_PROPERTY_TYPES = {"group", "label", "text"}


def _read_project_json(project_path: Path) -> dict:
    try:
        data = json.loads((project_path / "project.json").read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _scene_package(project_path: Path, project: dict) -> Path | None:
    declared = project.get("file")
    if isinstance(declared, str) and Path(declared).suffix.lower() == ".json":
        package = (project_path / declared).with_suffix(".pkg")
        if package.is_file():
            return package
    standard = project_path / "scene.pkg"
    if standard.is_file():
        return standard
    packages = sorted(item for item in project_path.glob("*.pkg") if item.is_file())
    return packages[0] if len(packages) == 1 else None


def _detect_project_kind(project_path: Path, project: dict) -> str:
    declared = str(project.get("type", "")).strip().lower()
    if declared in RUNNABLE_PROJECT_TYPES:
        return declared
    if str(project.get("category", "")).strip().lower() == "asset":
        return "asset"
    if _scene_package(project_path, project) is not None:
        return "scene"
    explicit = str(project.get("file", "")).strip().lower()
    suffix = Path(explicit).suffix
    if suffix in {".mp4", ".webm", ".mkv", ".mov", ".avi", ".m4v"}:
        return "video"
    if suffix in {".html", ".htm"}:
        return "web"
    if suffix in {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tif", ".tiff"}:
        return "image"
    return "unknown"


def _resolve_project_chain(wallpaper: str | Path) -> dict:
    original_path = _local_path(str(wallpaper)).expanduser()
    if original_path.name == "project.json":
        original_path = original_path.parent
    elif original_path.is_file():
        original_path = original_path.parent
    original_path = original_path.resolve()
    original_project = _read_project_json(original_path)
    if not original_project:
        return {
            "ok": False,
            "status": "invalid or missing project.json",
            "originalPath": str(original_path),
        }

    current_path = original_path
    current_project = original_project
    visited = {original_path.name}
    preset_layers: list[tuple[Path, dict]] = []
    while True:
        kind = _detect_project_kind(current_path, current_project)
        if kind in RUNNABLE_PROJECT_TYPES or kind == "asset":
            break
        preset = current_project.get("preset")
        if isinstance(preset, dict):
            preset_layers.append((current_path, dict(preset)))
        dependency = str(current_project.get("dependency", "")).strip()
        if not dependency or not dependency.isdigit() or dependency in visited:
            break
        dependency_path = current_path.parent / dependency
        dependency_project = _read_project_json(dependency_path)
        if not dependency_project:
            break
        visited.add(dependency)
        current_path = dependency_path.resolve()
        current_project = dependency_project

    runtime_preset: dict = {}
    preset_owners: dict[str, str] = {}
    for owner, values in reversed(preset_layers):
        runtime_preset.update(values)
        preset_owners.update({str(key): str(owner) for key in values})

    return {
        "ok": True,
        "originalPath": str(original_path),
        "originalProject": original_project,
        "sourcePath": str(current_path),
        "sourceProject": current_project,
        "kind": _detect_project_kind(current_path, current_project),
        "isPreset": current_path != original_path,
        "presetOverrides": runtime_preset,
        "presetOwners": preset_owners,
        "dependency": str(original_project.get("dependency", "")).strip(),
    }


def _project_source(project_path: Path, project: dict, kind: str) -> Path | None:
    explicit = project.get("file")
    if isinstance(explicit, str) and explicit.strip():
        candidate = (project_path / explicit).resolve()
        try:
            candidate.relative_to(project_path.resolve())
        except ValueError:
            return None
        if candidate.is_file() or (
            kind == "scene"
            and candidate.suffix.lower() == ".json"
            and _scene_package(project_path, project) is not None
        ):
            return candidate
    if kind == "scene":
        package = _scene_package(project_path, project)
        if package is not None:
            return package.with_suffix(".json")
    suffixes = {
        "video": (".mp4", ".webm", ".mkv", ".mov", ".avi", ".m4v"),
        "web": (".html", ".htm"),
        "image": (".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tif", ".tiff"),
    }.get(kind, ())
    files = [item for item in project_path.rglob("*") if item.is_file()]
    for suffix in suffixes:
        result = next(
            (
                item for item in files
                if item.suffix.lower() == suffix
                and not item.name.lower().startswith(("preview", "screenshot"))
            ),
            None,
        )
        if result:
            return result
    return None


def _plain_property_text(value: Any, fallback: str) -> str:
    text = value if isinstance(value, str) else ""
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"<[^>]*>", " ", text)
    text = html.unescape(text)
    text = re.sub(r"[ \t\r\f\v]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n", text).strip()
    if text:
        return text
    fallback = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", fallback)
    return fallback.replace("_", " ").strip() or "Property"


def _optional_plain_text(value: Any) -> str:
    if not isinstance(value, str) or not value.strip():
        return ""
    return _plain_property_text(value, "")


def _bool_value(value: Any, fallback: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off", ""}:
            return False
    return fallback


def _number_value(value: Any, fallback: float = 0.0) -> float:
    if isinstance(value, bool):
        return float(value)
    try:
        result = float(value)
    except (TypeError, ValueError):
        return float(fallback)
    return result if math.isfinite(result) else float(fallback)


def _normalize_property_type(spec: dict) -> str:
    value = spec.get("type")
    kind = str(value).strip().lower() if value is not None else ""
    aliases = {"boolean": "bool", "string": "textinput"}
    kind = aliases.get(kind, kind)
    if not kind:
        return "label"
    if kind in PRESENTATION_PROPERTY_TYPES or kind in EDITABLE_PROPERTY_TYPES:
        return kind
    return "unknown"


def _project_translations(general: dict) -> tuple[dict, list[str]]:
    localization = general.get("localization")
    if not isinstance(localization, dict):
        return {}, []
    locales = sorted(
        str(locale).lower() for locale, values in localization.items()
        if isinstance(values, dict)
    )
    requested = os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or "en_US"
    requested = requested.split(".", 1)[0].split("@", 1)[0].replace("_", "-").lower()
    candidates = [requested]
    language = requested.split("-", 1)[0]
    candidates.extend(locale for locale in locales if locale.split("-", 1)[0] == language)
    candidates.extend(["en-us", "en"])
    candidates.extend(locales)
    for locale in candidates:
        values = localization.get(locale)
        if isinstance(values, dict):
            return {
                str(key): str(value)
                for key, value in values.items()
                if isinstance(value, str)
            }, locales
    return {}, locales


def _translated_text(value: Any, translations: dict) -> Any:
    return translations.get(value, value) if isinstance(value, str) else value


def _normalize_combo_options(value: Any, translations: dict | None = None) -> list[dict]:
    translations = translations or {}
    result: list[dict] = []
    if not isinstance(value, list):
        return result
    for option in value:
        if not isinstance(option, dict) or "value" not in option:
            continue
        option_value = option["value"]
        normalized = {
            "label": _plain_property_text(
                _translated_text(option.get("label"), translations), str(option_value)
            ),
            "value": option_value,
        }
        if isinstance(option.get("condition"), str) and option["condition"].strip():
            normalized["condition"] = option["condition"]
        result.append(normalized)
    return result


def _coerce_color(value: Any, fallback: str = "1 1 1") -> str:
    if isinstance(value, (list, tuple)):
        value = " ".join(str(part) for part in value)
    if not isinstance(value, str):
        return fallback
    result = value.strip()
    if re.fullmatch(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?", result):
        channels = [int(result[index:index + 2], 16) / 255 for index in range(1, len(result), 2)]
        return " ".join(format(channel, ".8g") for channel in channels)
    parts = re.split(r"[\s,]+", result)
    if len(parts) in {3, 4}:
        try:
            channels = [float(part) for part in parts]
        except ValueError:
            return fallback
        if any(channel > 1 for channel in channels) and all(0 <= channel <= 255 for channel in channels):
            channels = [channel / 255 for channel in channels]
        channels = [max(0.0, min(1.0, channel)) for channel in channels]
        return " ".join(format(channel, ".8g") for channel in channels)
    return result or fallback


def _typed_scalar_equal(left: Any, right: Any) -> bool:
    if left is None or right is None:
        return left is None and right is None
    if isinstance(left, bool) or isinstance(right, bool):
        return isinstance(left, bool) and isinstance(right, bool) and left is right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        try:
            return Decimal(str(left)) == Decimal(str(right))
        except InvalidOperation:
            return False
    if isinstance(left, str) or isinstance(right, str):
        return isinstance(left, str) and isinstance(right, str) and left == right
    return type(left) is type(right) and left == right


def _coerce_property_value(property_spec: dict, value: Any) -> Any:
    kind = property_spec.get("type", "unknown")
    default = property_spec.get("default")
    if kind == "bool":
        return _bool_value(value, bool(default))
    if kind == "slider":
        number = _number_value(value, _number_value(default))
        minimum = _number_value(property_spec.get("min"), number)
        maximum = _number_value(property_spec.get("max"), number)
        if maximum < minimum:
            minimum, maximum = maximum, minimum
        number = max(minimum, min(maximum, number))
        integral = all(
            float(_number_value(property_spec.get(key), number)).is_integer()
            for key in ("min", "max", "step")
            if property_spec.get(key) is not None
        ) and isinstance(default, int) and float(number).is_integer()
        return int(round(number)) if integral else number
    if kind == "combo":
        options = property_spec.get("options") or []
        for option in options:
            if _typed_scalar_equal(value, option["value"]):
                return option["value"]
        return default
    if kind == "color":
        return _coerce_color(value, str(default or "1 1 1"))
    if kind in {"textinput", "file", "directory", "scenetexture", "usershortcut", "unknown"}:
        return "" if value is None else str(value)
    return default


def _decimal_places(value: Any) -> int:
    if isinstance(value, bool) or value is None:
        return 0
    try:
        exponent = Decimal(str(value)).normalize().as_tuple().exponent
    except (InvalidOperation, ValueError):
        return 0
    return max(0, min(8, -exponent))


def _normalize_property(
    name: str, spec: dict, position: int, translations: dict | None = None
) -> dict:
    translations = translations or {}
    kind = _normalize_property_type(spec)
    raw_default = spec.get("value")
    if kind == "bool":
        default: Any = _bool_value(raw_default, False)
    elif kind == "slider":
        number = _number_value(raw_default, 0)
        default = int(number) if isinstance(raw_default, int) and not isinstance(raw_default, bool) else number
    elif kind == "color":
        default = _coerce_color(raw_default)
    elif kind in {"textinput", "file", "directory", "scenetexture", "usershortcut", "unknown"}:
        default = "" if raw_default is None else str(raw_default)
    else:
        default = raw_default
    options = _normalize_combo_options(spec.get("options"), translations) if kind == "combo" else []
    if kind == "combo":
        default = next(
            (option["value"] for option in options if _typed_scalar_equal(raw_default, option["value"])),
            raw_default,
        )
    minimum = _number_value(spec.get("min"), 0)
    maximum = _number_value(spec.get("max"), max(minimum, _number_value(default, 0)))
    raw_step = spec.get("step")
    precision = spec.get("precision")
    if not isinstance(precision, int) or isinstance(precision, bool):
        precision_values = [raw_step] if raw_step is not None else [raw_default, spec.get("min"), spec.get("max")]
        precision = max((_decimal_places(value) for value in precision_values), default=0)
        if spec.get("fraction"):
            precision = max(precision, 2)
    precision = max(0, min(12, precision))
    step = _number_value(raw_step, 10 ** -precision if precision else 1)
    order = _number_value(spec.get("order"), float(position))
    index = spec.get("index") if isinstance(spec.get("index"), int) else position
    return {
        "name": name,
        "type": kind,
        "label": _plain_property_text(_translated_text(spec.get("text"), translations), name),
        "rawText": spec.get("text") if isinstance(spec.get("text"), str) else "",
        "default": default,
        "value": default,
        "editable": kind in EDITABLE_PROPERTY_TYPES and kind != "unknown",
        "runtimeSupported": kind in EDITABLE_PROPERTY_TYPES and kind != "unknown",
        "allowTextEntry": bool(spec.get("editable", False)),
        "condition": spec.get("condition") if isinstance(spec.get("condition"), str) else "",
        "order": order,
        "index": index,
        "min": minimum,
        "max": maximum,
        "step": step if step > 0 else 1,
        "precision": precision,
        "fraction": bool(spec.get("fraction", False)),
        "options": options,
        "mode": str(spec.get("mode", "")),
        "fileType": str(spec.get("fileType", "")),
    }


def normalize_property_overrides(properties: list[dict], overrides: Any) -> dict:
    if not isinstance(overrides, dict):
        return {}
    definitions = {
        item["name"]: item
        for item in properties
        if isinstance(item, dict) and item.get("editable") and isinstance(item.get("name"), str)
    }
    return {
        name: _coerce_property_value(definitions[name], value)
        for name, value in overrides.items()
        if name in definitions
    }


def _native_resource_value(property_spec: dict, value: Any) -> Any:
    if property_spec.get("type") not in {"file", "directory", "scenetexture"} or not isinstance(value, str) or not value:
        return value
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme == "file":
        return str(Path(urllib.parse.unquote(parsed.path)).resolve())
    if parsed.scheme in {"http", "https", "data", "blob"}:
        return value
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = Path(property_spec.get("valueRoot") or ".") / candidate
    try:
        return str(candidate.resolve())
    except ValueError:
        return value


def _web_property_value(property_spec: dict, value: Any) -> Any:
    return _native_resource_value(property_spec, value)


def inspect_wallpaper_project(wallpaper: str | Path, user_overrides: Any = None) -> dict:
    chain = _resolve_project_chain(wallpaper)
    if not chain.get("ok"):
        return chain
    source_path = Path(chain["sourcePath"])
    source_project = chain["sourceProject"]
    kind = chain["kind"]
    source = _project_source(source_path, source_project, kind)
    general = source_project.get("general")
    if not isinstance(general, dict):
        general = {}
    translations, locales = _project_translations(general)
    raw_properties = general.get("properties", {})
    if not isinstance(raw_properties, dict):
        raw_properties = {}
    properties = [
        _normalize_property(str(name), spec, position, translations)
        for position, (name, spec) in enumerate(raw_properties.items())
        if isinstance(spec, dict)
    ]
    properties.sort(key=lambda item: (item["order"], item["index"], item["name"]))
    if kind == "video":
        for item in properties:
            item["runtimeSupported"] = False
            item["editable"] = False

    preset_raw = chain["presetOverrides"]
    preset_known = normalize_property_overrides(properties, preset_raw)
    normalized_user = normalize_property_overrides(properties, user_overrides)
    by_name = {item["name"]: item for item in properties}
    for name, value in preset_known.items():
        by_name[name]["value"] = value
    for name, value in normalized_user.items():
        by_name[name]["value"] = value
    asset_option_cache: dict[tuple, list[dict]] = {}
    for item in properties:
        item["presetValue"] = preset_known.get(item["name"], item["default"])
        item["isOverridden"] = item["name"] in normalized_user
        item["valueRoot"] = (
            chain["originalPath"] if item["isOverridden"]
            else chain["presetOwners"].get(item["name"], chain["sourcePath"])
        )
        item["assetOptions"] = _property_asset_options(
            item,
            [Path(chain["originalPath"]), Path(chain["sourcePath"])],
            cache=asset_option_cache,
        )
        item["webValue"] = _web_property_value(item, item["value"])
        item["sceneValue"] = _native_resource_value(item, item["value"])

    runtime_overrides = dict(preset_raw)
    active_known = set(preset_known) | set(normalized_user)
    for name in active_known:
        item = by_name[name]
        runtime_overrides[name] = item["webValue"] if kind == "web" else item["sceneValue"]
    original_project = chain["originalProject"]
    property_type_counts: dict[str, int] = {}
    for item in properties:
        property_type_counts[item["type"]] = property_type_counts.get(item["type"], 0) + 1
    return {
        "ok": kind in RUNNABLE_PROJECT_TYPES and source is not None,
        "status": "ready" if source is not None else f"{kind} project has no runnable source",
        "title": str(original_project.get("title") or source_project.get("title") or source_path.name),
        "kind": kind,
        "source": str(source) if source else "",
        "projectPath": chain["originalPath"],
        "sourceProjectPath": chain["sourcePath"],
        "sourceProjectId": source_path.name,
        "dependency": chain["dependency"],
        "isPreset": chain["isPreset"],
        "supportsAudioProcessing": bool(general.get("supportsaudioprocessing", False)),
        "supportsVideo": bool(general.get("supportsvideo", False)),
        "videoFlags": general.get("supportsvideoflags") if isinstance(general.get("supportsvideoflags"), int) else 0,
        "locales": locales,
        "properties": properties,
        "propertyCount": len(properties),
        "editablePropertyCount": sum(1 for item in properties if item["editable"]),
        "propertyTypeCounts": dict(sorted(property_type_counts.items())),
        "presetOverrides": preset_raw,
        "runtimeValueRoots": chain["presetOwners"],
        "userOverrides": normalized_user,
        "runtimeOverrides": runtime_overrides,
    }


@jrpc.add_method
def get_wallpaper_project(wallpaper: str, workshop_id: str = "") -> dict:
    user_overrides: dict = {}
    if workshop_id:
        user_overrides = M.read_wallpaper_config(workshop_id).get("property_overrides", {})
    return inspect_wallpaper_project(wallpaper, user_overrides)


PROPERTY_DIRECTORY_EXTENSIONS = {
    "image": {".bmp", ".gif", ".jpeg", ".jpg", ".png", ".tif", ".tiff", ".webp"},
    "video": {".avi", ".m4v", ".mkv", ".mov", ".mp4", ".webm"},
}


def _property_asset_options(
    property_spec: dict,
    roots: list[Path],
    max_files: int = 128,
    cache: dict[tuple, list[dict]] | None = None,
) -> list[dict]:
    """List bundled media choices for one Wallpaper Engine resource property."""
    kind = str(property_spec.get("type") or "").lower()
    if kind not in {"file", "scenetexture"}:
        return []
    requested = str(property_spec.get("fileType") or "").lower()
    if kind == "scenetexture" or requested == "image":
        extensions = PROPERTY_DIRECTORY_EXTENSIONS["image"]
    elif requested == "video":
        extensions = PROPERTY_DIRECTORY_EXTENSIONS["video"]
    else:
        extensions = PROPERTY_DIRECTORY_EXTENSIONS["image"] | PROPERTY_DIRECTORY_EXTENSIONS["video"]

    cache_key = (tuple(str(root.resolve()) for root in roots), tuple(sorted(extensions)), max_files)
    if cache is not None and cache_key in cache:
        return cache[cache_key]

    options: list[dict] = []
    seen: set[str] = set()
    for raw_root in roots:
        root = raw_root.resolve()
        if not root.is_dir():
            continue
        for candidate in sorted(root.rglob("*"), key=lambda item: str(item).casefold()):
            if len(options) >= max_files:
                return options
            if candidate.is_symlink() or not candidate.is_file() or candidate.suffix.lower() not in extensions:
                continue
            relative = candidate.relative_to(root).as_posix()
            if candidate.name.casefold() in {"preview.jpg", "preview.jpeg", "preview.png", "preview.gif", "preview.webp"}:
                continue
            value = str(candidate.resolve())
            if value in seen:
                continue
            seen.add(value)
            options.append({"label": relative, "value": value})
    if cache is not None:
        cache[cache_key] = options
    return options


@jrpc.add_method
def list_property_directory(path: str, file_type: str = "", max_files: int = 512) -> dict:
    try:
        parsed = urllib.parse.urlparse(str(path or ""))
        selected = Path(urllib.parse.unquote(parsed.path) if parsed.scheme == "file" else str(path)).expanduser().resolve()
        if not selected.is_dir():
            return {"ok": False, "files": [], "truncated": False, "error": "Selected directory does not exist"}
        limit = max(1, min(1000, int(max_files)))
        requested = str(file_type or "").lower()
        extensions = PROPERTY_DIRECTORY_EXTENSIONS.get(requested)
        if extensions is None:
            extensions = PROPERTY_DIRECTORY_EXTENSIONS["image"] | PROPERTY_DIRECTORY_EXTENSIONS["video"]
        files = []
        for candidate in sorted(selected.rglob("*"), key=lambda item: str(item).casefold()):
            if candidate.is_symlink() or not candidate.is_file() or candidate.suffix.lower() not in extensions:
                continue
            resolved = candidate.resolve()
            try:
                resolved.relative_to(selected)
            except ValueError:
                continue
            files.append(str(resolved))
            if len(files) > limit:
                break
        return {
            "ok": True,
            "path": str(selected),
            "files": files[:limit],
            "truncated": len(files) > limit,
        }
    except (OSError, TypeError, ValueError) as error:
        return {"ok": False, "files": [], "truncated": False, "error": str(error)}


WORKSHOP_APP_ID = 431960
DEFAULT_WORKSHOP_ROOT = Path("/data/SteamLibrary/steamapps/workshop/content/431960")
WORKSHOP_SORTS = {
    "trend", "textsearch", "mostrecent", "lastupdated", "toprated",
    "mostsubscribed", "mostunique", "totaluniquesubscribers",
}
WORKSHOP_SORT_ALIASES = {
    "mostsubscribed": "totaluniquesubscribers",
    "mostunique": "totaluniquesubscribers",
}
WORKSHOP_KIND_TAGS = {"scene": "Scene", "video": "Video", "web": "Web", "image": "Image"}


def _workshop_id(value: Any) -> str:
    value = str(value or "")
    if not re.fullmatch(r"[0-9]{1,20}", value):
        raise ValueError("Invalid Workshop item identifier")
    return value


def build_workshop_search_url(
    query: str = "", page: int = 1, sort: str = "trend", kind: str = "all"
) -> str:
    try:
        page = int(page)
    except (TypeError, ValueError) as error:
        raise ValueError("Invalid Workshop page") from error
    if page < 1 or page > 1000:
        raise ValueError("Invalid Workshop page")
    sort = str(sort or "trend").lower()
    if sort not in WORKSHOP_SORTS:
        raise ValueError("Invalid Workshop sort")
    kind = str(kind or "all").lower()
    if kind not in {"all", *WORKSHOP_KIND_TAGS}:
        raise ValueError("Invalid Workshop type filter")
    params: list[tuple[str, str | int]] = [
        ("appid", WORKSHOP_APP_ID),
        ("browsesort", WORKSHOP_SORT_ALIASES.get(sort, sort)),
        ("section", "readytouseitems"),
        ("searchtext", str(query or "")[:160]),
        ("p", page),
        ("num_per_page", 30),
        ("days", 7),
        ("l", "english"),
    ]
    if kind != "all":
        params.append(("requiredtags[]", WORKSHOP_KIND_TAGS[kind]))
    return "https://steamcommunity.com/workshop/browse/?" + urllib.parse.urlencode(params)


def _large_workshop_preview(url: str) -> str:
    if not url:
        return ""
    parsed = urllib.parse.urlsplit(url)
    query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    updated = []
    seen = set()
    for key, value in query:
        if key in {"imw", "imh"}:
            value = "512"
            seen.add(key)
        updated.append((key, value))
    for key in ("imw", "imh"):
        if key not in seen:
            updated.append((key, "512"))
    return urllib.parse.urlunsplit(parsed._replace(query=urllib.parse.urlencode(updated)))


class _WorkshopBrowseParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.items: OrderedDict[str, dict] = OrderedDict()
        self.total = 0
        self._anchor_item_id = ""
        self._author_item_id = ""
        self._last_item_id = ""

    @staticmethod
    def _id_from_url(url: str) -> str:
        parsed = urllib.parse.urlsplit(url)
        if "sharedfiles/filedetails" not in parsed.path:
            return ""
        values = urllib.parse.parse_qs(parsed.query).get("id", [])
        return values[0] if values and re.fullmatch(r"[0-9]{1,20}", values[0]) else ""

    def _item(self, workshop_id: str) -> dict:
        return self.items.setdefault(workshop_id, {
            "workshopId": workshop_id,
            "title": "",
            "author": "",
            "preview": "",
            "workshopUrl": f"https://steamcommunity.com/sharedfiles/filedetails/?id={workshop_id}",
        })

    def handle_starttag(self, tag: str, attrs) -> None:
        attributes = dict(attrs)
        if tag == "a":
            href = attributes.get("href", "")
            workshop_id = self._id_from_url(href)
            if workshop_id:
                self._anchor_item_id = workshop_id
                self._author_item_id = ""
                self._last_item_id = workshop_id
                self._item(workshop_id)
            elif self._last_item_id and "myworkshopfiles" in href and f"appid={WORKSHOP_APP_ID}" in href:
                self._anchor_item_id = ""
                self._author_item_id = self._last_item_id
            else:
                self._anchor_item_id = ""
                self._author_item_id = ""
        elif tag == "img" and self._anchor_item_id:
            item = self._item(self._anchor_item_id)
            title = " ".join(str(attributes.get("alt", "")).split())
            preview = str(attributes.get("src", ""))
            if title:
                item["title"] = title[:240]
            if preview.startswith(("https://", "http://")):
                item["preview"] = _large_workshop_preview(preview)

    def handle_endtag(self, tag: str) -> None:
        if tag == "a":
            self._anchor_item_id = ""
            self._author_item_id = ""

    def handle_data(self, data: str) -> None:
        text = " ".join(data.split())
        if not text:
            return
        total_match = re.fullmatch(r"([0-9][0-9., ]*) entries matching filters", text)
        if total_match:
            self.total = int(re.sub(r"[^0-9]", "", total_match.group(1)))
        if self._anchor_item_id:
            self._item(self._anchor_item_id)["title"] = text[:240]
        elif self._author_item_id:
            author = re.sub(r"^By\s+", "", text, flags=re.IGNORECASE).strip()
            if author:
                self._item(self._author_item_id)["author"] = author[:160]


def _workshop_ssr_data(html_text: str) -> dict | None:
    marker = "window.SSR.renderContext=JSON.parse("
    start = html_text.find(marker)
    if start < 0:
        return None
    start += len(marker)
    try:
        encoded, _ = json.JSONDecoder().raw_decode(html_text[start:])
        context = json.loads(encoded) if isinstance(encoded, str) else encoded
        query_data = context.get("queryData", {}) if isinstance(context, dict) else {}
        if isinstance(query_data, str):
            query_data = json.loads(query_data)
    except (TypeError, ValueError, json.JSONDecodeError):
        return None
    queries = query_data.get("queries", []) if isinstance(query_data, dict) else []
    browse = None
    authors: dict[str, dict] = {}
    for query in queries:
        if not isinstance(query, dict):
            continue
        key = query.get("queryKey") or []
        data = (query.get("state") or {}).get("data")
        if not isinstance(key, list) or not isinstance(data, dict):
            continue
        if key and key[0] == "workshop_browse":
            browse = data
        elif len(key) > 1 and key[0] == "PlayerLinkDetails":
            public = data.get("public_data")
            if isinstance(public, dict):
                authors[str(key[1])] = public
    if not isinstance(browse, dict):
        return None
    items = []
    for raw in browse.get("results") or []:
        if not isinstance(raw, dict) or int(raw.get("consumer_appid") or 0) != WORKSHOP_APP_ID:
            continue
        try:
            workshop_id = _workshop_id(raw.get("publishedfileid"))
        except ValueError:
            continue
        creator = str(raw.get("creator") or "")
        author_data = authors.get(creator, {})
        profile_slug = str(author_data.get("profile_url") or "").strip()
        steam_id = str(author_data.get("steamid") or creator).strip()
        author_url = ""
        if profile_slug:
            author_url = "https://steamcommunity.com/id/" + urllib.parse.quote(profile_slug, safe="") + "/"
        elif steam_id.isdigit():
            author_url = f"https://steamcommunity.com/profiles/{steam_id}/"
        tags = [
            str(tag.get("tag")) for tag in raw.get("tags") or []
            if isinstance(tag, dict) and isinstance(tag.get("tag"), str)
        ]
        kind = next((tag.lower() for tag in tags if tag.lower() in WORKSHOP_KIND_TAGS), "unknown")
        preview = str(raw.get("preview_url") or "")
        if not preview.startswith("https://"):
            preview = ""
        items.append({
            "workshopId": workshop_id,
            "title": _plain_property_text(raw.get("title"), f"Workshop {workshop_id}")[:240],
            "kind": kind,
            "author": _optional_plain_text(author_data.get("persona_name"))[:160],
            "authorUrl": author_url,
            "creator": creator,
            "preview": _large_workshop_preview(preview),
            "workshopUrl": f"https://steamcommunity.com/sharedfiles/filedetails/?id={workshop_id}",
            "description": _optional_plain_text(raw.get("short_description"))[:500],
            "tags": tags,
            "sizeBytes": int(raw.get("file_size") or 0),
            "updatedEpoch": int(raw.get("time_updated") or 0),
            "subscriptions": int(raw.get("subscriptions") or raw.get("lifetime_subscriptions") or 0),
            "views": int(raw.get("views") or 0),
            "rating": float(raw.get("star_rating") or 0),
        })
    current_page = int(browse.get("current_page") or 1)
    total_pages = min(1000, int(browse.get("total_pages") or 0))
    return {
        "total": int(browse.get("total_count") or len(items)),
        "currentPage": current_page,
        "totalPages": total_pages,
        "hasMore": current_page < total_pages,
        "items": items,
    }


def parse_workshop_search_html(html_text: str, workshop_root: str | Path = DEFAULT_WORKSHOP_ROOT) -> dict:
    html_text = str(html_text or "")
    structured = _workshop_ssr_data(html_text)
    parser = None
    if structured is None:
        parser = _WorkshopBrowseParser()
        parser.feed(html_text)
        if not parser.items and not re.search(r"[0-9][0-9., ]* entries matching filters", html_text):
            raise ValueError("Steam response did not contain recognizable Workshop results")
        structured = {
            "total": parser.total,
            "currentPage": 1,
            "totalPages": 0,
            "hasMore": False,
            "items": list(parser.items.values()),
        }
    root = Path(workshop_root or DEFAULT_WORKSHOP_ROOT).expanduser().resolve()
    items = []
    for item in structured["items"]:
        workshop_id = item["workshopId"]
        folder = root / workshop_id
        installed = (folder / "project.json").is_file()
        normalized = dict(item)
        normalized.update({
            "title": item["title"] or f"Workshop {workshop_id}",
            "installed": installed,
            "folder": str(folder) if installed else "",
            "online": True,
        })
        items.append(normalized)
    structured["items"] = items
    return structured


@jrpc.add_method
def search_workshop(
    query: str = "", page: int = 1, sort: str = "trend", kind: str = "all",
    workshop_root: str = str(DEFAULT_WORKSHOP_ROOT),
) -> dict:
    try:
        url = build_workshop_search_url(query, page, sort, kind)
        request = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) DcentWallpapers/1.0",
            "Accept-Language": "en-US,en;q=0.9",
        })
        with urllib.request.urlopen(request, timeout=25) as response:
            body = response.read(4_000_001)
        if len(body) > 4_000_000:
            raise ValueError("Workshop response was too large")
        parsed = parse_workshop_search_html(body.decode("utf-8", errors="replace"), workshop_root)
        parsed.update({
            "ok": True,
            "query": str(query or "")[:160],
            "page": int(page),
            "sort": sort,
            "kind": kind,
            "url": url,
            "hasMore": parsed.get("hasMore") if parsed.get("totalPages") else int(page) * 30 < parsed["total"],
            "status": f"Found {parsed['total']:,} Workshop wallpapers",
        })
        return parsed
    except (OSError, ValueError, urllib.error.URLError) as error:
        return {
            "ok": False, "items": [], "total": 0, "page": int(page) if str(page).isdigit() else 1,
            "hasMore": False, "status": "Steam Workshop search failed", "error": str(error),
        }


def _vdf_named_block(text: str, name: str) -> str:
    match = re.search(r'"' + re.escape(name) + r'"\s*\{', text)
    if not match:
        return ""
    start = text.find("{", match.start())
    depth = 0
    quoted = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
    return ""


def _vdf_values(block: str) -> dict[str, str]:
    return dict(re.findall(r'"([^"\\]+)"\s*"([^"\\]*)"', block))


def _workshop_manifest_state(root: Path, workshop_id: str) -> tuple[bool | None, str]:
    manifest_path = root.parent.parent / f"appworkshop_{WORKSHOP_APP_ID}.acf"
    if not manifest_path.is_file():
        return None, "unmanaged"
    try:
        text = manifest_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False, "manifest-unreadable"
    installed_section = _vdf_named_block(text, "WorkshopItemsInstalled")
    details_section = _vdf_named_block(text, "WorkshopItemDetails")
    installed_values = _vdf_values(_vdf_named_block(installed_section, workshop_id))
    detail_values = _vdf_values(_vdf_named_block(details_section, workshop_id))
    installed_manifest = installed_values.get("manifest", "")
    latest_manifest = detail_values.get("latest_manifest") or detail_values.get("manifest", "")
    if installed_manifest and latest_manifest and installed_manifest == latest_manifest:
        return True, "current"
    if installed_manifest or detail_values:
        return False, "updating"
    return False, "remote"


@jrpc.add_method
def workshop_item_status(
    workshop_id: str, workshop_root: str = str(DEFAULT_WORKSHOP_ROOT)
) -> dict:
    try:
        workshop_id = _workshop_id(workshop_id)
        root = Path(workshop_root or DEFAULT_WORKSHOP_ROOT).expanduser().resolve()
        folder = root / workshop_id
        project_present = (folder / "project.json").is_file()
        manifest_current, manifest_state = _workshop_manifest_state(root, workshop_id)
        local_item = local_workshop_item(workshop_id, root) if project_present else {"ok": False}
        runnable = bool(local_item.get("ok"))
        installed = runnable and manifest_current is not False
        if installed:
            install_state = "installed"
        elif project_present or manifest_state == "updating":
            install_state = "downloading"
        else:
            install_state = "remote"
        return {
            "ok": True, "workshopId": workshop_id, "installed": installed,
            "folder": str(folder) if installed else "",
            "installState": install_state,
            "manifestState": manifest_state,
        }
    except ValueError as error:
        return {"ok": False, "installed": False, "error": str(error)}


def local_workshop_item(workshop_id: str, workshop_root: str | Path = DEFAULT_WORKSHOP_ROOT) -> dict:
    workshop_id = _workshop_id(workshop_id)
    root = Path(workshop_root or DEFAULT_WORKSHOP_ROOT).expanduser().resolve()
    folder = root / workshop_id
    manifest = _read_project_json(folder)
    if not manifest:
        return {"ok": False, "installed": False, "workshopId": workshop_id}
    project = inspect_wallpaper_project(folder)
    if not project.get("ok"):
        return {**project, "installed": True, "workshopId": workshop_id}
    preview = ""
    declared_preview = manifest.get("preview")
    if isinstance(declared_preview, str) and declared_preview:
        candidate = (folder / declared_preview).resolve()
        try:
            candidate.relative_to(folder)
        except ValueError:
            candidate = Path()
        if candidate.is_file():
            preview = candidate.as_uri()
    if not preview:
        for name in ("preview.jpg", "preview.png", "preview.gif", "preview.webp"):
            candidate = folder / name
            if candidate.is_file():
                preview = candidate.as_uri()
                break
    kind = project["kind"]
    support = {
        "scene": "Animated scene",
        "video": "Video",
        "web": "Web wallpaper",
        "image": "Image",
    }.get(kind, "Unavailable")
    return {
        "ok": True, "installed": True, "online": False,
        "workshopId": workshop_id,
        "title": project["title"],
        "kind": kind,
        "renderKind": kind,
        "support": support,
        "folder": str(folder),
        "preview": preview,
        "media": project["source"],
        "size": 0,
        "workshopUrl": f"https://steamcommunity.com/sharedfiles/filedetails/?id={workshop_id}",
    }


@jrpc.add_method
def get_local_workshop_item(
    workshop_id: str, workshop_root: str = str(DEFAULT_WORKSHOP_ROOT)
) -> dict:
    try:
        return local_workshop_item(workshop_id, workshop_root or DEFAULT_WORKSHOP_ROOT)
    except (OSError, ValueError) as error:
        return {"ok": False, "installed": False, "error": str(error)}


@jrpc.add_method
def list_local_workshop_items(
    workshop_root: str | Path = DEFAULT_WORKSHOP_ROOT,
) -> dict:
    root = Path(workshop_root or DEFAULT_WORKSHOP_ROOT).expanduser().resolve()
    items = []
    diagnostics = []
    try:
        folders = sorted(
            (folder for folder in root.iterdir() if folder.is_dir() and folder.name.isdigit()),
            key=lambda folder: int(folder.name),
        )
    except OSError as error:
        return {"ok": False, "count": 0, "items": [], "error": str(error)}
    for folder in folders:
        try:
            item = local_workshop_item(folder.name, root)
        except (OSError, ValueError) as error:
            diagnostics.append({"workshopId": folder.name, "error": str(error)})
            continue
        if item.get("ok"):
            items.append(item)
        elif item.get("installed"):
            diagnostics.append({"workshopId": folder.name, "error": item.get("status", "Unsupported project")})
    items.sort(key=lambda item: (item["title"].casefold(), item["workshopId"]))
    return {
        "ok": True, "count": len(items), "items": items,
        "diagnostics": diagnostics, "root": str(root),
    }


@jrpc.add_method
def write_wallpaper_properties(workshop_id: str, wallpaper: str, overrides: Any) -> dict:
    baseline = inspect_wallpaper_project(wallpaper)
    if not baseline.get("ok"):
        return baseline
    normalized = normalize_property_overrides(baseline["properties"], overrides)
    baseline_values = {item["name"]: item["value"] for item in baseline["properties"]}
    compact = {
        name: value
        for name, value in normalized.items()
        if value != baseline_values.get(name)
    }
    if compact:
        M.write_wallpaper_config(workshop_id, {"property_overrides": compact})
    else:
        M.remove_wallpaper_config_keys(workshop_id, {"property_overrides"})
    return inspect_wallpaper_project(wallpaper, compact)


@jrpc.add_method
def reset_wallpaper_properties(workshop_id: str, wallpaper: str) -> dict:
    M.remove_wallpaper_config_keys(workshop_id, {"property_overrides"})
    return inspect_wallpaper_project(wallpaper)


@jrpc.add_method
def get_dir_size(path: str, depth: int) -> int:
    glob_strs: list[str] = (
        ["**/*"]
        if depth <= 0
        else ["/".join(["*" for _ in range(i + 1)]) for i in range(depth)]
    )
    root_directory: Path = Path(path)
    return sum(
        [
            sum(f.stat().st_size for f in root_directory.glob(s) if f.is_file())
            for s in glob_strs
        ]
    )


@jrpc.add_method
def get_folder_list(path: str, _opt: dict = {}) -> Optional[dict]:
    def gen_item(f: Path) -> dict:
        stat: os.stat_result = f.stat()
        return {"name": f.name, "mtime": math.floor(stat.st_mtime)}

    opt: dict = get_folder_list.default_opt.copy()
    opt.update(_opt)
    opt_only_dir = opt["only_dir"]

    def path_filter(p: Path) -> bool:
        return p.is_dir() if opt_only_dir else True

    folder: Optional[Path] = next(
        filter(lambda p: p.is_dir(), [Path(p) for p in [path, *opt["fallbacks"]]]), None
    )
    if folder is None:
        return None
    return {
        "folder": str(folder),
        "items": [gen_item(p) for p in folder.glob("*") if path_filter(p)],
    }
get_folder_list.default_opt = {"only_dir": True, "fallbacks": []}

jrpc.add_method(M.read_wallpaper_config)
jrpc.add_method(M.write_wallpaper_config)
jrpc.add_method(M.reset_wallpaper_config)


MULTISCREEN_CONFIG_KEYS = {
    "WallpaperPath", "PreviewPath", "MediaPath", "WorkshopRoot", "WallpaperType",
    "Scaling", "Muted", "Volume", "Fps", "DisableMouse", "SteamLibraryPath",
    "WallpaperWorkShopId", "WallpaperSource", "BackgroundColor", "DisplayMode",
    "Rotation", "PauseMode", "PauseFilterByScreen", "PauseOnBatPower",
    "PauseBatPercent", "VideoBackend", "MuteAudio", "MouseInput", "Speed",
    "DisableParallax", "DisableParticles", "PropertyOverrides",
    "MultiScreenMode", "VirtualDesktopX", "VirtualDesktopY",
    "VirtualDesktopWidth", "VirtualDesktopHeight",
}


def parse_output_bounds(output: str) -> dict:
    outputs = parse_outputs(output)
    geometries = [(item["x"], item["y"], item["width"], item["height"]) for item in outputs]
    if not geometries:
        return {
            "VirtualDesktopX": 0,
            "VirtualDesktopY": 0,
            "VirtualDesktopWidth": 0,
            "VirtualDesktopHeight": 0,
        }
    minimum_x = min(x for x, _y, _width, _height in geometries)
    minimum_y = min(y for _x, y, _width, _height in geometries)
    maximum_x = max(x + width for x, _y, width, _height in geometries)
    maximum_y = max(y + height for _x, y, _width, height in geometries)
    return {
        "VirtualDesktopX": minimum_x,
        "VirtualDesktopY": minimum_y,
        "VirtualDesktopWidth": maximum_x - minimum_x,
        "VirtualDesktopHeight": maximum_y - minimum_y,
    }


def parse_outputs(output: str) -> list[dict]:
    clean = re.sub(r"\x1b\[[0-9;]*m", "", output)
    parsed = []
    for block in re.split(r"(?=^Output:)", clean, flags=re.MULTILINE):
        name_match = re.search(r"^Output:\s+\d+\s+(\S+)", block, flags=re.MULTILINE)
        geometry_match = re.search(r"Geometry:\s*(-?\d+),(-?\d+)\s+(\d+)x(\d+)", block)
        scale_match = re.search(r"Scale:\s*([0-9]+(?:\.[0-9]+)?)", block)
        if not name_match or not geometry_match:
            continue
        x, y, width, height = map(int, geometry_match.groups())
        parsed.append({
            "index": len(parsed),
            "name": name_match.group(1),
            "x": x,
            "y": y,
            "width": width,
            "height": height,
            "scale": float(scale_match.group(1)) if scale_match else 1.0,
        })
    return parsed


def _bounded_resolution(width: int, height: int) -> tuple[int, int]:
    width = max(1, int(width))
    height = max(1, int(height))
    factor = min(1.0, 7680 / width, 4320 / height, math.sqrt(20_000_000 / (width * height)))
    return max(2, int(width * factor) // 2 * 2), max(2, int(height * factor) // 2 * 2)


def choose_scene_fallback_resolution(outputs: list[dict], mode: str, fps: int = 30) -> tuple[int, int]:
    """Choose enough source pixels while bounding high-frame-rate playback cost."""
    if not outputs:
        return 3840, 2160
    maximum_scale = (
        1.0 if int(fps) > 30
        else max(float(item.get("scale", 1.0)) for item in outputs)
    )
    if mode == "span":
        minimum_x = min(int(item["x"]) for item in outputs)
        minimum_y = min(int(item["y"]) for item in outputs)
        maximum_x = max(int(item["x"]) + int(item["width"]) for item in outputs)
        maximum_y = max(int(item["y"]) + int(item["height"]) for item in outputs)
        width = round((maximum_x - minimum_x) * maximum_scale)
        height = round((maximum_y - minimum_y) * maximum_scale)
    else:
        width = max(round(int(item["width"]) * min(float(item.get("scale", 1.0)), maximum_scale)) for item in outputs)
        height = max(round(int(item["height"]) * min(float(item.get("scale", 1.0)), maximum_scale)) for item in outputs)
    width, height = _bounded_resolution(width, height)
    fps = max(1, min(240, int(fps)))
    if fps > 30:
        maximum_pixels = 250_000_000 / fps
        if width * height > maximum_pixels:
            factor = math.sqrt(maximum_pixels / (width * height))
            width = max(2, int(width * factor) // 2 * 2)
            height = max(2, int(height * factor) // 2 * 2)
    return width, height


def bound_video_decoder_resolution(width: int, height: int) -> tuple[int, int]:
    """Keep H.264 scene fallbacks within NVIDIA's 4096px decoder limit."""
    width = max(2, int(width))
    height = max(2, int(height))
    factor = min(1.0, 4096 / width, 4096 / height)
    return max(2, int(width * factor) // 2 * 2), max(2, int(height * factor) // 2 * 2)


def _property_cli_value(value: Any) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    if value is None:
        return ""
    if isinstance(value, float):
        return format(value, ".15g")
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return str(value)


def _override_mapping(properties: Any) -> dict:
    if isinstance(properties, str):
        try:
            properties = json.loads(properties)
        except json.JSONDecodeError:
            return {}
    if not isinstance(properties, dict):
        return {}
    result = {}
    for raw_name, value in properties.items():
        name = str(raw_name)
        if not name or len(name) > 128 or "=" in name or "\x00" in name or "\n" in name or "\r" in name:
            continue
        if isinstance(value, (str, int, float, bool)) or value is None:
            if isinstance(value, str) and len(value) > 16_384:
                continue
            result[name] = value
    return result


def build_property_cli_args(properties: Any) -> list[str]:
    properties = _override_mapping(properties)
    result: list[str] = []
    for name in sorted(properties):
        if not isinstance(name, str) or not name or "\x00" in name:
            continue
        result.extend(["--set-property", f"{name}={_property_cli_value(properties[name])}"])
    return result


def build_scene_fallback_command(
    renderer: Path,
    wallpaper: Path,
    assets: Path,
    screenshot: Path,
    width: int,
    height: int,
    scaling: str,
    properties: Any = None,
    disable_parallax: bool = False,
    disable_particles: bool = False,
) -> list[str]:
    scaling = scaling if scaling in {"fit", "fill", "stretch"} else "fill"
    return [
        str(renderer),
        "--window", f"-{int(width) + 80}x0x{int(width)}x{int(height)}",
        "--screenshot", str(screenshot),
        "--screenshot-delay", "30",
        "--assets-dir", str(assets),
        "--scaling", scaling,
        "--clamp", "border",
        "--silent",
        "--disable-mouse",
        *(["--disable-parallax"] if disable_parallax else []),
        *(["--disable-particles"] if disable_particles else []),
        *build_property_cli_args(properties),
        str(wallpaper),
    ]


def build_scene_video_renderer_command(
    renderer: Path,
    wallpaper: Path,
    assets: Path,
    width: int,
    height: int,
    scaling: str,
    properties: Any = None,
    disable_parallax: bool = False,
    disable_particles: bool = False,
    fps: int = 30,
) -> list[str]:
    scaling = scaling if scaling in {"fit", "fill", "stretch"} else "fill"
    fps = max(15, min(240, int(fps)))
    return [
        str(renderer),
        "--window", f"-{int(width) + 80}x0x{int(width)}x{int(height)}",
        "--fps", str(fps),
        "--assets-dir", str(assets),
        "--scaling", scaling,
        "--clamp", "border",
        "--silent",
        "--disable-mouse",
        "--no-fullscreen-pause",
        *(["--disable-parallax"] if disable_parallax else []),
        *(["--disable-particles"] if disable_particles else []),
        *build_property_cli_args(properties),
        str(wallpaper),
    ]


def build_scene_video_capture_command(
    ffmpeg: Path,
    display: str,
    window_id: int,
    destination: Path,
    width: int,
    height: int,
    fps: int,
    duration: int,
    encoder: str,
) -> list[str]:
    encoder_options = (
        ["-preset", "p4", "-cq", "21"]
        if encoder == "h264_nvenc"
        else ["-preset", "veryfast", "-crf", "20"]
    )
    return [
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y",
        "-f", "x11grab", "-framerate", str(int(fps)), "-draw_mouse", "0",
        "-window_id", str(int(window_id)),
        "-video_size", f"{int(width)}x{int(height)}",
        "-i", display,
        "-t", str(int(duration)), "-an", "-c:v", encoder,
        *encoder_options,
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        str(destination),
    ]


def scene_loop_overlap(duration: int) -> int:
    duration = max(4, int(duration))
    return max(1, min(3, (duration - 1) // 3))


def build_scene_video_smoothing_command(
    ffmpeg: Path,
    captured: Path,
    destination: Path,
    fps: int,
    encoder: str,
    duration: int,
) -> list[str]:
    fps = max(15, min(240, int(fps)))
    duration = max(4, int(duration))
    overlap = scene_loop_overlap(duration)
    offset = max(1, duration - (overlap * 2))
    cadence = (
        f"minterpolate=fps={fps}:mi_mode=blend"
        if fps > 30 else f"fps={fps}"
    )
    filter_graph = (
        f"[0:v]{cadence},split=2[base][head];"
        f"[base]trim=start={overlap}:end={duration},setpts=PTS-STARTPTS[main];"
        f"[head]trim=start=0:end={overlap},setpts=PTS-STARTPTS[start];"
        f"[main][start]xfade=transition=fade:duration={overlap}:offset={offset},"
        "format=yuv420p[out]"
    )
    encoder_options = (
        ["-preset", "p4", "-cq", "20"]
        if encoder == "h264_nvenc"
        else ["-preset", "veryfast", "-crf", "20"]
    )
    return [
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(captured), "-filter_complex", filter_graph,
        "-map", "[out]", "-fps_mode", "cfr", "-an", "-c:v", encoder,
        *encoder_options, "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        str(destination),
    ]


def normalize_scene_capture_duration(duration: Any) -> int:
    try:
        return max(12, min(180, int(duration)))
    except (TypeError, ValueError):
        return 45


def video_frame_count_is_smooth(frame_count: int, duration: float, fps: int) -> bool:
    try:
        expected = float(duration) * int(fps)
        return int(frame_count) >= max(1, int(expected * 0.9))
    except (TypeError, ValueError):
        return False


def _png_dimensions(path: Path) -> tuple[int, int] | None:
    try:
        with path.open("rb") as stream:
            header = stream.read(24)
        if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        return struct.unpack(">II", header[16:24])
    except OSError:
        return None


def _configuration_assignments(configuration: dict) -> str:
    filtered = {
        key: value
        for key, value in configuration.items()
        if key in MULTISCREEN_CONFIG_KEYS and isinstance(value, (str, int, float, bool))
    }
    return "\n".join(
        f"    desktop.writeConfig({json.dumps(key)}, {json.dumps(value)});"
        for key, value in sorted(filtered.items())
    )


def build_apply_all_script(configuration: dict) -> str:
    assignments = _configuration_assignments(configuration)
    return f'''var items = desktops();
for (var i = 0; i < items.length; ++i) {{
    var desktop = items[i];
    desktop.wallpaperPlugin = "org.dcentwallpapers.plasma";
    desktop.currentConfigGroup = ["Wallpaper", "org.dcentwallpapers.plasma", "General"];
{assignments}
    desktop.reloadConfig();
}}
'''


def build_apply_screen_script(configuration: dict, screen_index: int) -> str:
    screen_index = int(screen_index)
    if screen_index < 0 or screen_index > 31:
        raise ValueError("Invalid target screen")
    assignments = _configuration_assignments(configuration)
    return f'''var items = desktops();
for (var i = 0; i < items.length; ++i) {{
    var desktop = items[i];
    if (desktop.screen === {screen_index}) continue;
    if (desktop.wallpaperPlugin !== "org.dcentwallpapers.plasma") continue;
    desktop.currentConfigGroup = ["Wallpaper", "org.dcentwallpapers.plasma", "General"];
    desktop.writeConfig("MultiScreenMode", "single");
    desktop.writeConfig("VirtualDesktopX", 0);
    desktop.writeConfig("VirtualDesktopY", 0);
    desktop.writeConfig("VirtualDesktopWidth", 0);
    desktop.writeConfig("VirtualDesktopHeight", 0);
    desktop.reloadConfig();
}}
for (var i = 0; i < items.length; ++i) {{
    var desktop = items[i];
    if (desktop.screen !== {screen_index}) continue;
    desktop.wallpaperPlugin = "org.dcentwallpapers.plasma";
    desktop.currentConfigGroup = ["Wallpaper", "org.dcentwallpapers.plasma", "General"];
{assignments}
    desktop.reloadConfig();
}}
'''


def parse_wallpaper_readback(output: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in str(output or "").splitlines():
        if ": " not in line:
            continue
        key, value = line.split(": ", 1)
        result[key.strip()] = value.strip()
    return result


def _readback_string(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def wallpaper_readback_matches(readback: dict, configuration: dict) -> bool:
    if readback.get("wallpaperPlugin") != "org.dcentwallpapers.plasma":
        return False
    required = ("WallpaperSource", "WallpaperType", "WallpaperWorkShopId", "MediaPath", "WallpaperPath")
    for key in required:
        if key in configuration and readback.get(key) != _readback_string(configuration[key]):
            return False
    return True


def read_screen_wallpaper(screen_index: int) -> dict[str, str]:
    try:
        result = subprocess.run(
            ["qdbus", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.wallpaper", str(int(screen_index))],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError, ValueError):
        return {}
    if result.returncode != 0:
        return {}
    return parse_wallpaper_readback(result.stdout)


def resolve_screen_target(screens: list[dict], target: Any) -> dict | None:
    """Resolve KDE's output-name target or a legacy numeric index."""
    text = str(target if target is not None else "")
    named = next((screen for screen in screens if str(screen.get("name", "")) == text), None)
    if named is not None:
        return named
    try:
        index = int(target)
    except (TypeError, ValueError):
        return None
    return next((screen for screen in screens if int(screen.get("index", -1)) == index), None)


def wait_for_wallpaper_readback(screen_indices: list[int], configuration: dict, timeout: float = 3.0) -> tuple[bool, dict[int, dict[str, str]]]:
    deadline = time.monotonic() + max(0.1, timeout)
    latest: dict[int, dict[str, str]] = {}
    while True:
        latest = {index: read_screen_wallpaper(index) for index in screen_indices}
        if latest and all(wallpaper_readback_matches(value, configuration) for value in latest.values()):
            return True, latest
        if time.monotonic() >= deadline:
            return False, latest
        time.sleep(0.1)


@jrpc.add_method
def list_screens() -> list[dict]:
    try:
        result = subprocess.run(
            ["kscreen-doctor", "-o"], capture_output=True, text=True, timeout=5, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return []
    return parse_outputs(result.stdout) if result.returncode == 0 else []


def _list_screens_for_render(job: SceneRenderJob) -> list[dict]:
    try:
        result = run_cancellable_process(
            job, ["kscreen-doctor", "-o"], timeout=5, capture_output=True, text=True
        )
    except SceneRenderCancelled:
        raise
    except (OSError, subprocess.SubprocessError):
        return []
    return parse_outputs(result.stdout) if result.returncode == 0 else []


def _render_scene_fallback(
    wallpaper: str,
    assets: str,
    mode: str = "mirror",
    scaling: str = "fill",
    properties: Any = None,
    disable_parallax: bool = False,
    disable_particles: bool = False,
    _job: SceneRenderJob | None = None,
    cache_only: bool = False,
) -> dict:
    """Render an unsafe native scene to a display-resolution static PNG."""
    job = _job or SceneRenderJob()
    renderer = Path.home() / ".local" / "bin" / "linux-wallpaperengine"
    wallpaper_path = _local_path(wallpaper).resolve()
    assets_path = _local_path(assets).resolve()
    project = inspect_wallpaper_project(wallpaper_path)
    if not project.get("ok") or project.get("kind") != "scene":
        return {"ok": False, "status": "high-resolution fallback requires a packed scene"}
    render_path = Path(project["sourceProjectPath"])
    package_file = _scene_package(render_path, _read_project_json(render_path))
    if package_file is None:
        return {"ok": False, "status": "high-resolution fallback requires a packed scene"}
    runtime_properties = dict(project.get("runtimeOverrides") or {})
    supplied_properties = _override_mapping(properties)
    if supplied_properties:
        runtime_properties.update(supplied_properties)
    if not assets_path.is_dir():
        return {"ok": False, "status": "Wallpaper Engine assets are missing"}
    if not os.access(renderer, os.X_OK):
        return {"ok": False, "status": "fallback renderer is unavailable"}

    width, height = choose_scene_fallback_resolution(_list_screens_for_render(job), mode)
    scaling = scaling if scaling in {"fit", "fill", "stretch"} else "fill"
    scene_stamp = package_file.stat()
    renderer_stamp = renderer.stat()
    cache_token = ":".join([
        "static-v2",
        str(package_file), str(scene_stamp.st_size), str(scene_stamp.st_mtime_ns),
        str(renderer_stamp.st_mtime_ns), mode, scaling, f"{width}x{height}",
        json.dumps(runtime_properties, sort_keys=True, separators=(",", ":"), ensure_ascii=False),
        str(bool(disable_parallax)), str(bool(disable_particles)),
    ])
    digest = hashlib.sha256(cache_token.encode("utf-8")).hexdigest()[:16]
    cache_dir = Path.home() / ".cache" / "dcentwallpapers" / "rendered-fallbacks"
    cache_dir.mkdir(parents=True, exist_ok=True)
    safe_id = wallpaper_path.name if wallpaper_path.name.isdigit() else digest
    destination = cache_dir / f"{safe_id}-{mode}-{width}x{height}-{digest}.png"
    if job.cancelled:
        raise SceneRenderCancelled("scene render cancelled")
    if _png_dimensions(destination) == (width, height):
        return {
            "ok": True, "path": str(destination), "width": width, "height": height,
            "cached": True, "status": f"cached {width}×{height} fallback",
        }

    if cache_only:
        return {"ok": False, "cacheMiss": True, "status": "no cached scene still is ready"}

    temporary = cache_dir / f".{destination.stem}-{os.getpid()}-{time.time_ns()}.png"
    command = build_scene_fallback_command(
        renderer, render_path, assets_path, temporary, width, height, scaling,
        runtime_properties, disable_parallax, disable_particles,
    )
    process = None
    ready = False
    last_size = -1
    stable_checks = 0
    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        job.track(process)
        deadline = time.monotonic() + 75
        while time.monotonic() < deadline:
            if job.cancelled:
                return {"ok": False, "cancelled": True, "status": "scene fallback generation cancelled"}
            dimensions = _png_dimensions(temporary)
            try:
                current_size = temporary.stat().st_size
            except OSError:
                current_size = -1
            if dimensions == (width, height) and current_size > 1024:
                stable_checks = stable_checks + 1 if current_size == last_size else 0
                if stable_checks >= 2:
                    ready = True
                    break
            last_size = current_size
            if process.poll() is not None and dimensions != (width, height):
                break
            time.sleep(0.15)
    except OSError as error:
        return {"ok": False, "status": "fallback renderer failed to start", "error": repr(error)}
    finally:
        if process is not None:
            job.untrack(process)
        if process is not None and process.poll() is None:
            _terminate_process_tree(process)

    if not ready:
        temporary.unlink(missing_ok=True)
        return {"ok": False, "status": "high-resolution fallback render failed"}
    if job.cancelled:
        raise SceneRenderCancelled("scene render cancelled")
    temporary.replace(destination)
    return {
        "ok": True, "path": str(destination), "width": width, "height": height,
        "cached": False, "status": f"rendered {width}×{height} fallback",
    }


@jrpc.add_method
def render_scene_fallback(
    wallpaper: str,
    assets: str,
    mode: str = "mirror",
    scaling: str = "fill",
    properties: Any = None,
    disable_parallax: bool = False,
    disable_particles: bool = False,
    render_id: str = "",
    cache_only: bool = False,
) -> dict:
    job = SCENE_RENDERS.begin(render_id)
    try:
        return _render_scene_fallback(
            wallpaper, assets, mode, scaling, properties,
            disable_parallax, disable_particles, job, cache_only,
        )
    except SceneRenderCancelled:
        return {"ok": False, "cancelled": True, "status": "scene render cancelled"}
    finally:
        SCENE_RENDERS.finish(job.render_id, job)


def _render_scene_video_fallback(
    wallpaper: str,
    assets: str,
    mode: str = "mirror",
    scaling: str = "fill",
    fps: int = 30,
    duration: int = 24,
    properties: Any = None,
    disable_parallax: bool = False,
    disable_particles: bool = False,
    _job: SceneRenderJob | None = None,
    cache_only: bool = False,
) -> dict:
    """Render a blocked native scene into a cached animated MP4 fallback."""
    job = _job or SceneRenderJob()
    renderer = Path.home() / ".local" / "bin" / "linux-wallpaperengine"
    wallpaper_path = _local_path(wallpaper).resolve()
    assets_path = _local_path(assets).resolve()
    project = inspect_wallpaper_project(wallpaper_path)
    if not project.get("ok") or project.get("kind") != "scene":
        return {"ok": False, "status": "animated fallback requires a packed scene"}
    render_path = Path(project["sourceProjectPath"])
    package_file = _scene_package(render_path, _read_project_json(render_path))
    if package_file is None:
        return {"ok": False, "status": "animated fallback requires a packed scene"}
    runtime_properties = dict(project.get("runtimeOverrides") or {})
    supplied_properties = _override_mapping(properties)
    if supplied_properties:
        runtime_properties.update(supplied_properties)
    if not assets_path.is_dir():
        return {"ok": False, "status": "Wallpaper Engine assets are missing"}
    if not os.access(renderer, os.X_OK):
        return {"ok": False, "status": "fallback renderer is unavailable"}

    ffmpeg_value = shutil.which("ffmpeg")
    ffprobe_value = shutil.which("ffprobe")
    xdotool_value = shutil.which("xdotool")
    wmctrl_value = shutil.which("wmctrl")
    display = os.environ.get("DISPLAY", "")
    if not all((ffmpeg_value, ffprobe_value, xdotool_value, wmctrl_value, display)):
        if cache_only:
            return {"ok": False, "cacheMiss": True, "status": "no cached animated scene is ready"}
        return {"ok": False, "status": "animated capture tools or XWayland display are unavailable"}
    ffmpeg = Path(str(ffmpeg_value))
    ffprobe = Path(str(ffprobe_value))
    xdotool = Path(str(xdotool_value))
    wmctrl = Path(str(wmctrl_value))

    try:
        fps = max(15, min(240, int(fps)))
    except (TypeError, ValueError):
        fps = 30
    width, height = bound_video_decoder_resolution(
        *choose_scene_fallback_resolution(_list_screens_for_render(job), mode, fps)
    )
    scaling = scaling if scaling in {"fit", "fill", "stretch"} else "fill"
    duration = normalize_scene_capture_duration(duration)

    scene_stamp = package_file.stat()
    renderer_stamp = renderer.stat()
    cache_token = ":".join([
        "animated-v4", str(package_file), str(scene_stamp.st_size), str(scene_stamp.st_mtime_ns),
        str(renderer_stamp.st_mtime_ns), mode, scaling, f"{width}x{height}", str(fps), str(duration),
        json.dumps(runtime_properties, sort_keys=True, separators=(",", ":"), ensure_ascii=False),
        str(bool(disable_parallax)), str(bool(disable_particles)),
    ])
    digest = hashlib.sha256(cache_token.encode("utf-8")).hexdigest()[:16]
    cache_dir = Path.home() / ".cache" / "dcentwallpapers" / "rendered-fallbacks"
    cache_dir.mkdir(parents=True, exist_ok=True)
    safe_id = wallpaper_path.name if wallpaper_path.name.isdigit() else digest
    destination = cache_dir / f"{safe_id}-{mode}-{width}x{height}-{digest}.mp4"
    poster = destination.with_suffix(".png")

    def inspect_video(path: Path) -> dict | None:
        if not path.is_file() or path.stat().st_size < 100_000:
            return None
        try:
            probe = run_cancellable_process(
                job,
                [
                    str(ffprobe), "-v", "error", "-select_streams", "v:0",
                    "-show_entries", "stream=width,height,nb_frames:format=duration,size",
                    "-of", "json", str(path),
                ],
                timeout=20, capture_output=True, text=True,
            )
        except SceneRenderCancelled:
            raise
        except (OSError, subprocess.SubprocessError):
            return None
        if probe.returncode != 0:
            return None
        try:
            metadata = json.loads(probe.stdout)
            stream = metadata["streams"][0]
            actual_duration = float(metadata["format"]["duration"])
            actual_width = int(stream["width"])
            actual_height = int(stream["height"])
            frame_count = int(stream.get("nb_frames") or 0)
        except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError):
            return None
        minimum_duration = duration - scene_loop_overlap(duration) - 1
        if (actual_width, actual_height) != (width, height) or actual_duration < minimum_duration:
            return None
        if frame_count and not video_frame_count_is_smooth(frame_count, actual_duration, fps):
            return None
        return {"duration": actual_duration, "frames": frame_count}

    if job.cancelled:
        raise SceneRenderCancelled("scene render cancelled")
    metadata = inspect_video(destination)
    if metadata:
        return {
            "ok": True, "kind": "video", "animated": True, "path": str(destination),
            "preview": str(poster) if _png_dimensions(poster) == (width, height) else "",
            "width": width, "height": height, "fps": fps, "duration": metadata["duration"],
            "cached": True, "status": f"cached {width}×{height} animated fallback",
        }

    if cache_only:
        return {"ok": False, "cacheMiss": True, "status": "no cached animated scene is ready"}

    temporary = cache_dir / f".{destination.stem}-{os.getpid()}-{time.time_ns()}.mp4"
    captured_temporary = temporary.with_name(temporary.stem + "-capture.mp4")
    temporary_poster = temporary.with_suffix(".png")
    renderer_process = None
    window_id = None
    encoder = ""
    try:
        renderer_environment = os.environ.copy()
        renderer_environment.pop("WAYLAND_DISPLAY", None)
        renderer_environment["XDG_SESSION_TYPE"] = "x11"
        renderer_process = subprocess.Popen(
            build_scene_video_renderer_command(
                renderer, render_path, assets_path, width, height, scaling,
                runtime_properties, disable_parallax, disable_particles, fps,
            ),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            env=renderer_environment,
        )
        job.track(renderer_process)
        if job.cancelled:
            return {"ok": False, "cancelled": True, "status": "animated fallback generation cancelled"}

        window_deadline = time.monotonic() + 30
        while time.monotonic() < window_deadline:
            if job.cancelled:
                return {"ok": False, "cancelled": True, "status": "animated fallback generation cancelled"}
            if renderer_process.poll() is not None:
                break
            lookup = run_cancellable_process(
                job,
                [str(xdotool), "search", "--pid", str(renderer_process.pid), "--class", "linux-wallpaperengine"],
                timeout=3, capture_output=True, text=True,
            )
            candidates = [line.strip() for line in lookup.stdout.splitlines() if line.strip().isdigit()]
            if candidates:
                window_id = int(candidates[0])
                break
            time.sleep(0.1)
        if window_id is None:
            return {"ok": False, "status": "animated renderer window did not initialize"}

        window_hex = f"0x{window_id:x}"
        run_cancellable_process(
            job,
            [str(wmctrl), "-ir", window_hex, "-b", "add,below,skip_taskbar,skip_pager"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
        )
        moved = run_cancellable_process(
            job,
            [str(wmctrl), "-ir", window_hex, "-e", f"0,-{width + 80},0,{width},{height}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
        )
        if moved.returncode != 0:
            return {"ok": False, "status": "could not hide animated renderer window safely"}

        warmup_deadline = time.monotonic() + 3
        while time.monotonic() < warmup_deadline:
            if job.cancelled:
                return {"ok": False, "cancelled": True, "status": "animated fallback generation cancelled"}
            if renderer_process.poll() is not None:
                return {"ok": False, "status": "animated renderer stopped during warm-up"}
            time.sleep(0.1)

        encoders = run_cancellable_process(
            job, [str(ffmpeg), "-hide_banner", "-encoders"],
            timeout=20, capture_output=True, text=True,
        )
        encoder = "h264_nvenc" if "h264_nvenc" in encoders.stdout else "libx264"
        capture = run_cancellable_process(
            job,
            build_scene_video_capture_command(
                ffmpeg, display, window_id, captured_temporary, width, height, fps, duration, encoder
            ),
            timeout=duration + 120, capture_output=True, text=True,
        )
        if job.cancelled:
            return {"ok": False, "cancelled": True, "status": "animated fallback generation cancelled"}
        if capture.returncode != 0 and encoder == "h264_nvenc":
            captured_temporary.unlink(missing_ok=True)
            encoder = "libx264"
            capture = run_cancellable_process(
                job,
                build_scene_video_capture_command(
                    ffmpeg, display, window_id, captured_temporary, width, height, fps, duration, encoder
                ),
                timeout=duration + 180, capture_output=True, text=True,
            )
        if job.cancelled:
            return {"ok": False, "cancelled": True, "status": "animated fallback generation cancelled"}
        if capture.returncode != 0:
            return {
                "ok": False, "status": "animated scene capture failed",
                "error": (capture.stderr or capture.stdout).strip()[-1000:],
            }

        smoothing = run_cancellable_process(
            job,
            build_scene_video_smoothing_command(
                ffmpeg, captured_temporary, temporary, fps, encoder, duration
            ),
            timeout=duration + 180, capture_output=True, text=True,
        )
        if smoothing.returncode != 0:
            return {
                "ok": False, "status": "animated scene smoothing failed",
                "error": (smoothing.stderr or smoothing.stdout).strip()[-1000:],
            }

        metadata = inspect_video(temporary)
        if not metadata:
            return {"ok": False, "status": "animated scene capture was incomplete"}
        poster_result = run_cancellable_process(
            job,
            [
                str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y", "-ss", "2",
                "-i", str(temporary), "-frames:v", "1", str(temporary_poster),
            ],
            timeout=60, capture_output=True, text=True,
        )
        if poster_result.returncode != 0 or _png_dimensions(temporary_poster) != (width, height):
            temporary_poster.unlink(missing_ok=True)

        if job.cancelled:
            raise SceneRenderCancelled("scene render cancelled")
        temporary.replace(destination)
        if temporary_poster.exists():
            temporary_poster.replace(poster)
        return {
            "ok": True, "kind": "video", "animated": True, "path": str(destination),
            "preview": str(poster) if poster.exists() else "",
            "width": width, "height": height, "fps": fps, "duration": metadata["duration"],
            "encoder": encoder, "cached": False,
            "status": f"rendered {width}×{height} animated fallback",
        }
    except subprocess.TimeoutExpired as error:
        return {"ok": False, "status": "animated fallback generation timed out", "error": repr(error)}
    except OSError as error:
        return {"ok": False, "status": "animated fallback generation failed", "error": repr(error)}
    finally:
        temporary.unlink(missing_ok=True)
        captured_temporary.unlink(missing_ok=True)
        temporary_poster.unlink(missing_ok=True)
        if renderer_process is not None:
            job.untrack(renderer_process)
        if renderer_process is not None and renderer_process.poll() is None:
            _terminate_process_tree(renderer_process)


@jrpc.add_method
def render_scene_video_fallback(
    wallpaper: str,
    assets: str,
    mode: str = "mirror",
    scaling: str = "fill",
    fps: int = 30,
    duration: int = 24,
    properties: Any = None,
    disable_parallax: bool = False,
    disable_particles: bool = False,
    render_id: str = "",
    cache_only: bool = False,
) -> dict:
    job = SCENE_RENDERS.begin(render_id)
    try:
        return _render_scene_video_fallback(
            wallpaper, assets, mode, scaling, fps, duration, properties,
            disable_parallax, disable_particles, job, cache_only,
        )
    except SceneRenderCancelled:
        return {"ok": False, "cancelled": True, "status": "scene render cancelled"}
    finally:
        SCENE_RENDERS.finish(job.render_id, job)


@jrpc.add_method
def apply_to_screen(configuration: dict, screen_target: Any) -> dict:
    screens = list_screens()
    target = resolve_screen_target(screens, screen_target)
    if target is None:
        return {"ok": False, "status": "The selected screen is no longer connected"}
    screen_index = int(target["index"])
    configuration = dict(configuration)
    configuration.update({
        "MultiScreenMode": "single",
        "VirtualDesktopX": 0,
        "VirtualDesktopY": 0,
        "VirtualDesktopWidth": 0,
        "VirtualDesktopHeight": 0,
    })
    try:
        script = build_apply_screen_script(configuration, screen_index)
        result = subprocess.run(
            ["qdbus", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        return {"ok": False, "status": "Per-screen apply failed", "error": repr(error)}
    command_ok = result.returncode == 0 and not result.stdout.strip()
    verified, readback = (False, {})
    if command_ok:
        verified, readback = wait_for_wallpaper_readback([screen_index], configuration)
    return {
        "ok": command_ok and verified,
        "status": f"applied to {target['name']}" if command_ok and verified
                else ("Plasma did not load the selected wallpaper" if command_ok else "Plasma rejected per-screen apply"),
        "screen": target,
        "readback": readback,
        "stderr": result.stderr.strip(),
    }


@jrpc.add_method
def apply_all_screens(configuration: dict) -> dict:
    mode = str(configuration.get("MultiScreenMode", "mirror"))
    if mode == "single":
        return {"ok": True, "status": "current screen only"}
    if mode not in {"mirror", "span"}:
        mode = "mirror"
    configuration = dict(configuration)
    configuration["MultiScreenMode"] = mode
    screens = list_screens()
    screen_indices = [int(screen["index"]) for screen in screens]
    if not screen_indices:
        return {"ok": False, "status": "No connected Plasma screens found"}
    try:
        output = subprocess.run(
            ["kscreen-doctor", "-o"], capture_output=True, text=True, timeout=5, check=False
        )
        if output.returncode == 0:
            configuration.update(parse_output_bounds(output.stdout))
    except (OSError, subprocess.SubprocessError):
        configuration.update(parse_output_bounds(""))

    script = build_apply_all_script(configuration)
    try:
        result = subprocess.run(
            ["qdbus", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return {"ok": False, "status": "Plasma apply failed", "error": repr(error)}
    command_ok = result.returncode == 0 and not result.stdout.strip()
    verified, readback = (False, {})
    if command_ok:
        verified, readback = wait_for_wallpaper_readback(screen_indices, configuration)
    return {
        "ok": command_ok and verified,
        "status": "applied to all screens" if command_ok and verified
                else ("Plasma did not load the wallpaper on every screen" if command_ok else "Plasma rejected multi-screen apply"),
        "readback": readback,
        "stderr": result.stderr.strip(),
    }


LOGIN_CONFIG = Path("/etc/plasmalogin.conf")
LOGIN_WALLPAPER_DIR = Path("/var/lib/plasmalogin/wallpapers")


def build_login_wallpaper_commands(prepared: Path, destination: Path) -> list[list[str]]:
    prepared = prepared.resolve()
    destination = Path(destination)
    if destination.parent != LOGIN_WALLPAPER_DIR or not destination.name.startswith("dcent-login-"):
        raise ValueError("Unsafe login wallpaper destination")
    common = ["/usr/bin/pkexec"]
    return [
        common + ["/usr/bin/install", "-d", "-m", "0755", "-o", "plasmalogin", "-g", "plasmalogin", str(LOGIN_WALLPAPER_DIR)],
        common + ["/usr/bin/install", "-m", "0644", "-o", "plasmalogin", "-g", "plasmalogin", str(prepared), str(destination)],
        common + [
            "/usr/bin/kwriteconfig6", "--file", str(LOGIN_CONFIG),
            "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.image", "--group", "General",
            "--key", "Image", f"file://{destination}",
        ],
        common + [
            "/usr/bin/kwriteconfig6", "--file", str(LOGIN_CONFIG),
            "--group", "Greeter", "--key", "WallpaperPlugin", "org.kde.image",
        ],
    ]


def _prepare_login_preview(preview: str) -> tuple[Path, Path]:
    source = _local_path(preview)
    if not source.is_file():
        raise FileNotFoundError(f"Preview image does not exist: {source}")
    image_tool = shutil.which("magick")
    if not image_tool:
        raise RuntimeError("ImageMagick is required to prepare the login preview")
    fingerprint = hashlib.sha256(f"{source}:{source.stat().st_mtime_ns}:{source.stat().st_size}".encode()).hexdigest()[:16]
    cache_dir = Path.home() / ".cache" / "dcentwallpapers" / "login"
    cache_dir.mkdir(parents=True, exist_ok=True)
    prepared = cache_dir / f"dcent-login-{fingerprint}.jpg"
    if not prepared.exists():
        proc = subprocess.run(
            [image_tool, f"{source}[0]", "-auto-orient", "-strip", "-quality", "92", str(prepared)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if proc.returncode != 0 or not prepared.is_file():
            raise RuntimeError(proc.stderr.strip() or "Could not convert the login preview")
    return prepared, LOGIN_WALLPAPER_DIR / prepared.name


@jrpc.add_method
def set_login_wallpaper(preview: str) -> dict:
    try:
        prepared, destination = _prepare_login_preview(preview)
        backup_dir = Path.home() / ".local" / "share" / "dcentwallpapers" / "backups"
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup = backup_dir / "plasmalogin.conf.before-dcent"
        if LOGIN_CONFIG.is_file() and not backup.exists():
            shutil.copy2(LOGIN_CONFIG, backup)
        for command in build_login_wallpaper_commands(prepared, destination):
            proc = subprocess.run(command, capture_output=True, text=True, timeout=180)
            if proc.returncode != 0:
                return {
                    "ok": False,
                    "error": proc.stderr.strip() or proc.stdout.strip() or "Administrator authorization was cancelled",
                    "backup": str(backup) if backup.exists() else "",
                }
        plugin = subprocess.run(
            ["/usr/bin/kreadconfig6", "--file", str(LOGIN_CONFIG), "--group", "Greeter", "--key", "WallpaperPlugin"],
            capture_output=True, text=True, timeout=10,
        ).stdout.strip()
        image = subprocess.run(
            ["/usr/bin/kreadconfig6", "--file", str(LOGIN_CONFIG), "--group", "Greeter", "--group", "Wallpaper",
             "--group", "org.kde.image", "--group", "General", "--key", "Image"],
            capture_output=True, text=True, timeout=10,
        ).stdout.strip()
        expected = f"file://{destination}"
        return {
            "ok": plugin == "org.kde.image" and image == expected,
            "provider": plugin,
            "image": image,
            "destination": str(destination),
            "backup": str(backup) if backup.exists() else "",
            "restartRequired": True,
        }
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        return {"ok": False, "error": str(error)}


def _local_path(value: str) -> Path:
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme == "file":
        return Path(urllib.parse.unquote(parsed.path))
    return Path(value)


@jrpc.add_method
def preflight_scene(source: str, assets: str) -> dict:
    """Parse a scene in an isolated native process before Plasma loads it."""
    helper = Path(__file__).resolve().parent / "tools" / "dcent-scene-preflight"
    source_path = _local_path(source)
    assets_path = _local_path(assets)
    package = source_path.parent / "scene.pkg"

    try:
        source_stamp = package.stat() if package.is_file() else source_path.stat()
        helper_stamp = helper.stat()
        token = f"{source_path}:{source_stamp.st_size}:{source_stamp.st_mtime_ns}:{helper_stamp.st_mtime_ns}"
        cache_key = hashlib.sha256(token.encode("utf-8")).hexdigest()
    except OSError as error:
        return {"safe": False, "status": "missing source", "error": repr(error)}

    cache_dir = Path.home() / ".cache" / "dcentwallpapers"
    cache_file = cache_dir / "scene-preflight.json"
    cache = {}
    try:
        cache = json.loads(cache_file.read_text())
        if isinstance(cache.get(cache_key), dict):
            result = cache[cache_key].copy()
            result["cached"] = True
            return result
    except (OSError, json.JSONDecodeError, TypeError):
        cache = {}

    if not os.access(helper, os.X_OK):
        return {"safe": False, "status": "validator unavailable"}

    try:
        process = subprocess.run(
            [str(helper), str(source_path), str(assets_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
            check=False,
        )
        safe = process.returncode == 0
        if safe:
            status = "native parser passed"
        elif process.returncode < 0:
            status = f"native parser crashed (signal {-process.returncode})"
        else:
            status = f"native parser failed (code {process.returncode})"
        result = {"safe": safe, "status": status, "returncode": process.returncode, "cached": False}
    except subprocess.TimeoutExpired:
        result = {"safe": False, "status": "native parser timed out", "cached": False}
    except OSError as error:
        result = {"safe": False, "status": "validator launch failed", "error": repr(error), "cached": False}

    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        cache[cache_key] = result
        temporary = cache_file.with_suffix(".tmp")
        temporary.write_text(json.dumps(cache))
        temporary.replace(cache_file)
    except OSError:
        pass
    return result


def _audio_spectrum_from_pcm(pcm: list[float], channels: int = 2, sample_rate: int = 48000) -> list[float]:
    """Convert interleaved PCM into Wallpaper Engine's 64+64 normalized bands."""
    channels = max(1, int(channels))
    frame_count = len(pcm) // channels
    size = 1
    while size * 2 <= frame_count and size < 2048:
        size *= 2
    if size < 64:
        return [0.0] * 128

    def channel_bands(channel: int) -> list[float]:
        values = [
            complex(float(pcm[(frame_count - size + index) * channels + min(channel, channels - 1)])
                    * (0.5 - 0.5 * math.cos(2 * math.pi * index / (size - 1))), 0.0)
            for index in range(size)
        ]
        j = 0
        for i in range(1, size):
            bit = size >> 1
            while j & bit:
                j ^= bit
                bit >>= 1
            j ^= bit
            if i < j:
                values[i], values[j] = values[j], values[i]
        length = 2
        while length <= size:
            root = complex(math.cos(-2 * math.pi / length), math.sin(-2 * math.pi / length))
            for start in range(0, size, length):
                factor = 1 + 0j
                half = length // 2
                for offset in range(half):
                    even = values[start + offset]
                    odd = values[start + offset + half] * factor
                    values[start + offset] = even + odd
                    values[start + offset + half] = even - odd
                    factor *= root
            length *= 2
        max_bin = size // 2
        edges = [max(1, min(max_bin, round(math.exp(math.log(max_bin) * index / 64)))) for index in range(65)]
        bands = []
        for index in range(64):
            first = edges[index]
            last = max(first + 1, edges[index + 1])
            magnitudes = [abs(values[bin_index]) for bin_index in range(first, min(last, max_bin))]
            magnitude = sum(magnitudes) / max(1, len(magnitudes))
            bands.append(max(0.0, min(1.0, magnitude / (size * 0.08))))
        return bands

    return channel_bands(0) + channel_bands(1 if channels > 1 else 0)


class AudioSpectrumCapture:
    def __init__(self):
        self._lock = threading.Lock()
        self._samples = [0.0] * 128
        self._process: subprocess.Popen | None = None
        self._thread: threading.Thread | None = None
        self._stopping = False
        self._error = ""

    def _monitor_source(self) -> str:
        result = subprocess.run(
            ["pactl", "get-default-sink"], capture_output=True, text=True, timeout=2, check=False
        )
        sink = result.stdout.strip()
        return sink + ".monitor" if result.returncode == 0 and sink else ""

    def start(self) -> None:
        if self._process is not None and self._process.poll() is None:
            return
        monitor = self._monitor_source()
        if not monitor:
            self._error = "No PipeWire/PulseAudio monitor source"
            return
        try:
            self._process = subprocess.Popen(
                ["parec", f"--device={monitor}", "--format=float32le", "--rate=48000", "--channels=2"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as error:
            self._error = str(error)
            self._process = None
            return
        self._stopping = False
        self._thread = threading.Thread(target=self._read_loop, name="dcent-audio-spectrum", daemon=True)
        self._thread.start()

    def _read_loop(self) -> None:
        process = self._process
        if process is None or process.stdout is None:
            return
        byte_count = 2048 * 2 * 4
        while not self._stopping:
            data = process.stdout.read(byte_count)
            if len(data) != byte_count:
                break
            pcm = list(struct.unpack("<4096f", data))
            spectrum = _audio_spectrum_from_pcm(pcm, channels=2, sample_rate=48000)
            with self._lock:
                self._samples = spectrum

    def latest(self) -> dict:
        self.start()
        with self._lock:
            samples = list(self._samples)
        active = self._process is not None and self._process.poll() is None
        return {"ok": active, "samples": samples, "status": "capturing system audio" if active else self._error}

    def close(self) -> None:
        self._stopping = True
        process = self._process
        self._process = None
        if process is not None and process.poll() is None:
            _terminate_process_tree(process)


AUDIO_SPECTRUM = AudioSpectrumCapture()


@jrpc.add_method
def audio_spectrum() -> dict:
    return AUDIO_SPECTRUM.latest()


@jrpc.add_method
def delete_wallpaper(path: str, workshopid: str = "") -> dict:
    # Safety: require the target to be an existing directory containing
    # a project.json file so arbitrary paths can't be wiped out.
    try:
        folder: Path = Path(path).resolve()
        if not folder.is_dir():
            return {"ok": False, "error": "not a directory"}
        if not (folder / "project.json").is_file():
            return {"ok": False, "error": "not a wallpaper folder"}
        shutil.rmtree(folder)
        if workshopid:
            M.delete_wallpaper_config(workshopid)
        return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": repr(e)}


async def connect(uri):
    import websockets

    async with websockets.connect(uri) as websocket:
        pending = set()
        send_lock = asyncio.Lock()

        async def respond(message: str) -> None:
            response = await jrpc.handle_async(message)
            async with send_lock:
                await websocket.send(response)

        try:
            while True:
                task = asyncio.create_task(respond(await websocket.recv()))
                pending.add(task)
                task.add_done_callback(pending.discard)
        finally:
            SCENE_RENDERS.cancel_all()
            AUDIO_SPECTRUM.close()
            for task in pending:
                task.cancel()
            if pending:
                await asyncio.gather(*pending, return_exceptions=True)
            jrpc.shutdown()

if __name__ == "__main__":
    import argparse

    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="qml localfile helper"
    )
    parser.add_argument("url", metavar="URL", type=str, help="a websocket url")
    args: dict = vars(parser.parse_args())

    if hasattr(asyncio, "run"):
        asyncio.run(connect(args["url"]))
    else:
        asyncio.get_event_loop().run_until_complete(connect(args["url"]))
