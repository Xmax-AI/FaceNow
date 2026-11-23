//
//  HomeReferencePicker.cs
//  FaceNow
//

using System.Numerics;
using FaceNow.Windows.Studio.ViewModels;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;

namespace FaceNow.App.Controls;

internal sealed class HomeReferencePicker : UserControl
{
    internal const double AvatarSize = 52;
    private const double StripHeight = AvatarSize + 4;
    private const double Spacing = 8;
    private const float FadeWidth = 50;
    private const double EdgeTolerance = .5;
    private const double DragThreshold = 4;
    private readonly StackPanel tiles = new()
    {
        Orientation = Orientation.Horizontal,
        Spacing = Spacing,
        VerticalAlignment = VerticalAlignment.Center,
        Background = Theme.Brush("#00000000")
    };
    private readonly ScrollViewer strip;
    private readonly Button more;
    private IReadOnlyList<ReferenceItem>? displayedReferences;
    private ReferenceItem? selected;
    private ReferenceTile? pressedTile;
    private uint? dragPointerId;
    private Point dragOrigin;
    private double dragX;
    private double dragOffset;
    private bool isDragging;

    internal event Action? MoreRequested;

    internal event Action<ReferenceItem>? ReferenceSelected;

    internal HomeReferencePicker(
        IReadOnlyList<ReferenceItem> presets
    )
    {
        Height = StripHeight;
        HorizontalAlignment = HorizontalAlignment.Center;
        strip = new ScrollViewer
        {
            Width = presets.Count * StripHeight + Math.Max(0, presets.Count - 1) * Spacing,
            Height = StripHeight,
            Content = tiles,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollMode = ScrollMode.Enabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollMode = ScrollMode.Disabled,
            ZoomMode = ZoomMode.Disabled
        };
        strip.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(BeginMouseDrag), true);
        strip.AddHandler(UIElement.PointerMovedEvent, new PointerEventHandler(ContinueMouseDrag), true);
        strip.AddHandler(UIElement.PointerReleasedEvent, new PointerEventHandler(EndMouseDrag), true);
        strip.AddHandler(UIElement.PointerCanceledEvent, new PointerEventHandler(EndMouseDrag), true);
        strip.AddHandler(UIElement.PointerCaptureLostEvent, new PointerEventHandler(LoseMouseCapture), true);
        strip.AddHandler(UIElement.PointerWheelChangedEvent, new PointerEventHandler(ScrollWithMouse), true);
        AutomationProperties.SetName(strip, AppText.Get("Reference images"));

        var moreCircle = new Grid
        {
            Width = AvatarSize,
            Height = AvatarSize,
            Opacity = .85,
            Children =
            {
                new Ellipse
                {
                    Stroke = Theme.Brush("#FFFFFF"),
                    StrokeThickness = 1.5,
                    StrokeDashArray = new DoubleCollection { 3, 3 }
                },
                new Glyph
                {
                    Kind = "plus",
                    Width = 22,
                    Height = 22,
                    Foreground = Theme.Brush("#FFFFFF"),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                }
            }
        };
        more = new Button
        {
            Template = Theme.ButtonTemplate,
            Content = moreCircle,
            Width = StripHeight,
            Height = AvatarSize,
            Padding = new(0),
            BorderThickness = new(0),
            Background = Theme.Brush("#00000000"),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            UseSystemFocusVisuals = true
        };
        string moreLabel = AppText.Get("Reference images");
        AutomationProperties.SetName(more, moreLabel);
        AutomationProperties.SetAutomationId(more, "home_reference_more");
        ToolTipService.SetToolTip(more, moreLabel);
        more.PointerEntered += (_, _) => moreCircle.Opacity = 1;
        more.PointerExited += (_, _) => moreCircle.Opacity = .85;
        more.Click += (_, _) => MoreRequested?.Invoke();
        Content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = Spacing,
            Children = { more, CreateFadedStrip() }
        };
    }

    internal void Update(
        IReadOnlyList<ReferenceItem> references,
        ReferenceItem selection,
        bool enabled,
        bool dimmed
    )
    {
        if (displayedReferences != references)
        {
            displayedReferences = references;
            tiles.Children.Clear();
            foreach (var item in references)
                tiles.Children.Add(CreateTile(item));
            strip.ChangeView(0, null, null, true);
        }
        selected = selection;
        more.IsEnabled = enabled;
        tiles.Opacity = more.Opacity = dimmed ? .5 : 1;
        foreach (ReferenceTile tile in tiles.Children)
            tile.UpdateCompactSelection(tile.Item == selection, enabled);
    }

    internal void RevealSelection()
    {
        foreach (ReferenceTile tile in tiles.Children)
        {
            if (tile.Item == selected)
            {
                tile.StartBringIntoView(new() { AnimationDesired = false });
                break;
            }
        }
    }

    private ReferenceTile CreateTile(
        ReferenceItem item
    )
    {
        var tile = new ReferenceTile(item, compact: true);
        tile.Click += (_, _) => ReferenceSelected?.Invoke(item);
        return tile;
    }

    private Grid CreateFadedStrip()
    {
        var viewport = new Grid();
        viewport.Children.Add(strip);
        viewport.Loaded += (_, _) =>
        {
            if (ElementCompositionPreview.GetElementChildVisual(viewport) is not null)
                return;

            var source = ElementCompositionPreview.GetElementVisual(strip);
            var compositor = source.Compositor;
            var contentSurface = compositor.CreateVisualSurface();
            contentSurface.SourceVisual = source;
            var gradient = compositor.CreateLinearGradientBrush();
            gradient.StartPoint = Vector2.Zero;
            gradient.EndPoint = Vector2.UnitX;
            var opaque = Microsoft.UI.Colors.Black;
            var faded = global::Windows.UI.Color.FromArgb(51, 0, 0, 0);
            var leadingEdge = compositor.CreateColorGradientStop(0, opaque);
            var leadingInner = compositor.CreateColorGradientStop(0, opaque);
            var trailingInner = compositor.CreateColorGradientStop(1, opaque);
            var trailingEdge = compositor.CreateColorGradientStop(1, opaque);
            gradient.ColorStops.Add(leadingEdge);
            gradient.ColorStops.Add(leadingInner);
            gradient.ColorStops.Add(trailingInner);
            gradient.ColorStops.Add(trailingEdge);

            var maskVisual = compositor.CreateSpriteVisual();
            maskVisual.Brush = gradient;
            var maskSurface = compositor.CreateVisualSurface();
            maskSurface.SourceVisual = maskVisual;
            var maskBrush = compositor.CreateMaskBrush();
            maskBrush.Source = compositor.CreateSurfaceBrush(contentSurface);
            maskBrush.Mask = compositor.CreateSurfaceBrush(maskSurface);
            var output = compositor.CreateSpriteVisual();
            output.Brush = maskBrush;

            void UpdateEdges()
            {
                leadingEdge.Color = strip.HorizontalOffset > EdgeTolerance ? faded : opaque;
                trailingEdge.Color = strip.ScrollableWidth - strip.HorizontalOffset > EdgeTolerance ? faded : opaque;
            }

            void ResizeMask()
            {
                var size = new Vector2((float)viewport.ActualWidth, (float)viewport.ActualHeight);
                contentSurface.SourceSize = maskSurface.SourceSize = maskVisual.Size = output.Size = size;
                float fraction = size.X > 0 ? Math.Min(.5f, FadeWidth / size.X) : 0;
                leadingInner.Offset = fraction;
                trailingInner.Offset = 1 - fraction;
            }

            viewport.SizeChanged += (_, _) => ResizeMask();
            strip.ViewChanged += (_, _) => UpdateEdges();
            strip.RegisterPropertyChangedCallback(ScrollViewer.ScrollableWidthProperty, (_, _) => UpdateEdges());
            ResizeMask();
            UpdateEdges();
            // Present the masked visual while the original ScrollViewer keeps input and focus.
            ElementCompositionPreview.SetElementChildVisual(viewport, output);
            source.Opacity = 0;
        };
        return viewport;
    }

    private void BeginMouseDrag(
        object sender,
        PointerRoutedEventArgs args
    )
    {
        var point = args.GetCurrentPoint(strip);
        if (point.PointerDeviceType != PointerDeviceType.Mouse ||
            point.Properties.PointerUpdateKind != PointerUpdateKind.LeftButtonPressed ||
            strip.ScrollableWidth <= 0)
            return;

        dragPointerId = args.Pointer.PointerId;
        dragOrigin = point.Position;
        isDragging = false;
        DependencyObject? source = args.OriginalSource as DependencyObject;
        while (source is not null && source != strip && source is not ReferenceTile)
            source = VisualTreeHelper.GetParent(source);
        pressedTile = source as ReferenceTile;
        if (pressedTile is null)
            strip.CapturePointer(args.Pointer);
    }

    private void ContinueMouseDrag(
        object sender,
        PointerRoutedEventArgs args
    )
    {
        if (args.Pointer.PointerId != dragPointerId)
            return;

        var point = args.GetCurrentPoint(strip);
        if (!point.Properties.IsLeftButtonPressed)
        {
            EndMouseDrag(sender, args);
            return;
        }
        if (!isDragging)
        {
            double horizontal = Math.Abs(point.Position.X - dragOrigin.X);
            double vertical = Math.Abs(point.Position.Y - dragOrigin.Y);
            if (horizontal < DragThreshold || horizontal <= vertical)
                return;

            // Transfer capture only after a pan begins. Losing capture cancels the tile's pending click.
            if (pressedTile is { } tile)
            {
                pressedTile = null;
                tile.ReleasePointerCapture(args.Pointer);
                if (!strip.CapturePointer(args.Pointer))
                {
                    dragPointerId = null;
                    return;
                }
            }
            isDragging = true;
            dragX = dragOrigin.X;
            dragOffset = strip.HorizontalOffset;
        }

        dragOffset = Math.Clamp(dragOffset + dragX - point.Position.X, 0, strip.ScrollableWidth);
        dragX = point.Position.X;
        strip.ChangeView(dragOffset, null, null, true);
        args.Handled = true;
    }

    private void EndMouseDrag(
        object sender,
        PointerRoutedEventArgs args
    )
    {
        if (args.Pointer.PointerId != dragPointerId)
            return;

        if (isDragging)
            args.Handled = true;
        dragPointerId = null;
        pressedTile = null;
        isDragging = false;
        strip.ReleasePointerCapture(args.Pointer);
    }

    private void LoseMouseCapture(
        object sender,
        PointerRoutedEventArgs args
    )
    {
        var source = args.OriginalSource as DependencyObject;
        if (source == strip || (pressedTile is not null && source == pressedTile))
            EndMouseDrag(sender, args);
    }

    private void ScrollWithMouse(
        object sender,
        PointerRoutedEventArgs args
    )
    {
        var properties = args.GetCurrentPoint(strip).Properties;
        if (properties.IsHorizontalMouseWheel || strip.ScrollableWidth <= 0)
            return;
        double target = Math.Clamp(
            strip.HorizontalOffset - properties.MouseWheelDelta * (StripHeight + Spacing) / 120,
            0,
            strip.ScrollableWidth
        );
        if (target == strip.HorizontalOffset)
            return;
        args.Handled = strip.ChangeView(target, null, null, true);
    }
}
