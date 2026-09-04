# Security policy

## Reporting a vulnerability

Please open a private GitHub security advisory for vulnerabilities involving local-file access, command execution, the web-wallpaper sandbox, or native scene parsing. Do not include credentials, private Steam data, SSH keys, or unrelated desktop configuration in reports.

For ordinary rendering failures, use a normal issue and include only the diagnostic fields listed in `docs/TROUBLESHOOTING.md`.

## Native-scene boundary

Wallpaper Engine scenes are untrusted native-renderer inputs. DcentWallpapers runs bounded process-isolated preflight before an input reaches the in-process Plasma scene backend. A successful preflight reduces startup/parser risk but cannot guarantee that a later graphics-driver or native-renderer fault will not affect `plasmashell`.

Do not bypass preflight by manually writing unverified scene paths into Plasma configuration.

## Supported versions

Security fixes are currently applied to the latest `main` branch while the project remains pre-1.0.
