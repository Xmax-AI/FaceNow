using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace FaceNow.App.Controls;

internal sealed class ReferenceUploadOverlay : Grid
{
    private readonly Storyboard rotation = new();
    private readonly TextBlock progressLabel;
    private bool uploading;

    internal ReferenceUploadOverlay(bool compact = false)
    {
        Children.Add(new Border { Background = Theme.Brush("#8C000000"), CornerRadius = new(compact ? 22 : 32) });
        IsHitTestVisible = false;
        Visibility = Visibility.Collapsed;
        var content = new StackPanel
        {
            Spacing = 3, HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        // Use XAML geometry, as in XLab; the default Lottie ProgressRing can crash on Windows ARM.
        var spinner = new Grid { Width = 14, Height = 14, HorizontalAlignment = HorizontalAlignment.Center };
        var transform = new RotateTransform { CenterX = 7, CenterY = 7 };
        var arc = new Microsoft.UI.Xaml.Shapes.Path
        {
            Stroke = Theme.Brush("#FFFFFF"), StrokeThickness = 1.8,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            RenderTransform = transform,
            Data = new PathGeometry { Figures = { new PathFigure { StartPoint = new(7, 1.5),
                Segments = { new ArcSegment { Point = new(1.5, 7), Size = new(5.5, 5.5), IsLargeArc = true, SweepDirection = SweepDirection.Clockwise } } } } }
        };
        spinner.Children.Add(arc);
        var animation = new DoubleAnimation { From = 0, To = 360, Duration = new(TimeSpan.FromMilliseconds(800)),
            RepeatBehavior = RepeatBehavior.Forever, EnableDependentAnimation = true };
        Storyboard.SetTarget(animation, transform); Storyboard.SetTargetProperty(animation, "Angle");
        rotation.Children.Add(animation);
        content.Children.Add(spinner);
        progressLabel = Theme.Text("", compact ? 9 : 10, "#FFFFFF");
        progressLabel.TextAlignment = TextAlignment.Center;
        progressLabel.Visibility = Visibility.Collapsed;
        content.Children.Add(progressLabel);
        Children.Add(content);
        Loaded += (_, _) => UpdateAnimation();
        Unloaded += (_, _) => rotation.Stop();
    }

    internal void SetUploading(bool uploading, double? progress)
    {
        progressLabel.Text = progress is double value ? $"{Math.Floor(Math.Clamp(value, 0, 1) * 100):0}%" : "";
        progressLabel.Visibility = progress.HasValue ? Visibility.Visible : Visibility.Collapsed;
        if (this.uploading == uploading) return;
        this.uploading = uploading;
        Visibility = uploading ? Visibility.Visible : Visibility.Collapsed;
        UpdateAnimation();
    }

    private void UpdateAnimation()
    {
        rotation.Stop();
        if (uploading && IsLoaded) rotation.Begin();
    }
}
