//
//  LoginMotion.cs
//  FaceNow
//

using System.Runtime.CompilerServices;
using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace FaceNow.App.User;

/// <summary>Shared color and opacity transitions for FaceNow controls.</summary>
internal static class LoginMotion
{
    private sealed class State
    {
        public State()
        {
        }

        public object? Desired; public Storyboard? Animation;
    }

    private static readonly ConditionalWeakTable<DependencyObject, State> states = new();

    internal static bool Enabled => new UISettings().AnimationsEnabled;

    internal static void Color(
        FrameworkElement owner,
        SolidColorBrush brush,
        string hex
    ) =>
        Color(owner, brush, SolidColorBrush.ColorProperty, Theme.Brush(hex).Color);

    internal static void Color(
        FrameworkElement owner,
        GradientStop stop,
        string hex,
        bool pressed
    )
    {
        var next = Theme.Brush(hex).Color;
        if (pressed)
            next = global::Windows.UI.Color.FromArgb(next.A, (byte)Math.Round(next.R * .94),
                (byte)Math.Round(next.G * .94), (byte)Math.Round(next.B * .94));
        Color(owner, stop, GradientStop.ColorProperty, next);
    }

    private static void Color(
        FrameworkElement owner,
        DependencyObject target,
        DependencyProperty property,
        Color next
    )
    {
        var state = states.GetOrCreateValue(target);
        if (Equals(state.Desired, next))
            return;
        bool animate = state.Desired is not null && owner.IsLoaded && Enabled;
        var current = (Color)target.GetValue(property);
        state.Animation?.Stop();
        state.Desired = next;
        target.SetValue(property, next);
        if (!animate)
            return;
        var animation = new ColorAnimation
        {
            From = current,
            To = next,
            Duration = TimeSpan.FromSeconds(.3),
            EnableDependentAnimation = true,
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        Storyboard.SetTarget(animation, target);
        Storyboard.SetTargetProperty(animation, "Color");
        var storyboard = new Storyboard { FillBehavior = FillBehavior.Stop };
        storyboard.Children.Add(animation);
        state.Animation = storyboard;
        storyboard.Begin();
    }

    internal static void Opacity(
        FrameworkElement owner,
        double next
    )
    {
        var state = states.GetOrCreateValue(owner);
        if (Equals(state.Desired, next))
            return;
        bool animate = state.Desired is not null && owner.IsLoaded && Enabled;
        double current = owner.Opacity;
        state.Animation?.Stop();
        state.Desired = next;
        owner.Opacity = next;
        if (!animate)
            return;
        var animation = new DoubleAnimation
        {
            From = current,
            To = next,
            Duration = TimeSpan.FromSeconds(.3),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        Storyboard.SetTarget(animation, owner);
        Storyboard.SetTargetProperty(animation, "Opacity");
        var storyboard = new Storyboard { FillBehavior = FillBehavior.Stop };
        storyboard.Children.Add(animation);
        state.Animation = storyboard;
        storyboard.Begin();
    }
}
