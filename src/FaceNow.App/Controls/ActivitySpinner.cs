//
//  ActivitySpinner.cs
//  FaceNow
//

using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace FaceNow.App.Controls;

/// <summary>A geometry-only indicator avoids ProgressRing's deferred native style/Lottie activation.</summary>
internal sealed class ActivitySpinner : Grid
{
    private readonly Storyboard rotation = new();
    private bool active;

    internal bool IsActive
    {
        get => active;
        set
        {
            if (active == value)
                return;
            active = value;
            UpdateAnimation();
        }
    }

    internal ActivitySpinner()
    {
        Width = Height = 18;
        IsHitTestVisible = false;
        var transform = new RotateTransform { CenterX = 9, CenterY = 9 };
        Children.Add(new Microsoft.UI.Xaml.Shapes.Path
        {
            Stroke = Theme.Brush("#FFFFFF"),
            StrokeThickness = 2,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            RenderTransform = transform,
            Data = new PathGeometry
            {
                Figures = { new PathFigure { StartPoint = new(9, 2.5),
                Segments = { new ArcSegment
{
Point = new(2.5, 9),
Size = new(6.5, 6.5),
IsLargeArc = true,
SweepDirection = SweepDirection.Clockwise
} } } }
            }
        });
        var animation = new DoubleAnimation
        {
            From = 0,
            To = 360,
            Duration = new(TimeSpan.FromMilliseconds(800)),
            RepeatBehavior = RepeatBehavior.Forever,
            EnableDependentAnimation = true
        };
        Storyboard.SetTarget(animation, transform);
        Storyboard.SetTargetProperty(animation, "Angle");
        rotation.Children.Add(animation);
        Loaded += (_, _) => UpdateAnimation();
        Unloaded += (_, _) => rotation.Stop();
    }

    private void UpdateAnimation()
    {
        rotation.Stop();
        if (active && IsLoaded && LoginMotion.Enabled)
            rotation.Begin();
    }
}
