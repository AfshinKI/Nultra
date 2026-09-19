# Visual direction

Nultra uses a midnight navy canvas, mint highlights, compact rounded cards, system typography, and an uncluttered per-device control sheet. The dashboard prioritizes a two-column switch grid inspired by fancy. Each card has battery/signal, real name/details, and direct power toggle. The detail sheet also offers explicit On and Off actions. Six standard-size demo cards should fit on the iPhone 13 mini without scrolling; more cards remain scrollable. Accessibility text uses one column. Pending operations disable controls, and demo mode is visible on both dashboard and device sheet.

Brand artwork: `Nultra/Assets.xcassets/BrandMark.imageset/BrandMark.png`.
Packaged icons: `Nultra/Assets.xcassets/AppIcon.appiconset/` (including opaque 1024px marketing icon).

Artwork was generated with the built-in image generation tool, then mechanically resized with `sips` for the asset catalog. Final generation prompt:

> Create one production iPhone app icon for a private premium Bluetooth switch controller named Nultra. Square 1024x1024 full bleed opaque dark midnight navy background, no outer rounded-square border, iOS will mask it. Center a striking sculptural luminous mint / seafoam symbol: two thick smooth vertical ceramic rails joined by a diagonal to suggest a minimal N, with the right rail subtly shaped like a physical power switch. Precision industrial design, soft dimensional bevels, restrained mint glow, beautiful shadow, minimal iconic silhouette legible at tiny sizes, perfectly centered with generous 20 percent safe margins. No text, no letters as typography, no phone, no mockup, no extra symbols, no watermark. Premium calm smart-home aesthetic.

Generated output was 1254px square, opaque; packaged icon sizes are 40, 58, 60, 80, 87, 120, 180, and 1024px (120px has two asset entries). This is a native SwiftUI implementation, not a web view. Physical iPhone layout and accessibility checks remain part of hardware acceptance.

The dashboard reserves the top for All Off / All On and compact scan status. A small top-left blue/gray LED marks recent presence on each card. Only verified real names enter the grid; offline cards remain. The hamburger opens the master-password and discovery settings, keeping setup controls off the main dashboard.

Version 0.5 reduces cards to a thin status strip plus one name/bulb row. Signal and battery are icons; connection stages and continuously changing timestamps are absent from cards. The yellow bulb glow indicates on, separately from the blue presence dot. Demo mode is last in Menu, after Shortcuts and developer information.
