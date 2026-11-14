//
//  MainWindow.Verification.NativeCapture.cs
//  FaceNow
//

using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    // RenderTargetBitmap can lay out native text differently when rendering an isolated control at 2x.
    // Capture the composed HWND at its actual DPI for text-position verification.
    private async Task SaveNativeLoginScreenshotAsync(
        string name,
        FrameworkElement target
    )
    {
        string? output = Environment.GetEnvironmentVariable("FACENOW_SMOKE_OUTPUT");
        if (output is null)
            return;
        await Task.Delay(100);
        var window = WinRT.Interop.WindowNative.GetWindowHandle(this);
        if (!LoginWindowCapture.GetWindowRect(window, out var bounds))
            throw new InvalidOperationException("No preview window bounds.");
        var clientOrigin = new LoginWindowCapture.Point();
        if (!LoginWindowCapture.ClientToScreen(window, ref clientOrigin))
            throw new InvalidOperationException("No preview client origin.");
        double dpi = GetDpiForWindow(window) / 96d;
        var origin = target.TransformToVisual(root).TransformPoint(new());
        uint left = (uint)Math.Round(clientOrigin.X - bounds.Left + origin.X * dpi);
        uint top = (uint)Math.Round(clientOrigin.Y - bounds.Top + origin.Y * dpi);
        uint width = (uint)Math.Round(target.ActualWidth * dpi), height = (uint)Math.Round(target.ActualHeight * dpi);
        int fullWidth = bounds.Right - bounds.Left, fullHeight = bounds.Bottom - bounds.Top;
        var info = new LoginWindowCapture.BitmapInfo
        {
            Size = 40,
            Width = fullWidth,
            Height = -fullHeight,
            Planes = 1,
            BitCount = 32
        };
        var dc = LoginWindowCapture.CreateCompatibleDC(IntPtr.Zero);
        if (dc == IntPtr.Zero)
            throw new InvalidOperationException("Could not create a preview capture context.");
        IntPtr bitmap = IntPtr.Zero, previous = IntPtr.Zero;
        byte[] pixels;
        try
        {
            bitmap = LoginWindowCapture.CreateDIBSection(dc, ref info, 0, out var bits, IntPtr.Zero, 0);
            if (bitmap == IntPtr.Zero)
                throw new InvalidOperationException("Could not allocate a preview bitmap.");
            previous = LoginWindowCapture.SelectObject(dc, bitmap);
            if (!LoginWindowCapture.PrintWindow(window, dc, 2))
                throw new InvalidOperationException("Could not capture the composed preview window.");
            pixels = new byte[checked(fullWidth * fullHeight * 4)];
            Marshal.Copy(bits, pixels, 0, pixels.Length);
        }
        finally
        {
            if (previous != IntPtr.Zero)
                LoginWindowCapture.SelectObject(dc, previous);
            if (bitmap != IntPtr.Zero)
                LoginWindowCapture.DeleteObject(bitmap);
            LoginWindowCapture.DeleteDC(dc);
        }
        using var stream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Ignore,
            (uint)fullWidth,
            (uint)fullHeight,
            96,
            96,
            pixels
        );
        encoder.BitmapTransform.Bounds = new()
        {
            X = left,
            Y = top,
            Width = width,
            Height = height
        };
        await encoder.FlushAsync();
        using var reader = new DataReader(stream.GetInputStreamAt(0));
        await reader.LoadAsync((uint)stream.Size);
        byte[] png = new byte[stream.Size];
        reader.ReadBytes(png);
        await File.WriteAllBytesAsync(Path.Combine(output, name + ".png"), png);
    }

    private static class LoginWindowCapture
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct Rect
        {
            internal int Left, Top, Right, Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct Point
        {
            internal int X, Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct BitmapInfo
        {
            internal uint Size; internal int Width, Height; internal ushort Planes, BitCount;
            internal uint Compression, SizeImage; internal int XPelsPerMeter, YPelsPerMeter;
            internal uint ClrUsed, ClrImportant;
        }

        [DllImport("user32.dll")]
        internal static extern bool GetWindowRect(
            IntPtr window,
            out Rect rect
        );

        [DllImport("user32.dll")]
        internal static extern bool ClientToScreen(
            IntPtr window,
            ref Point point
        );

        [DllImport("user32.dll")]
        internal static extern bool PrintWindow(
            IntPtr window,
            IntPtr dc,
            uint flags
        );

        [DllImport("gdi32.dll")]
        internal static extern IntPtr CreateCompatibleDC(
            IntPtr dc
        );

        [DllImport("gdi32.dll")]
        internal static extern IntPtr CreateDIBSection(
            IntPtr dc,
            ref BitmapInfo info,
            uint usage,
            out IntPtr bits,
            IntPtr section,
            uint offset
        );

        [DllImport("gdi32.dll")]
        internal static extern IntPtr SelectObject(
            IntPtr dc,
            IntPtr item
        );

        [DllImport("gdi32.dll")]
        internal static extern bool DeleteObject(
            IntPtr item
        );

        [DllImport("gdi32.dll")]
        internal static extern bool DeleteDC(
            IntPtr dc
        );
    }
}
