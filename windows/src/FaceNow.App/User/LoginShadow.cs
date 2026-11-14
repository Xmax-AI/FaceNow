//
//  LoginShadow.cs
//  FaceNow
//

using System.Numerics;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Windows.UI;

namespace FaceNow.App.User;

/// <summary>
/// Draws a composition shadow that follows the dimensions of its host.
/// </summary>
internal sealed class LoginShadow
{
    private readonly Grid host;
    private readonly Func<float> radius;
    private readonly Color color;
    private readonly float blur, offset;
    private Microsoft.UI.Composition.DropShadow? shadow;
    private Action? resize;
    private float opacity;

    internal LoginShadow(
        Grid host,
        Func<float> radius,
        Color color,
        float blur,
        float offset,
        float opacity
    )
    {
        this.host = host;
        this.radius = radius;
        this.color = color;
        this.blur = blur;
        this.offset = offset;
        this.opacity = opacity;
        host.Loaded += (_, _) => Initialize();
        host.SizeChanged += (_, _) => resize?.Invoke();
    }

    internal void SetOpacity(
        float value
    )
    {
        opacity = value;
        if (shadow is not null)
            shadow.Opacity = value;
    }

    private void Initialize()
    {
        if (shadow is not null)
            return;
        var compositor = ElementCompositionPreview.GetElementVisual(host).Compositor;
        var geometry = compositor.CreateRoundedRectangleGeometry();
        var shape = compositor.CreateSpriteShape(geometry);
        shape.FillBrush = compositor.CreateColorBrush(Microsoft.UI.Colors.White);
        var caster = compositor.CreateShapeVisual();
        caster.Shapes.Add(shape);
        var mask = compositor.CreateVisualSurface();
        mask.SourceVisual = caster;
        shadow = compositor.CreateDropShadow();
        shadow.Color = color;
        shadow.BlurRadius = blur;
        shadow.Offset = new(0, offset, 0);
        shadow.Opacity = opacity;
        shadow.Mask = compositor.CreateSurfaceBrush(mask);
        var visual = compositor.CreateSpriteVisual();
        visual.Shadow = shadow;
        resize = () =>
        {
            var size = new Vector2((float)host.ActualWidth, (float)host.ActualHeight);
            geometry.Size = caster.Size = mask.SourceSize = visual.Size = size;
            geometry.CornerRadius = new(radius());
        };
        resize();
        ElementCompositionPreview.SetElementChildVisual(host, visual);
    }
}
