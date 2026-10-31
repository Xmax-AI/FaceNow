using System.Runtime.InteropServices;
using FaceNow.Core.Media;
using FaceNow.Core.Product;

namespace FaceNow.Windows.Media;

/// <summary>Final output canvas owns cropping and readable branding; it never mirrors source pixels.</summary>
internal sealed class FrameCompositor(int width = 1920, int height = 1080)
{
    private byte[]? overlay;
    public unsafe ResultFrame Compose(ResultFrame frame)
    {
        overlay ??= WatermarkRasterizer.Create(width, height, BrandDefinition.GenerationCaption);
        var result = new ResultFrame(width, height, frame.TimestampMicroseconds, frame.SessionId);
        try
        {
            fixed (byte* input = frame.Pixels.Span, output = result.Pixels.Span, artwork = overlay)
                if (FaceNowCompose(input, (uint)frame.Width, (uint)frame.Height, (uint)frame.Stride, output, (uint)width, (uint)height, artwork) != 0)
                    throw new InvalidDataException("Invalid output canvas.");
            return result;
        }
        catch { result.Dispose(); throw; }
    }
    [DllImport("FaceNow.FrameEffects.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern unsafe int FaceNowCompose(byte* source, uint sourceWidth, uint sourceHeight, uint sourceStride,
        byte* output, uint width, uint height, byte* overlay);
}

/// <summary>Rasterizes static white glyph masks once. GDI objects and memory DCs never cross frame boundaries.</summary>
internal static class WatermarkRasterizer
{
    [StructLayout(LayoutKind.Sequential)] private struct Header { public uint Size; public int Width, Height; public ushort Planes, Bits; public uint Compression, ImageSize; public int X, Y; public uint Used, Important; }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("gdi32.dll")] private static extern nint CreateCompatibleDC(nint dc);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(nint dc);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(nint value);
    [DllImport("gdi32.dll")] private static extern nint SelectObject(nint dc, nint value);
    [DllImport("gdi32.dll")] private static extern nint CreateDIBSection(nint dc, ref Header header, uint usage, out nint pixels, nint section, uint offset);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] private static extern nint CreateFontW(int height, int width, int angle, int orientation, int weight, uint italic, uint underline, uint strike, uint charset, uint output, uint clip, uint quality, uint pitch, string family);
    [DllImport("gdi32.dll")] private static extern uint SetTextColor(nint dc, uint color);
    [DllImport("gdi32.dll")] private static extern int SetBkMode(nint dc, int mode);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int DrawTextW(nint dc, string text, int length, ref Rect rectangle, uint format);
    [DllImport("gdi32.dll")] private static extern bool GdiFlush();
    internal static byte[] Create(int width, int height, string caption)
    {
        byte[] pixels = new byte[checked(width * height * 4)];
        double scale = Math.Min(width / 640d, height / 360d); int margin = (int)Math.Round(12 * scale);
        var brand = Glyphs(BrandDefinition.Watermark, (int)Math.Round(11 * scale), 600);
        Stamp(pixels, width, height, brand.Pixels, brand.Width, brand.Height, margin, margin, .8);
        var badge = Glyphs(caption, (int)Math.Round(10 * scale), 400);
        int insetX = (int)Math.Round(6 * scale), insetY = (int)Math.Round(3 * scale);
        int bw = badge.Width + insetX * 2, bh = badge.Height + insetY * 2, left = width - margin - bw, radius = (int)Math.Round(8 * scale);
        for (int y = 0; y < bh; ++y) for (int x = 0; x < bw; ++x)
        {
            double dx = Math.Max(radius - x - .5, Math.Max(0, x + .5 - (bw - radius))), dy = Math.Max(radius - y - .5, Math.Max(0, y + .5 - (bh - radius)));
            if (dx * dx + dy * dy <= radius * radius && left + x >= 0 && margin + y < height)
                pixels[((margin + y) * width + left + x) * 4 + 3] = 89;
        }
        Stamp(pixels, width, height, badge.Pixels, badge.Width, badge.Height, left + insetX, margin + insetY, .65);
        return pixels;
    }
    private static void Stamp(byte[] output, int width, int height, byte[] mask, int mw, int mh, int left, int top, double opacity)
    {
        for (int y = 0; y < mh && top + y < height; ++y) for (int x = 0; x < mw && left + x < width; ++x)
        {
            if (left + x < 0 || top + y < 0) continue;
            int from = (y * mw + x) * 4, at = ((top + y) * width + left + x) * 4;
            int alpha = (int)Math.Round(Math.Max(mask[from], Math.Max(mask[from + 1], mask[from + 2])) * opacity);
            if (alpha == 0) continue;
            int total = alpha + output[at + 3] * (255 - alpha) / 255;
            for (int c = 0; c < 3; ++c) output[at + c] = (byte)((255 * alpha + output[at + c] * output[at + 3] * (255 - alpha) / 255) / total);
            output[at + 3] = (byte)total;
        }
    }
    private static (byte[] Pixels, int Width, int Height) Glyphs(string text, int size, int weight)
    {
        nint dc = CreateCompatibleDC(0), font = CreateFontW(-Math.Max(1, size), 0, 0, 0, weight, 0, 0, 0, 1, 0, 0, 4, 0, "Segoe UI");
        if (dc == 0 || font == 0) { if (dc != 0) DeleteDC(dc); if (font != 0) DeleteObject(font); throw new IOException("Watermark font allocation failed."); }
        nint oldFont = SelectObject(dc, font), bitmap = 0, oldBitmap = 0;
        try
        {
            var bounds = new Rect(); DrawTextW(dc, text, -1, ref bounds, 0x420); // DT_CALCRECT | DT_SINGLELINE
            int width = Math.Max(1, bounds.Right), height = Math.Max(1, bounds.Bottom);
            var header = new Header { Size = (uint)Marshal.SizeOf<Header>(), Width = width, Height = -height, Planes = 1, Bits = 32 };
            bitmap = CreateDIBSection(dc, ref header, 0, out nint memory, 0, 0);
            if (bitmap == 0) throw new IOException("Watermark bitmap allocation failed.");
            oldBitmap = SelectObject(dc, bitmap); byte[] pixels = new byte[width * height * 4]; Marshal.Copy(pixels, 0, memory, pixels.Length);
            SetTextColor(dc, 0xFFFFFF); SetBkMode(dc, 1); bounds = new() { Right = width, Bottom = height };
            DrawTextW(dc, text, -1, ref bounds, 0x120); GdiFlush(); Marshal.Copy(memory, pixels, 0, pixels.Length);
            return (pixels, width, height);
        }
        finally { if (oldBitmap != 0) SelectObject(dc, oldBitmap); if (bitmap != 0) DeleteObject(bitmap); SelectObject(dc, oldFont); DeleteObject(font); DeleteDC(dc); }
    }
}
