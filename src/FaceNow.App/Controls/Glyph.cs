// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;

namespace FaceNow.App.Controls;

internal sealed class Glyph : Grid
{
    private readonly Canvas canvas = new() { Width = 24, Height = 24 };
    private readonly Viewbox viewbox = new();
    private Canvas? artworkFrame;
    private double artworkSize;
    public static readonly DependencyProperty KindProperty = DependencyProperty.Register(nameof(Kind), typeof(string), typeof(Glyph), new PropertyMetadata("", Changed));
    public static readonly DependencyProperty ForegroundProperty = DependencyProperty.Register(nameof(Foreground), typeof(Brush), typeof(Glyph), new PropertyMetadata(null, Changed));
    public string Kind { get => (string)GetValue(KindProperty); set => SetValue(KindProperty, value); }
    public Brush Foreground { get => (Brush)GetValue(ForegroundProperty); set => SetValue(ForegroundProperty, value); }
    private const string MicrophonePath = "M9,5 Q9,2 12,2 Q15,2 15,5 L15,11 Q15,14 12,14 Q9,14 9,11 Z M5,10 L5,12 C5,21 19,21 19,12 L19,10 M12,19 L12,22 M8,22 L16,22";
    private static readonly Dictionary<string, string> Paths = new()
    {
        ["camera"] = "M5,6 L13,6 Q16,6 16,9 L16,15 Q16,18 13,18 L5,18 Q2,18 2,15 L2,9 Q2,6 5,6 M16,10 L22,6.5 L22,17.5 L16,14",
        ["display"] = "M4,3 L20,3 Q22,3 22,5 L22,15 Q22,17 20,17 L4,17 Q2,17 2,15 L2,5 Q2,3 4,3 Z M12,17 L12,21 M8,21 L16,21",
        ["microphone"] = MicrophonePath,
        ["microphoneOff"] = MicrophonePath + " M3,3 L21,21",
        ["key"] = "M11.4,11.6 L21,2 M15.5,7.5 L18.5,10.5 L22,7 L19,4",
        ["chevron"] = "M6,9 L12,15 L18,9",
        ["statistics"] = "M4,20 L4,11 M12,20 L12,4 M20,20 L20,14",
        ["volume"] = "M11,5 L5,9 L2,9 L2,15 L5,15 L11,19 Z M15,8 C19,10 19,14 15,16 M18,5 C24,9 24,15 18,19",
        ["muted"] = "M11,5 L5,9 L2,9 L2,15 L5,15 L11,19 Z M16,9 L22,15 M22,9 L16,15",
        ["plus"] = "M12,4 L12,20 M4,12 L20,12",
        ["arrow"] = "M4,12 L20,12 M14,6 L20,12 L14,18",
        ["close"] = "M6,6 L18,18 M18,6 L6,18",
        ["warning"] = "M12,7 L12,13 M12,16 L12,17",
        ["warningTriangle"] = "F0 M10.3,3.2 Q12,0.3 13.7,3.2 L23,19.3 Q24.5,22 21.4,22 L2.6,22 Q-0.5,22 1,19.3 Z M11,7 L13,7 L13,14 L11,14 Z M11,17 L13,17 L13,19 L11,19 Z",
        // Render social logos as filled paths.
        ["globe"] = "M2,12 L22,12 M12,2 C17.3,7 17.3,17 12,22 C6.7,17 6.7,7 12,2",
        ["socialX"] = "F0 M18.244,2.25 L21.552,2.25 L14.325,10.51 L22.827,21.75 L16.17,21.75 L10.956,14.933 L4.99,21.75 L1.68,21.75 L9.41,12.915 L1.254,2.25 L8.08,2.25 L12.793,8.481 Z M17.083,19.77 L18.916,19.77 L6.95,4.126 L5.117,4.126 Z",
        ["wechat"] = "F0 M9.3,4 C5.6,4 2.6,6.6 2.6,9.9 C2.6,11.8 3.6,13.4 5.2,14.5 L4.5,16.7 L6.9,15.5 C7.6,15.7 8.4,15.8 9.3,15.8 L9.8,15.8 C9.7,15.4 9.6,14.9 9.6,14.5 C9.6,11.4 12.5,8.9 16,8.9 L16.3,8.9 C15.7,6.2 12.8,4 9.3,4 Z M8.2,8.1 A0.9,0.9 0 1 0 6.4,8.1 A0.9,0.9 0 1 0 8.2,8.1 Z M12.6,8.1 A0.9,0.9 0 1 0 10.8,8.1 A0.9,0.9 0 1 0 12.6,8.1 Z M15.8,9.9 C12.7,9.9 10.2,11.9 10.2,14.5 C10.2,17 12.7,19.1 15.8,19.1 C16.4,19.1 17.1,19 17.7,18.8 L19.7,19.8 L19.2,18 C20.5,17.2 21.4,15.9 21.4,14.5 C21.4,12 18.9,9.9 15.8,9.9 Z M15,13.2 A0.8,0.8 0 1 0 13.4,13.2 A0.8,0.8 0 1 0 15,13.2 Z M18.2,13.2 A0.8,0.8 0 1 0 16.6,13.2 A0.8,0.8 0 1 0 18.2,13.2 Z",
        ["bolt"] = "M13,2 L5,14 L11,14 L10,22 L19,9 L13,9 Z",
        ["boltFilled"] = "M13,2 L5,14 L11,14 L10,22 L19,9 L13,9 Z",
        ["money"] = "M15.5,7.5 C14,5.5 8,5.5 8,9 C8,13 16,10 16,15 C16,18.5 10,18.5 8,16.5 M12,4 L12,20",
        ["sparkles"] = "M12,2 L14.6,8.4 L21,11 L14.6,13.6 L12,20 L9.4,13.6 L3,11 L9.4,8.4 Z M20,1 L21,3 L23,4 L21,5 L20,7 L19,5 L17,4 L19,3 Z M3,17 L4,19 L6,20 L4,21 L3,23 L2,21 L0,20 L2,19 Z",
        ["person"] = "M12,12 C14.5,12 16.5,10 16.5,7.5 C16.5,5 14.5,3 12,3 C9.5,3 7.5,5 7.5,7.5 C7.5,10 9.5,12 12,12 Z M4,21 C4,16.5 7.5,14 12,14 C16.5,14 20,16.5 20,21 Z",
        ["privacy"] = "M8,13 L8,5 C8,3 10,3 10,5 L10,11 M10,5 L10,3.5 C10,1.5 12,1.5 12,3.5 L12,11 M12,4.5 C12,2.5 14,2.5 14,4.5 L14,11 M14,6.5 C14,4.5 16,4.5 16,6.5 L16,13 L18,10.5 C19.5,8.5 22,10.5 20.5,12.5 L17,19 C15,23 8,23 6,19 L3,13 C2,11 4.5,9.5 6,12 L8,15",
        ["document"] = "M4,2 L14,2 L20,8 L20,22 L4,22 Z M14,2 L14,8 L20,8 M8,12 L16,12 M8,16 L16,16",
        ["logout"] = "M14,5 L14,3 L4,3 L4,21 L14,21 L14,19 M10,12 L22,12 M18,8 L22,12 L18,16",
    };
    public Glyph()
    {
        viewbox.Child = canvas;
        Children.Add(viewbox);
        IsHitTestVisible = false;
    }

    internal void FitArtwork(double size)
    {
        artworkSize = size;
        viewbox.Child = null;
        artworkFrame = new Canvas();
        artworkFrame.Children.Add(canvas);
        viewbox.Child = artworkFrame;
        ResizeArtwork();
    }

    private static void Changed(DependencyObject sender, DependencyPropertyChangedEventArgs args) => ((Glyph)sender).Draw();
    private void Draw()
    {
        canvas.Children.Clear();
        if (Foreground is null) return;
        if (Kind is "key" or "warning" or "globe" or "record" or "money")
        {
            double radius = Kind == "key" ? 5.5 : Kind == "warning" ? 9 : Kind == "record" ? 8 : 10;
            var circle = new Ellipse { Width = radius * 2, Height = radius * 2, Stroke = Foreground, StrokeThickness = 1.8, Fill = Kind == "record" ? Foreground : null };
            Canvas.SetLeft(circle, (Kind == "key" ? 7.5 : 12) - radius); Canvas.SetTop(circle, (Kind == "key" ? 15.5 : 12) - radius); canvas.Children.Add(circle);
        }
        if (Kind == "stop")
        {
            var square = new Rectangle { Width = 10, Height = 10, RadiusX = 1, RadiusY = 1, Fill = Foreground };
            Canvas.SetLeft(square, 7); Canvas.SetTop(square, 7); canvas.Children.Add(square);
        }
        else if (Paths.TryGetValue(Kind, out string? data))
        {
            var path = (Microsoft.UI.Xaml.Shapes.Path)XamlReader.Load($"<Path xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Data='{data}'/>");
            if (Kind is "wechat" or "socialX" or "person" or "boltFilled" or "sparkles" or "warningTriangle")
            {
                path.Fill = Foreground;
                if (Kind == "wechat") path.RenderTransform = new MatrixTransform { Matrix = new(1.15, 0, 0, 1.15, -1.8, -1.8) };
            }
            else
            {
                path.Stroke = Foreground; path.StrokeThickness = 1.8; path.StrokeStartLineCap = path.StrokeEndLineCap = PenLineCap.Round; path.StrokeLineJoin = PenLineJoin.Round;
            }
            canvas.Children.Add(path);
        }
        ResizeArtwork();
    }

    private void ResizeArtwork()
    {
        if (artworkFrame is null || canvas.Children.Count == 0) return;

        var bounds = Rect.Empty;
        foreach (Shape shape in canvas.Children)
        {
            if (shape is not Microsoft.UI.Xaml.Shapes.Path path)
            {
                bounds.Union(new Rect(Canvas.GetLeft(shape), Canvas.GetTop(shape), shape.Width, shape.Height));
                continue;
            }

            Rect painted = path.Data.Bounds;
            if (path.Stroke is not null)
            {
                double halfStroke = path.StrokeThickness / 2;
                painted = new Rect(painted.X - halfStroke, painted.Y - halfStroke,
                    painted.Width + path.StrokeThickness, painted.Height + path.StrokeThickness);
            }
            bounds.Union(path.RenderTransform?.TransformBounds(painted) ?? painted);
        }

        // The frame removes the empty space around the artwork before the Viewbox scales it.
        double scale = artworkSize / Math.Max(bounds.Width, bounds.Height);
        Width = bounds.Width * scale;
        Height = bounds.Height * scale;
        artworkFrame.Width = bounds.Width;
        artworkFrame.Height = bounds.Height;
        Canvas.SetLeft(canvas, -bounds.X);
        Canvas.SetTop(canvas, -bounds.Y);
    }
}
