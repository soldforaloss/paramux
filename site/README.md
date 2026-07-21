# Paramux site

This directory is the static marketing payload for Paramux, a native Windows
command center for running coding agents in parallel.

## Source layout

- `index.html` — production page shell and metadata
- `main.jsx` — React entrypoint
- `components/` — editable JSX source
- `styles.css` — shared dark/light visual system
- `bundle.js` — precompiled browser bundle loaded by `index.html`
- `assets/` — Paramux brand assets and favicon
- `404.html`, `app.js` — standalone not-found page and theme helper

## Product truth

Marketing copy must stay aligned with the repository source of truth:

- [README.md](../README.md)
- [docs/paramux/capability-parity.md](../docs/paramux/capability-parity.md)
- [docs/paramux/paramux-prd.md](../docs/paramux/paramux-prd.md)

Current distribution is deliberately narrow: an unsigned Windows x64
portable prerelease `v0.1.11` in `soldforaloss/paramux`. There is no
public WinGet or Scoop package, signed installer, or verified ARM64 release yet.

Ghostty and Winghostty may be named only as technical lineage. Paramux is the
product, executable, configuration directory, and user-facing identity.

## Build and checks

From `site/`:

```powershell
npm run build
npm run doctor
npm run doctor:score
```

`npm run build` uses the repository bundler at
`../scripts/build-site-bundle.mjs` and writes `bundle.js`. Commit source and
generated bundle changes together.

## Runtime shape

The page intentionally stays static: local React production UMD files, a
precompiled bundle, and no runtime JSX compiler. Google Fonts provide
Bricolage Grotesque and JetBrains Mono. Release copy is pinned to the verified
prerelease instead of making a GitHub API request at page load; the pin keeps
the page truthful and reviewable.
