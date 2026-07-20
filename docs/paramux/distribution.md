# Distribution runbook

Where paramux installs come from today, and the exact path to WinGet /
Scoop / ARM64 when the prerequisites land. Hosting decisions here are
deliberately manual (maintainer-only) — see the project guardrails.

## Today (shipping)

- **x64 portable ZIP** on every GitHub release (`paramux-<ver>-windows-x64-portable.zip` + `SHA256SUMS-windows-x64.txt`), self-updating via `paramux update` since `v0.1.0-paramux.7`.
- Release train: `scripts/package-windows.ps1 -Version <ver> -Architecture x64 -SkipInstaller`.

## ARM64 (ready to attach)

The `Windows ARM64` workflow builds, packages, and smoke-tests a native
ARM64 portable ZIP on every push, and can produce a **versioned,
downloadable artifact** on demand:

```powershell
gh workflow run windows-arm64.yml -R soldforaloss/paramux -f version=<ver> --ref paramux
# wait for the run, then:
gh run download <run-id> -R soldforaloss/paramux -n paramux-<ver>-windows-arm64
gh release upload v<ver> -R soldforaloss/paramux paramux-<ver>-windows-arm64-portable.zip SHA256SUMS-windows-arm64.txt
```

First release to carry ARM64 should update README/PACKAGING copy (the
release-copy contract pins the x64-only wording).

## WinGet + Scoop (blocked on signing — by design)

`scripts/package-package-managers.ps1 -Version <ver>` generates both
manifests but **requires the signed installer**
(`paramux-<ver>-windows-x64-setup.exe`); the unsigned portable-only
prerelease intentionally does not qualify. When code-signing lands:

1. Build with the installer (`package-windows.ps1` without `-SkipInstaller`, signing configured).
2. Run `package-package-managers.ps1 -Version <ver>` → `dist/artifacts/.../winget/` + `scoop/`.
3. **Scoop**: create `soldforaloss/scoop-paramux`, commit the generated `paramux.json` bucket entry (maintainer action).
4. **WinGet**: fork `microsoft/winget-pkgs`, add the generated manifests under `manifests/s/soldforaloss/paramux/<ver>/`, open the PR (maintainer action).

Until then, the portable ZIP is the truthful install path and this page
is the receipt for why.
