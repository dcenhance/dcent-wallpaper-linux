# Changelog

All notable changes are documented here. The project follows [Semantic Versioning](https://semver.org/) after the first stable release.

## [Unreleased]

### Added

- Plasma-owned Wallpaper Engine provider for KDE Plasma 6
- Image, video, web, and native scene backends
- CaptSilver native scene renderer integration
- Process-isolated scene preflight and validated cached fallbacks
- PipeWire/PulseAudio stereo spectrum delivery for scene and web wallpapers
- Per-wallpaper Wallpaper Engine properties and bundled asset selection
- Interactive pointer forwarding for compatible wallpapers
- Per-screen, mirrored, and spanned multi-screen targeting
- Single Configure page with separate wallpaper and provider settings
- Accessibility activation and repeatable Apply behavior

### Fixed

- Preserve the current wallpaper until a replacement produces its first frame
- Keep Apply working after KDE replaces the transient `QScreen` object
- Prevent stale selection results and previews from becoming runtime sources
- Bound fallback generation and NVIDIA decoder output dimensions

## [0.2.0] - 2026-09-04

Initial public source release.
