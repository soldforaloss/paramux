# Windows 11 snap layouts (design — scoping only)

Two distinct integrations get conflated; paramux wants both, in order:

1. **Behave well IN snap layouts** (window-level): hovering the
   maximize button shows Windows' zone flyout and paramux snaps like
   any native window. This already works — the host is a normal
   top-level window. Verify + add a capability-matrix line: done when
   tested on Win11 22H2+.
2. **Offer PANE arrangements in the zones flyout** (app-level): apps
   cannot extend the OS flyout; the honest equivalent is our own
   "Arrange" affordance. The Split Ratio menu + layout slots +
   `.paramux/layout` already cover arrangement; the remaining idea is
   a hover flyout on the maximize/zoom area offering 2-col / 2x2 /
   main+side one-click applies (apply_layout under the hood). Small,
   real, post-v0.1.11.

No OS API exists for third-party zone providers (PowerToys FancyZones
ships its own overlay for the same reason). Anything claiming
deeper integration should be treated as unverifiable until Microsoft
documents one.
