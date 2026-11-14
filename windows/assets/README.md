# FaceNow application icon

The Windows application uses the same finished icon as the installed macOS FaceNow 1.0.0 (54)
build: a purple three-dimensional star on a white rounded background, including its existing
transparency and edge treatment.

Source: `/Applications/FaceNow.app/Contents/Resources/AppIcon.icns`.
Source SHA-1: `80a8d4468235f742404037821a1519bc14d17e82`.
The source artwork is `MacOS/XmaxCamera/Shared/AppIcon.icon/Assets/FaceNow.png`.

- `FaceNow.png`: the finished 256×256 RGBA representation extracted from the macOS icon.
- `FaceNow.ico`: Windows icon container with 16, 20, 24, 32, 40, 48, 64, 96, 128, and 256 pixel representations.
  The 32, 128, and 256 pixel images retain the native macOS representations;
  the remaining sizes are downsampled from the finished 256 pixel icon.

The project embeds the ICO into the executable with `ApplicationIcon` and copies it
to `Assets/FaceNow.ico` for `AppWindow.SetIcon`, covering Explorer, window chrome,
and the taskbar. Building Windows does not require access to the Mac project.

## Generation presets

`presets.json` is a product-owned snapshot of macOS FaceNow's
`Modules/FNGeneration/MVVM/Model/GenerationMode.swift` and `GenerationReference.swift`
with names from `Generation.xcstrings` (preset version `20261030`, asset version `32`).
It includes 19 character, 12 clothing, 8 style, and 8 summon presets; the first two
summon entries contain prompts without images. Original and thumbnail paths refer
to the same Playground image. Both regional prompts are stored per preset,
including accessory-specific clothing instructions. The Windows assembly embeds
this file directly. Building and running require neither the SDK demo's preset
list nor macOS sources. Uploaded-image defaults live in `GenerationPrompts.cs`.
