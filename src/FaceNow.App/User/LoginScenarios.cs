//
//  LoginScenarios.cs
//  FaceNow
//

using System.Numerics;
using FaceNow.App.Controls;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;

namespace FaceNow.App.User;

internal sealed class LoginScenarios : UserControl
{
    private const float Period = 12 * 68;
    private readonly Canvas viewport = new() { Height = 52 };
    private readonly Canvas track = new() { Width = Period * 3, Height = 52 };
    private bool playing;

    internal LoginScenarios()
    {
        Height = 88;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        var content = new Grid();
        content.RowDefinitions.Add(new()
        {
            Height = new(24)
        });
        content.RowDefinitions.Add(new()
        {
            Height = new(10)
        });
        content.RowDefinitions.Add(new()
        {
            Height = new(52)
        });
        var heading = new Grid { ColumnSpacing = 18 };
        heading.ColumnDefinitions.Add(new());
        heading.ColumnDefinitions.Add(new()
        {
            Width = GridLength.Auto
        });
        heading.ColumnDefinitions.Add(new());
        for (int i = 0; i < 2; i++)
        {
            var line = new Line
            {
                X2 = 1,
                Stretch = Stretch.Fill,
                Height = 1,
                StrokeThickness = 1,
                Stroke = Theme.Brush("#476B7380"),
                StrokeDashArray = new DoubleCollection { 3, 4 },
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(line, i * 2);
            heading.Children.Add(line);
        }
        var title = LoginTypography.Text("Scenarios", 16, "#666B7380");
        title.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        Grid.SetColumn(title, 1);
        heading.Children.Add(title);
        content.Children.Add(heading);
        string[] brands = ["WeChat", "Zoom", "TencentMeeting", "Feishu", "Teams", "GoogleMeet", "DingTalk", "QQ", "Discord", "Slack", "Telegram", "WhatsApp"];
        for (int copy = 0; copy < 3; copy++)
            for (int i = 0; i < brands.Length; i++)
            {
                var image = new Image
                {
                    Width = 32,
                    Height = 32,
                    Opacity = .4,
                    Source = new SvgImageSource(new($"ms-appx:///Assets/Login/Scenarios/Muted/Scenario{brands[i]}.svg"))
                };
                AutomationProperties.SetName(image, brands[i]);
                Canvas.SetLeft(image, (copy * 12 + i) * 68 + 18);
                Canvas.SetTop(image, 10);
                track.Children.Add(image);
            }
        viewport.Children.Add(track);
        Canvas.SetLeft(track, -Period);
        var window = new Grid();
        window.Children.Add(viewport);
        window.Children.Add(new Border
        {
            IsHitTestVisible = false,
            Background = new LinearGradientBrush
            {
                StartPoint = new(0, .5),
                EndPoint = new(1, .5),
                GradientStops = {
                new() { Color = Microsoft.UI.Colors.White }, new()
{
Color = Microsoft.UI.Colors.Transparent,
Offset = .08
},
                new()
{
Color = Microsoft.UI.Colors.Transparent,
Offset = .92
}, new()
{
Color = Microsoft.UI.Colors.White,
Offset = 1
} }
            }
        });
        Grid.SetRow(window, 2);
        content.Children.Add(window);
        Content = content;
        viewport.SizeChanged += (_, _) => viewport.Clip = new RectangleGeometry
        {
            Rect = new(
            0,
            0,
            viewport.ActualWidth,
            52
        )
        };
        Loaded += (_, _) => UpdateAnimation();
        Unloaded += (_, _) => SetPlaying(false);
        AutomationProperties.SetName(
            this,
            "Scenarios: WeChat, Zoom, Tencent Meeting, Feishu, Microsoft Teams, Google Meet, DingTalk, QQ, Discord, Slack, Telegram, WhatsApp"
        );
    }

    internal void SetPlaying(
        bool value
    )
    {
        playing = value;
        UpdateAnimation();
    }

    private void UpdateAnimation()
    {
        if (!track.IsLoaded)
            return;
        ElementCompositionPreview.SetIsTranslationEnabled(track, true);
        var visual = ElementCompositionPreview.GetElementVisual(track);
        visual.StopAnimation("Translation");
        visual.Properties.InsertVector3("Translation", Vector3.Zero);
        if (!playing || !LoginMotion.Enabled)
            return;
        var animation = visual.Compositor.CreateVector3KeyFrameAnimation();
        animation.InsertKeyFrame(0, Vector3.Zero);
        animation.InsertKeyFrame(1, new(Period, 0, 0), visual.Compositor.CreateLinearEasingFunction());
        animation.Duration = TimeSpan.FromSeconds(Period / 22);
        animation.IterationBehavior = AnimationIterationBehavior.Forever;
        visual.StartAnimation("Translation", animation);
    }
}
