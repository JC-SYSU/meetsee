# Search behavior

This document describes the behavior a user sees. It is the English reference for the application's search rules, filters, ranking, and settings.

## Search scope

Meet&See searches file and folder names, application names, and paths. It does not search file contents.

The whitelist is enabled by default on new installs. It contains:

- **Search roots.** `/Applications`, `/System/Applications`, and `~/Applications` by default. Users can add or remove folders in Settings.
- **File types.** Applications, folders, documents, images, audio, video, code/configuration, archives/disk images, and other. Selecting "All types" folds the individual type controls.
- **Custom extensions.** Extra extensions to include, one per line.
- **Extensionless files.** Off by default. When off, files without an extension are excluded.
- **Hidden files.** Off by default. This is a separate preference and remains in effect when the whitelist is disabled.

When the whitelist is disabled, the search root becomes `~/` and file-type restrictions are not applied. Hidden-file handling still follows its own preference.

The blacklist is disabled by default. It supports:

- **Folders.** A folder excludes its whole subtree.
- **Extensions.** Files with a matching extension are excluded.
- **Name keywords.** Case-, width-, and diacritic-insensitive substring matching against the item name and application aliases. Keywords do not match parent paths or file contents.
- **Finder aliases.** Excluded by attribute, not by extension.
- **Symbolic links.** Excluded by attribute. This also excludes system entry points such as `/Applications/Safari.app`, which is a symbolic link on current macOS versions. The settings UI warns about this.

The blacklist takes precedence over the whitelist. Explicitly opened pinned items do not bypass an enabled blacklist or macOS permissions.

## Matching

- Matching is substring-based. A query does not need to align with word boundaries.
- Case, full-width/half-width forms, and diacritics are ignored.
- Multiple keywords are combined with AND. Their order does not matter; every keyword must match.
- The default field is the item name. "Match full path" extends matching to the complete path.
- Ranking prefers an exact name, then a name prefix, then a substring match. Items at the same rank are sorted by name or modification time.
- Applications match the system-localized display name, the bundle name, and the English name. For example, both `字体册` and `Font Book` find Font Book.
- Pinyin and initials are generated for applications and pinned items. They are not applied to ordinary files or folders. Pinyin matching starts at two characters to avoid noisy single-letter results.
- Full-width punctuation, mixed Chinese/English text, and keyword reordering are supported.

## Ranking and limits

The result order is:

1. Pinned target matched by the query.
2. Matched applications, if "Applications first" is enabled.
3. Other results, in normal match order.

Pinned targets always rank first, even when "Applications first" is enabled. A pinned target is de-duplicated if it also appears in normal results.

The candidate limit can be 5, 10, 20, 30, or 50. The status line shows the total number of matches before truncation. The visible row count (3–8) controls the panel height; it does not limit the number of results.

## Keyboard

| Shortcut | Action |
|---|---|
| `Command-Space` | Show or hide the panel |
| `Up` / `Down` | Select a result |
| `Return` | Open with the default application |
| `Command-Return` | Reveal in Finder |
| `Command-I` | Open the native Finder info window |
| `Command-Shift-C` | Copy the full path |
| `Command-R` | Refresh the index |
| `Command-1` … `Command-N` | Open the Nth result; numbering is fixed to the result list, not the scroll position |
| `Escape` | Hide the panel |
| `Command-,` | Open settings |
| `Command-Q` | Quit |

The hotkey is configurable in Settings. `Command-Space` may conflict with Spotlight; the app reports registration failures.

## Settings pages

- **General.** Launch at login, login-item status, version, and a Full Disk Access shortcut.
- **Search Scope.** Whitelist, blacklist, and other sources (Contacts).
- **Search Behavior.** Name/path matching, result ordering, candidate limit, application priority, automatic file watching, system-settings search, and the file-search engine.
- **Diagnostics.** Explains why a selected path is or is not searchable.
- **Interaction.** Hotkey and candidate shortcuts.
- **Appearance.** Highlight theme, theme font, glass tint, window width, visible rows, and scan animation.

Launch at login uses `SMAppService.mainApp` on macOS 13+. The switch reflects the system state and takes effect immediately; it is not part of the settings draft.

## Contacts

Contacts search is optional and off by default. It appears under **Search Scope → Whitelist → Other sources**.

- A contact appears only when the query exactly matches the full name or the full Pinyin. Prefixes, fragments, and initials do not match.
- Each phone number is a separate candidate row. The app does not guess a "default" number.
- `Command-C` copies the selected number as digits only: no spaces, punctuation, or trailing newline. An explicit `+86` or `0086` prefix is removed. Extensions are not concatenated into the main number.
- If text is selected in the search field, `Command-C` copies the text instead.
- Contacts are read into memory when enabled and are not persisted. Revoking permission or disabling the feature clears the in-memory data.
- Contacts permission is independent of Full Disk Access.

## System Settings search

When enabled, first- and second-level System Settings pages appear alongside file results. Enter opens the page; it does not change any setting. Results are not files, so Finder-specific actions are not offered.

The page list is a verified local catalog, not a full-text index of every System Settings control. Deep pages and individual switches are out of scope.

## Indexing

### Native engine

- The native engine scans the configured roots and keeps the name index in memory.
- The index is persisted to a local cache. On launch, the cached snapshot is loaded first and a background calibration checks for changes.
- FSEvents watchers apply incremental updates. File creation, rename, deletion, and changes made while the app was not running are reconciled.
- Hidden directories and excluded directories are filtered before they trigger a rescan.
- A daily full calibration runs when automatic watching is enabled. A manual refresh forces a rebuild.
- The cache contains names, paths, types, and timestamps. It does not contain file contents.

### Bundled engine

The optional bundled engine runs as a separate headless helper process and streams status and search results over a private pipe. It maintains its own index and cache under `~/Library/Application Support/QuickFind/LokiiEngine`.

- Switching engines is exclusive: the inactive engine's indexer is paused.
- The helper reports initialization, replay, calibration, rebuild, incremental, ready, and failure states.
- A query returns at most 5,000 raw matches. The Swift layer applies the same whitelist, blacklist, type, ranking, pinning, contacts, and system-settings rules.
- The native engine remains the reference for matching behavior. The two engines can differ on edge cases and on queries with more than 5,000 raw matches.

## Diagnostics

The Diagnostics page answers "why is this file not in my results?" for a selected path. It reports:

- Whether the path exists and is readable.
- Whether it is inside a search root.
- Whether a blacklist rule, file-type rule, hidden-file rule, alias rule, or symlink rule excludes it.
- Whether it is present in the current index.
- Whether the candidate limit truncated it.

Diagnostics reads the saved settings and does not modify rules or permissions.

## Known limitations

- File contents are not searched.
- Spotlight and Alfred settings are not modified.
- Cloud placeholders may not be searchable until macOS materializes them.
- Network volumes use a slower rescan policy and are not guaranteed to be fresh.
- The bundled engine's 5,000-item prefetch is a hard per-query cap, not a full result set.
- Intel Macs are not covered by the published arm64 build.
- Liquid Glass requires macOS 26 or later; older systems use native vibrancy.
