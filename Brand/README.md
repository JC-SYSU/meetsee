# Brand assets

## Small signature

The app loads `Signature-light.pdf` and `Signature-dark.pdf` at runtime. The SVG files are editable versions of the same vector paths; they are not rendered by the app. `Tools/MakeSignature.swift` keeps the text, font choices, and layout parameters so the two PDFs can be regenerated.

- This is a small-size vector reconstruction, not a traced bitmap or an exact reproduction of the original font.
- `Meet` / `See` use AvenirNext-UltraLight; `&` uses SnellRoundhand. Glyphs are converted to outlines on the build machine. No font file is distributed, and the app does not require the fonts to be installed.
- The two circles use simplified geometric paths with true circular arcs. They do not carry texture, shadow, or glass effects.
- The production assets have a transparent background and fully opaque colors. The view applies 48% opacity and fade transitions.
- The signature is 136 points wide, aligned to the right edge below the search panel, 14 points above the bottom. It uses the window's existing transparent margin, so it does not change the glass outline or input position.
- It appears only when the input is empty and no scan is running. It is click-through and excluded from the accessibility reading order.
- Light and dark assets follow the app's effective appearance. Reduce Motion switches visibility without animation.

Regenerate from the source directory:

```bash
swift Tools/MakeSignature.swift Brand
```

Native PDF support: <https://developer.apple.com/documentation/appkit/nspdfimagerep>

## About brand composition

- The General settings page uses `AboutBrand-light.pdf` / `AboutBrand-dark.pdf`, following the effective appearance. The canvas is 520×160 points with a transparent background.
- The two-line bilingual composition is a reconstruction, not an exact copy of the reference artwork. Chinese uses STSongti-SC-Bold, English uses AvenirNext-Regular, and `&` uses SnellRoundhand. Text is converted to paths.
- The circles reuse the transparent foreground from `BrandMark.png`; the PDF/SVG is therefore vector text plus a bitmap mark, not fully vector.
- `&` is 30 points tall (adjacent English text is 28) and uses a static sage-green satin gradient. Light and dark versions are separate assets.
- The mark is centered proportionally inside the existing brand area and does not move the version text below it.
- The accessibility label includes the name and tagline. The view is click-through.

Regenerate:

```bash
swift Tools/MakeAboutBrand.swift Brand
```
