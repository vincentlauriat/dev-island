# Brand Assets

This directory contains the Dev Island icon assets for macOS app packaging and internal product surfaces.

Structure:

- `Source/` keeps raw brand source assets that should not be treated as generated runtime output.
- `AppIcon.appiconset/`, `DevIsland.iconset/`, and `DevIsland.icns` are generated packaging assets.
- `Internal/` contains small derived assets for in-app surfaces.

Generation workflow:

- regenerate everything with `python3 scripts/generate_brand_icons.py`
- the script outputs:
  - `AppIcon.appiconset/` for future asset-catalog use
  - `DevIsland.iconset/` and `DevIsland.icns` for manual macOS bundle packaging
  - `Internal/color/` for in-app colored usage
  - `Internal/template/` for monochrome template-style usage
  - `Internal/badge/` for small boxed icon treatments

Current raw source assets:

- `Source/logo.png`: original 1280x1280 logo source image

macOS app icon sizes included:

- `16x16`
- `16x16@2x`
- `32x32`
- `32x32@2x`
- `128x128`
- `128x128@2x`
- `256x256`
- `256x256@2x`
- `512x512`
- `512x512@2x`

Why both formats exist:

- Apple’s asset-catalog workflow for macOS expects explicit icon sizes for the platform.
- Our current dev app bundle is assembled manually by `scripts/launch-dev-app.sh`, so it also needs a bundled `.icns` referenced by `CFBundleIconFile`.

Current design direction:

- shell: full-bleed squircle in `#EDE9FE`, corner radius = size × 0.225, no baked-in shadow
  (macOS supplies its own)
- mark: a pair of round spectacles set into the island pill, in `#2E1065` with the frame cut out in
  the paper tone — two outlined lenses, a bridge, and temples running out toward the pill ends.
  Fork-specific in both shape and palette: upstream ships a "Bar+Dot" island (a status bar with a
  trailing dot) in warm paper `#f1ead9` / near-black `#0d0d0f`.
  The outlines are deliberate — filled discs read as eyes or a power socket, and it is the bridge
  that makes the shape parse as spectacles at all. Judge any edit at 32 px first.

Two things worth knowing before editing anything here:

- **The app icon does not come from `generate_brand_icons.py`.** That script's `SCOUT_PATTERN`
  and `render_app_icon()` are leftovers from an earlier mascot design the shipping icon
  abandoned — `write_app_icons()` reads `app-icon-v6.png` and ignores them. To change the app
  icon, edit `scripts/generate-v6-appicon.swift`, run it, *then* run the Python pipeline to
  redistribute into the iconsets and rebuild the `.icns`.
- **`Internal/` is referenced nowhere in `Sources/`.** Those assets are generated but unused.
