using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI.ViewManagement;

namespace FaceNow.App.Controls;

internal enum ToastStyle { Error, Success }

/// <summary>Matches the macOS ToastView geometry, timing and notification semantics.</summary>
internal sealed class ToastView : Grid
{
    private readonly Border surface = new()
    {
        MinHeight = 48, CornerRadius = new(14), Background = Theme.Brush("#F5FFFFFF"),
        BorderBrush = Theme.Brush("#1A111318"), BorderThickness = new(1), Padding = new(12, 7, 12, 7)
    };
    private readonly TextBlock message = LoginTypography.Text("", 14);
    private readonly Ellipse circle = new() { Width = 20, Height = 20, StrokeThickness = 1.6 };
    private readonly Microsoft.UI.Xaml.Shapes.Path successMark = Mark("M5,10 L8.5,13.5 L15,6.5");
    private readonly Microsoft.UI.Xaml.Shapes.Path errorMark = Mark("M10,5.5 L10,10.5 M10,14 L10,14.2");
    private readonly TranslateTransform offset = new();
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer timer;
    private Storyboard? motion;
    private bool stopped;
    internal string? Message { get; private set; }
    internal ToastStyle NotificationStyle { get; private set; }
    internal event Action? Dismissed;

    internal ToastView()
    {
        MaxWidth = 560; HorizontalAlignment = HorizontalAlignment.Center; VerticalAlignment = VerticalAlignment.Top;
        Margin = new(28, 32, 28, 0); Visibility = Visibility.Collapsed; RenderTransform = offset;
        var shadow = new Grid { IsHitTestVisible = false };
        _ = new LoginShadow(shadow, () => 14, Microsoft.UI.Colors.Black, 12, 5, .12f);
        Children.Add(shadow); Children.Add(surface);
        var row = new Grid();
        row.ColumnDefinitions.Add(new() { Width = new(20) });
        row.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        var icon = new Grid { Width = 20, Height = 20, VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false };
        icon.Children.Add(circle); icon.Children.Add(errorMark); icon.Children.Add(successMark); row.Children.Add(icon);
        message.TextWrapping = TextWrapping.Wrap; message.IsTextSelectionEnabled = true;
        message.Margin = new(9, 0, 0, 0); message.Padding = new(0, 0, 4, 0);
        AutomationProperties.SetLiveSetting(message, AutomationLiveSetting.Polite);
        Grid.SetColumn(message, 1); row.Children.Add(message);
        surface.Child = row;
        timer = DispatcherQueue.CreateTimer(); timer.Interval = TimeSpan.FromSeconds(4);
        timer.IsRepeating = false; timer.Tick += (_, _) => Dismiss();
    }

    private static Microsoft.UI.Xaml.Shapes.Path Mark(string data) => (Microsoft.UI.Xaml.Shapes.Path)XamlReader.Load($"""
        <Path xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Data="{data}"
              Width="20" Height="20" Stroke="#111318" StrokeThickness="1.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
        """);

    internal void Update(string? value, ToastStyle style = ToastStyle.Error, bool announce = false)
    {
        if (stopped) return;
        if (value is not null) value = AppText.Get(value);
        if (string.IsNullOrEmpty(value))
        {
            timer.Stop();
            if (Message is null) return;
            Message = null; Animate(false); return;
        }
        bool changed = Message != value || NotificationStyle != style;
        if (!changed && !announce) return;
        Message = value; NotificationStyle = style; message.Text = value;
        bool success = style == ToastStyle.Success;
        var color = Theme.Brush(success ? "#28CD41" : "#FF3B30");
        circle.Fill = success ? color : null; circle.Stroke = success ? null : color;
        successMark.Stroke = Theme.Brush("#FFFFFF"); errorMark.Stroke = color;
        successMark.Visibility = success ? Visibility.Visible : Visibility.Collapsed;
        errorMark.Visibility = success ? Visibility.Collapsed : Visibility.Visible;
        Animate(true); timer.Stop(); timer.Start();
        if (announce)
        {
            var peer = FrameworkElementAutomationPeer.FromElement(message) ?? FrameworkElementAutomationPeer.CreatePeerForElement(message);
            peer?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        }
    }

    private void Animate(bool show)
    {
        bool appearing = Visibility == Visibility.Collapsed;
        double fromOpacity = appearing ? 0 : Opacity, fromOffset = appearing ? -32 : offset.Y;
        motion?.Stop(); motion = null;
        Opacity = show ? 1 : 0; offset.Y = show ? 0 : -32; IsHitTestVisible = show;
        if (show) Visibility = Visibility.Visible;
        if (!IsLoaded || !new UISettings().AnimationsEnabled)
        {
            if (!show) Visibility = Visibility.Collapsed;
            return;
        }
        var storyboard = new Storyboard { FillBehavior = FillBehavior.Stop };
        void Add(DependencyObject target, string property, double from, double to)
        {
            var animation = new DoubleAnimationUsingKeyFrames
            {
                Duration = new(TimeSpan.FromMilliseconds(400)), EnableDependentAnimation = true,
                KeyFrames = { new LinearDoubleKeyFrame { Value = from, KeyTime = KeyTime.FromTimeSpan(TimeSpan.Zero) },
                    new SplineDoubleKeyFrame { Value = to, KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(400)),
                        KeySpline = new() { ControlPoint1 = new(.42, 0), ControlPoint2 = new(.58, 1) } } }
            };
            Storyboard.SetTarget(animation, target); Storyboard.SetTargetProperty(animation, property); storyboard.Children.Add(animation);
        }
        Add(this, "Opacity", fromOpacity, Opacity); Add(offset, "Y", fromOffset, offset.Y);
        storyboard.Completed += (_, _) =>
        {
            if (motion != storyboard) return;
            motion = null; if (!show) Visibility = Visibility.Collapsed;
        };
        motion = storyboard; storyboard.Begin();
    }

    internal void Dismiss()
    {
        if (Message is null || stopped) return;
        Update(null); Dismissed?.Invoke();
    }

    internal void Shutdown()
    {
        stopped = true; timer.Stop(); motion?.Stop(); motion = null; Message = null; Visibility = Visibility.Collapsed;
    }
}
