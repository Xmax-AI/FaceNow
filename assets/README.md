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
