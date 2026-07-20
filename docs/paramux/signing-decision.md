# Code-signing decision prep (maintainer action required)

Signing is the single gate blocking WinGet, Scoop, SmartScreen-clean
installs, and the stable channel (see roadmap-1.0.md). This page
collects what the decision needs so it can be made in one sitting.
Nothing here executes without the maintainer's purchase and secrets.

## Options

| Route | Cost (order of magnitude) | SmartScreen reputation | Notes |
| --- | --- | --- | --- |
| OV certificate (file-based) | ~$100-250/yr | Builds slowly with downloads | Simplest CI story; key must live in a secret store |
| OV on hardware token / cloud HSM | ~$250-500/yr | Same as OV | CA policy since 2023 pushes keys off disk; CI needs a signing service |
| EV certificate | ~$300-700/yr | Immediate reputation | Hardware/HSM mandatory; strongest SmartScreen answer |
| Azure Trusted Signing | ~$10/mo | Good; Microsoft-attested | Cheapest ongoing; requires Azure tenant + identity validation; signtool integration is straightforward |

Azure Trusted Signing is the likely fit for a solo-maintainer public
project: low cost, no physical token, CI-friendly.

## What's already in place

- `release.yml` carries the signed-release pipeline (currently defused;
  requires signing secrets + winget/Scoop vars before real semver
  releases will pass).
- `scripts/package-package-managers.ps1` generates WinGet + Scoop
  manifests once a signed `setup.exe` exists.
- The release-copy contract will need its "unsigned" requirement
  flipped the release signing lands.

## The checklist when the maintainer proceeds

1. Choose the route; complete identity validation.
2. Add the signing secrets to the repo (names documented in release.yml).
3. Re-enable release.yml's tag trigger for semver tags.
4. Cut the first signed release; verify Get-AuthenticodeSignature and
   SmartScreen behavior on a clean machine.
5. Publish the Scoop bucket + winget-pkgs PR from the generated
   manifests (distribution.md has the steps).
6. Flip roadmap-1.0.md's signing gate to DONE with the receipts.
