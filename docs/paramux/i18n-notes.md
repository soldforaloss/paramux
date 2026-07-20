# Localization notes (scaffold)

Paramux ships English-only today. This page maps the string surface so
a localization pass can start without archaeology, and records the
constraints any approach must satisfy.

## Where user-visible strings live

| Surface | Where | Count (rough) | Notes |
| --- | --- | --- | --- |
| Menus + chrome + banners | `src/apprt/win32.zig` (`utf8ToUtf16LeStringLiteral` literals, `setBanner` calls) | ~150 | Comptime UTF-16 literals; menu accelerators embed `\t` |
| Cheat sheet + hints | `help_shortcuts_text`, `currentHintTextW` | ~30 lines | Comptime blocks with `@setEvalBranchQuota` |
| Settings window | `src/apprt/win32_settings.zig` (section labels, row labels) | ~80 | Section enum label switches + `SectionRow.label` |
| Overlay text | `buildOverlayPaintLabelText` / hint / accept / cancel switches | ~30 | One switch arm per overlay mode |
| CLI help + errors | `src/cli/*.zig` doc comments (help gen) + `stderr.print` | large | Help text is generated from doc comments — localizing means localizing the generator input |
| Toast bodies | hook adapters (`contrib/paramux/hooks/`) + `notify` defaults | ~10 | Travel through OSC/IPC as UTF-8 |

## Constraints discovered

- Most chrome strings are **comptime** UTF-16 literals — a runtime
  string table means converting call sites to runtime lookups and
  paying the conversion cost once at startup, not per paint.
- Menu items carry accelerator text (`"...\tCtrl+Alt+F"`); the chord
  part must NOT localize.
- The attention state tags (`working/waiting/done/error`) are protocol
  (marker strings, JSON fields, adapters) — display names can localize,
  wire names cannot.
- Config doc comments generate the reference; localizing them is a
  docs-site problem, not a binary problem.

## Recommended approach (when wanted)

1. Introduce `src/apprt/win32_strings.zig`: one struct of `[:0]const
   u16` fields, default-initialized with the English comptime literals.
2. Convert call sites mechanically (the literal moves, the site reads
   the table) — no behavior change, English-only, zero new allocations.
3. A locale then becomes one alternate initializer compiled in (or a
   parsed file later); accelerator suffixes appended at build.
4. Proof-of-concept locale: de-DE for the ~30 highest-visibility
   strings (menus + chooser + banners).

Nothing here is scheduled; this is the map so step 1 is a mechanical PR.
