# FaceNow application icon

FaceNow uses the purple icon with two camera frames across macOS and Windows.
The source artwork is [FaceNow.png](../../macos/Shared/AppIcon.icon/Assets/FaceNow.png).

- `FaceNowBrandMark.png` is the original 1024×1024 artwork used in the app.
- `FaceNow.png` is a 256×256 PNG with a rounded tile and transparent margins.
- `FaceNow.ico` contains the same tile at 16, 20, 24, 32, 40, 48, 64, 96, 128, and 256 pixels.

The project embeds the ICO into the executable with `ApplicationIcon` and copies it
to `Assets/FaceNow.ico` for `AppWindow.SetIcon`, covering Explorer, window chrome,
and the taskbar. Building Windows does not require access to the Mac project.

## Generation presets

`presets.json` is a product-owned snapshot of macOS FaceNow's
`Modules/FNGeneration/MVVM/Model/GenerationMode.swift` and `GenerationReference.swift`
with names from `Generation.xcstrings` (preset version `20261030`, asset version `32`).
It includes 12 character, 12 clothing, 8 style, and 8 summon presets; the first two
summon entries contain prompts without images. Original and thumbnail paths refer
to the same Playground image. Both regional prompts are stored per preset,
including accessory-specific clothing instructions. The Windows assembly embeds
this file directly. Building and running require neither the SDK demo's preset
list nor macOS sources. Uploaded-image defaults live in `GenerationPrompts.cs`.
