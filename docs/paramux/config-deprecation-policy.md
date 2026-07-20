# Config deprecation policy

The 1.0 roadmap's config-stability gate needs a written contract.
This is it, effective immediately for every option paramux has added
on top of the inherited Ghostty grammar.

## The rules

1. **Renames keep the old key working for two minor releases.** A
   renamed option gains an alias entry; the old key parses, applies,
   and logs one `deprecated` warning naming the replacement. Removal
   earliest two minor versions later, listed in release notes both
   times.
2. **Removals are announced one release ahead.** An option slated for
   removal warns for at least one full minor release before parsing of
   it becomes an error.
3. **Semantics never silently change.** If an option's meaning must
   change (defaults may change with release-note callouts), the new
   behavior gets a new key and rule 1 applies to the old one.
4. **Wire names are frozen.** Attention state tags, the
   `paramux.state:` marker grammar, IPC frame layout, and the
   `paramux.windows.v2` JSON schema only ever gain additive fields.
   Breaking any of these requires a new versioned name
   (`windows.v3`), with the old one served in parallel for two minor
   releases.
5. **Layout/session JSON is additive-only.** New fields default;
   unknown fields are ignored on read (`ignore_unknown_fields` is
   already the parser posture). Files written by newer builds must
   load in the previous minor release.
6. **Keybind defaults may evolve**, but a chord that invoked an action
   keeps invoking something equivalent — replacements land in the
   cheat sheet and release notes.

## Inherited Ghostty options

Upstream-inherited options follow upstream's lifecycle; paramux does
not remove inherited options unilaterally. Windows-specific divergence
is documented in the capability matrix instead.

## Enforcement

- PR template's truthfulness checklist covers copy claims; reviewers
  cite this page for any config change lacking the alias/warning path.
- The gate in roadmap-1.0.md flips to DONE after one full minor
  release ships with zero breaking config changes (candidate: the
  release after this policy lands).
