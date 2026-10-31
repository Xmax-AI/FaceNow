using System.Runtime.InteropServices.WindowsRuntime;
using FaceNow.Core.Media;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Xmax.SDK;

namespace FaceNow.App.Controls;

/// <summary>Consumes one owned processed-frame mailbox. Only image pixels are mirrored, never overlays.</summary>
internal sealed class ResultVideoView : Grid
{
    internal static readonly DependencyProperty VideoSourceProperty = DependencyProperty.Register(nameof(VideoSource), typeof(ResultFrameSource), typeof(ResultVideoView), new PropertyMetadata(null, (owner, _) => ((ResultVideoView)owner).Reset()));
    public ResultFrameSource? VideoSource { get => (ResultFrameSource?)GetValue(VideoSourceProperty); set => SetValue(VideoSourceProperty, value); }
    public VideoContentMode ContentMode { get; set; } = VideoContentMode.Fill;
    private readonly Image image = new() { Stretch = Stretch.UniformToFill, HorizontalAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch,
        RenderTransformOrigin = new(.5, .5), RenderTransform = new ScaleTransform { ScaleX = -1 } };
    private WriteableBitmap? bitmap;
    private Stream? pixels;
    internal long PresentedFrameCount { get; private set; }
    internal long LastPresentedTimestampMicroseconds { get; private set; }
    internal uint VideoWidth { get; private set; }
    internal uint VideoHeight { get; private set; }
    internal event Action<Exception>? PlaybackFailed;
    internal ResultVideoView()
    {
        Background = Theme.Brush("#000000"); Children.Add(image);
        Loaded += (_, _) => { CompositionTarget.Rendering -= Render; CompositionTarget.Rendering += Render; };
        Unloaded += (_, _) => { CompositionTarget.Rendering -= Render; pixels?.Dispose(); pixels = null; bitmap = null; image.Source = null; };
    }
    private void Reset()
    { pixels?.Dispose(); pixels = null; bitmap = null; image.Source = null; VideoWidth = VideoHeight = 0; PresentedFrameCount = 0; }
    private void Render(object? sender, object e)
    {
        using var frame = VideoSource?.TryAcquireFrame(); if (frame is null) return;
        try
        {
            if (bitmap is null || bitmap.PixelWidth != frame.Width || bitmap.PixelHeight != frame.Height)
            { pixels?.Dispose(); bitmap = new(frame.Width, frame.Height); pixels = bitmap.PixelBuffer.AsStream(); image.Source = bitmap; }
            pixels!.Position = 0; pixels.Write(frame.Pixels.Span); bitmap.Invalidate();
            image.Stretch = ContentMode == VideoContentMode.Fill ? Stretch.UniformToFill : Stretch.Uniform;
            ++PresentedFrameCount; VideoWidth = (uint)frame.Width; VideoHeight = (uint)frame.Height; LastPresentedTimestampMicroseconds = frame.TimestampMicroseconds;
        }
        catch (Exception failure) { PlaybackFailed?.Invoke(failure); }
    }
}
