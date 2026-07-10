# Build notes

The site ships precompiled JSX as `bundle.js`; browsers do not load Babel or
transpile JSX at runtime.

## Source layout

- `main.jsx` — browser entrypoint
- `components/**/*.jsx` — editable React source
- `bundle.js` — minified esbuild output loaded by the page
- `index.html` — static page shell

## Rebuild

From `site/`:

```powershell
npm run build
```

The script invokes `../scripts/build-site-bundle.mjs`, bundles `main.jsx`, and
writes `bundle.js` using the pinned local esbuild dependency. Bump the
`bundle.js?v=...` query in `index.html` whenever a deployed bundle needs a cache
bust. Bump the `styles.css?v=...` query for CSS changes.

## Runtime choices

- Production React UMD builds are vendored under `vendor/`.
- Scripts are deferred so the document parses first.
- Fonts load non-blockingly with a no-script fallback.
- Theme bootstrapping runs in the head before first paint.
- Release metadata is pinned to the current verified private prerelease. A
  public GitHub API fetch would not truthfully discover this private prerelease.
