# Bako Icon Assets

The approved application icon is the blue box with the pale-blue circular switching mark.
The artwork uses a transparent canvas, an optically centered macOS-style tile, and a
restrained ambient shadow so its visible size matches neighboring Dock icons.
The menu bar variant preserves the complete pale-blue tile, blue box, and
pale-blue switching mark. Its brand colors are intentionally shared by light
and dark appearances rather than being recolored by macOS.

## Xcode assets

`BakoAssets.xcassets` is ready to add to the macOS application target:

- `AppIcon` contains the complete macOS 16–1024 px icon matrix.
- `MenuBarIcon` contains 18 px and 36 px full-color images.

Render the menu bar image in its original colors:

```swift
let image = NSImage(named: "MenuBarIcon")
image?.isTemplate = false
statusItem.button?.image = image
```

The same asset is used in light and dark appearances; the pale-blue tile keeps
the blue mark legible on either menu-bar background.

## Exports

- `Bako-AppIcon-Source.png`: approved transparent master source.
- `Bako-AppIcon-1024.png`: normalized 1024 px application icon.
- `Bako-MenuBar-Color-Source.png`: approved full-color menu bar source.

The `Previews` directory shows the menu bar glyph against representative light and dark backgrounds; previews are not application resources.
