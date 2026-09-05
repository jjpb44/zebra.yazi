# Changelog

All notable changes to zebra.yazi are documented here. Versions follow
[Semantic Versioning](https://semver.org/) once the API stabilises (pre-1.0
builds may include breaking changes between minor versions).

## [Unreleased]

## [0.6.0] - 2026-09-06

- Themeless terminals now get stripes: base falls back to an approximate
  dark/light background chosen by the terminal's light/dark report.
- Added `enabled` option — `false` makes the plugin fully inert, for gating
  per launcher (e.g. desktop entry via environment variable).

## [0.5.0] - 2026-09-03

- Fixed `app:resize` repaint after toggle — toggling is now instant.

## [0.4.0] - 2026-08-31

- Removed the per-pane toggle (`U p`). `U z` is the only chord now.

## [0.3.0] - 2026-08-30

- `on_file` per-file escape hatch — return a style to override the pattern.
- `dirs` per-directory rules with `~` expansion and Lua-pattern matching.

## [0.2.0] - 2026-08-29

- Runtime toggle `U z` with persistence (`~/.local/state/yazi/zebra.state`).
- `dirs` per-directory rules.
- `pane_of()` helper for preview-pane classification.

## [0.1.0] - 2026-08-28

- Initial scaffold.
