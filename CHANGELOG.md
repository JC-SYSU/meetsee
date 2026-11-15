# Changelog

## Unreleased

- Rounded surfaces now follow Apple's continuous curvature instead of circular arcs: the search panel, result rows, swatches, settings controls, and keycap boxes.
- SDR displays get a dedicated brighter, more saturated Celadon instead of the unboosted EDR fallback; EDR output is unchanged.
- Porcelain (釉绿) highlight theme: a flat ivory panel with a glaze-green selection, 1pt ink outline, and ink text. The selection lifts with EDR headroom on supported displays; SDR screens use a brighter glaze fallback. The recessed ceramic renderer stays behind the `PorcelainTheme.lite` switch.
- Soft White gradient flipped: the top is dimmer and the bottom is brighter, with the same restrained contrast.
- Graphite is hidden from the theme picker; existing Graphite preferences fall back to Celadon.

## 0.1.0

Initial public release.

- Native macOS launcher with a background menu bar app and a floating search panel.
- Chinese, mixed Chinese/English, and multi-keyword substring matching without Spotlight.
- Whitelist and blacklist: folders, file types, custom extensions, extensionless files, hidden files, keywords, Finder aliases, and symbolic links.
- Application search by localized name, bundle name, English name, and optional Pinyin/initials.
- Pinned items for files, folders, and URLs, with Pinyin and initials.
- Optional Contacts search by full name or full Pinyin, with clean phone-number copy.
- Optional first- and second-level System Settings search.
- Four highlight themes, including native HDR/EDR rendering for Celadon and Soft White.
- Native Liquid Glass on macOS 26, with a vibrancy fallback on macOS 13–15.
- Optional bundled Rust search engine built from lokii-core v0.1.9.
- Incremental FSEvents indexing, persisted cache, and diagnostics.
