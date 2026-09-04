# Contributing

Contributions are welcome for KDE Plasma 6 integration, Wallpaper Engine compatibility, tests, documentation, and renderer safety.

## Before opening a change

1. Search existing issues and pull requests.
2. Keep Plasma as the wallpaper owner—do not add a persistent overlay renderer.
3. Keep Workshop previews separate from runtime sources.
4. Never bypass isolated scene preflight.
5. Do not add credentials, private paths, or generated local catalogs.

## Development checks

```bash
uv run --with pytest pytest -q \
  tests/test_multiscreen.py \
  tests/test_properties.py \
  tests/test_workshop.py
```

On a system with Qt 6 and KDE Frameworks 6:

```bash
QML_XHR_ALLOW_FILE_READ=1 \
QT_QPA_PLATFORM=offscreen \
QT_QUICK_BACKEND=software \
/usr/lib64/qt6/bin/qmltestrunner -input "$PWD/tests/qml" -o -,txt
```

```bash
qmllint-qt6 \
  plasma-plugin/contents/ui/config.qml \
  plasma-plugin/contents/ui/main.qml \
  plasma-plugin/contents/ui/Common.qml \
  plasma-plugin/contents/ui/Pyext.qml \
  plasma-plugin/contents/ui/backend/QtWebView.qml \
  plasma-plugin/contents/ui/backend/QtMultimedia.qml \
  plasma-plugin/contents/ui/backend/Scene.qml
```

## Pull requests

- Keep changes focused.
- Add a regression test for behavior changes.
- Explain the tested desktop, GPU, output layout, and wallpaper type when relevant.
- Include screenshots only when they contain no private data or redistributed Workshop assets.
- Use clear commits; do not force-push over other contributors' work.

## Commit style

Use a short imperative subject, for example:

```text
Fix first-frame handoff for scene backends
Add PipeWire spectrum bridge documentation
```

## Reporting renderer failures

Use `docs/TROUBLESHOOTING.md` and include the Workshop ID, preflight exit status, GPU/driver, Plasma version, and relevant journal lines. Never attach credentials or unrelated configuration.
