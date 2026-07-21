# Accessibility verification checklist (hardware)

The UIA surface is built and unit-tested headless; screen-reader FEEL
needs a human at real hardware. This is the maintainer checklist for
a Narrator pass — run it once per release that touches `win32_uia/`.

Setup: `Win+Ctrl+Enter` toggles Narrator. Run a pane with real output
(e.g. `git log` then a long `type` of a file). NVDA works too; note
which reader you used.

## Window + fleet summary

- [ ] Focus paramux: Narrator announces the window title.
- [ ] Narrator's element help (`Narrator+0` on the window) reads the
      fleet summary ("N waiting, N done ... panes in N workspaces").

## TextPattern basics

- [ ] Continuous read (`Narrator+Ctrl+R`) reads the pane's text, not
      just the title.
- [ ] Line navigation (`Narrator+L` / arrow modes) steps line by line
      and matches what's on screen.
- [ ] Word navigation steps ink-run by ink-run and skips blank lines
      in one step (our Word = ink + trailing blanks).
- [ ] "Read current page" covers roughly the visible screen, not all
      scrollback (Page = viewport).

## Live behavior

- [ ] With Narrator attached, run a command that prints slowly
      (`ping -n 10 127.0.0.1`): re-reads track new output within a few
      seconds (TextChanged heartbeat).
- [ ] Trigger `paramux notify --state=done "finished"` in the pane:
      the re-read happens promptly (attention-transition raise).
- [ ] Narrator's highlight rectangle lands on the announced line
      (line-granular bounding rects; wide glyphs may be off by cells —
      note severity if so).

## Known approximations (do not file as bugs)

- Wide glyphs (CJK/emoji) measure their true cells since v0.1.13;
  line-end widths use a codepoint-range heuristic since v0.1.14, so
  only exotic width cases (ambiguous-width ranges) can be off.
- Format/Paragraph units behave as Line.
- Selection is reported unsupported; Narrator can read but not select.

Record results in the release's vault note: reader used, pass/fail
per box, and anything surprising verbatim.
