# HAmbar

Home Assistant in your Mac menu bar — entities, scripts, and connection status one click away.

- Website: [hambar.info](https://hambar.info)
- macOS 15.0 or later

## Install

```bash
brew tap hipszkij/hambar https://github.com/hipszkij/hambar-homebrew
brew install --cask hambar
```

After installing, open **Settings → Connection** and enter your Home Assistant URL and long-lived access token.

## Download

Latest release: [GitHub Releases](https://github.com/hipszkij/hambar-app/releases)

## Release notes

<!-- release-notes:start -->
### 1.0 — 2026-06-16
- Initial public release
- Developer ID signed and notarized macOS app
- Home Assistant menu bar panel with entities and scripts
<!-- release-notes:end -->

## Pro license

Purchase a lifetime license on the [website](https://hambar.info). Enter the license key in **Settings → Subscription**.

## Releasing (maintainers)

1. Export a signed + notarized `HAmbar.app` to `builds/HAmbar.app`.
2. Edit `.version/notes/<version>.md` (see `.version/next` for the version number).
3. Run:

```bash
./scripts/release.sh
./scripts/push-release.sh
```

Use `./scripts/release.sh --help` and `./scripts/push-release.sh --help` for options.
