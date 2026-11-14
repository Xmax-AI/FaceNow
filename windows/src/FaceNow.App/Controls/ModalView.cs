//
//  ModalView.cs
//  FaceNow
//

using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.System;

namespace FaceNow.App.Controls;

internal class ModalView : UserControl, IDisposable
{
    private readonly Border backdrop = new() { Background = Theme.Brush("#59000000"), Opacity = 0 };
    private readonly Grid card = new()
    {
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        Opacity = 0
    };
    private readonly Border surface;
    private readonly TranslateTransform slide = new() { Y = 24 };
    private readonly Button closeButton;
    private Storyboard? motion;
    private TaskCompletionSource? motionFinished;
    private bool disposed;

    internal event Action? DismissRequested;

    internal bool IsDismissing { get; private set; }

    internal UIElement? Body
    {
        get => surface.Child;
        set => surface.Child = value;
    }

    protected double BodyMaxHeight => Math.Max(0, card.MaxHeight - surface.Padding.Top - surface.Padding.Bottom);

    internal ModalView(
        string title,
        string closeLabel,
        double maxWidth,
        double maxHeight
    )
    {
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        VerticalAlignment = VerticalAlignment.Stretch;
        IsTabStop = true;
        UseSystemFocusVisuals = false;
        TabFocusNavigation = KeyboardNavigationMode.Cycle;
        AutomationProperties.SetName(this, AppText.Get(title));
        AutomationProperties.SetIsDialog(this, true);
        var overlay = new Grid { Background = Theme.Brush("#00FFFFFF") };
        overlay.Children.Add(backdrop);
        backdrop.Tapped += (_, args) =>
        {
            args.Handled = true;
            RequestDismiss();
        };
        card.RenderTransform = slide;
        var shadow = new Grid { IsHitTestVisible = false };
        _ = new LoginShadow(shadow, () => 22, Microsoft.UI.Colors.Black, 28, 8, .16f);
        card.Children.Add(shadow);
        surface = new Border
        {
            Background = Theme.Brush("#FFFFFF"),
            CornerRadius = new(22),
            Padding = new(28, 32, 28, 28)
        };
        card.Children.Add(surface);
        closeButton = ActionButton(closeLabel, primary: false);
        closeButton.Width = closeButton.Height = 32;
        closeButton.Padding = new(0);
        closeButton.HorizontalAlignment = HorizontalAlignment.Right;
        closeButton.VerticalAlignment = VerticalAlignment.Top;
        closeButton.Margin = new(0, 22, 22, 0);
        closeButton.Content = new Glyph
        {
            Kind = "close",
            Width = 16,
            Height = 16,
            Foreground = Theme.Brush("#6B7380")
        };
        closeButton.Click += (_, _) => RequestDismiss();
        closeButton.TabIndex = 0;
        AutomationProperties.SetAutomationId(closeButton, "modal_close");
        card.Children.Add(closeButton);
        overlay.Children.Add(card);
        Content = overlay;

        void UpdateSize()
        {
            card.Width = Math.Max(0, Math.Min(maxWidth, ActualWidth - 64));
            card.MaxHeight = Math.Max(0, Math.Min(maxHeight, ActualHeight - 64));
        }

        SizeChanged += (_, _) => UpdateSize();
        Loaded += (_, _) =>
        {
            UpdateSize();
            closeButton.Focus(FocusState.Programmatic);
            _ = SetPresentedAsync(true);
        };
        PreviewKeyDown += (_, args) =>
        {
            if (args.Key == VirtualKey.Escape)
            {
                args.Handled = true;
                RequestDismiss();
            }
            else if (IsDismissing)
                args.Handled = true;
        };
    }

    private void RequestDismiss()
    {
        if (!IsDismissing)
            DismissRequested?.Invoke();
    }

    protected static Button ActionButton(
        string name,
        bool primary
    )
    {
        var fill = Theme.Brush(primary ? "#2F46E2" : "#00FFFFFF");
        var border = Theme.Brush("#002F46E2");
        var label = LoginTypography.Text(name, 13, primary ? "#FFFFFF" : "#6B7380");
        label.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        var button = new Button
        {
            Template = Theme.ButtonTemplate,
            Content = label,
            Background = fill,
            BorderBrush = border,
            BorderThickness = new(1),
            CornerRadius = new(primary ? 10 : 8),
            MinHeight = 0,
            MinWidth = 0,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            UseSystemFocusVisuals = false
        };
        AutomationProperties.SetName(button, AppText.Get(name));
        bool hot = false, pressed = false, keyboard = false;
        void Refresh()
        {
            LoginMotion.Color(
                button,
                fill,
                primary ? hot ? "#2438C4" : "#2F46E2" : hot ? "#F7F8FA" : "#00FFFFFF"
            );
            LoginMotion.Color(button, border, keyboard ? "#2F46E2" : "#002F46E2");
            LoginMotion.Opacity(button, !button.IsEnabled ? .5 : pressed ? .85 : 1);
        }
        button.PointerEntered += (_, _) =>
        {
            hot = true;
            Refresh();
        };
        button.PointerExited += (_, _) =>
        {
            hot = pressed = false;
            Refresh();
        };
        button.PointerPressed += (_, _) =>
        {
            pressed = true;
            Refresh();
        };
        button.PointerReleased += (_, _) =>
        {
            pressed = false;
            Refresh();
        };
        button.GotFocus += (_, _) =>
        {
            keyboard = button.FocusState == FocusState.Keyboard;
            Refresh();
        };
        button.LostFocus += (_, _) =>
        {
            keyboard = false;
            Refresh();
        };
        button.RegisterPropertyChangedCallback(IsEnabledProperty, (_, _) => Refresh());
        Refresh();
        return button;
    }

    internal Task SetPresentedAsync(
        bool visible
    )
    {
        if (disposed)
            return Task.CompletedTask;
        IsDismissing = !visible;
        if (IsDismissing)
        {
            Focus(FocusState.Programmatic);
            card.IsHitTestVisible = false;
            closeButton.IsTabStop = false;
        }
        double cardOpacity = card.Opacity, backdropOpacity = backdrop.Opacity, fromY = slide.Y;
        motion?.Stop();
        motionFinished?.TrySetResult();
        card.Opacity = backdrop.Opacity = visible ? 1 : 0;
        slide.Y = visible ? 0 : 24;
        if (!IsLoaded || !LoginMotion.Enabled)
            return Task.CompletedTask;
        var storyboard = new Storyboard { FillBehavior = FillBehavior.Stop };
        void Fade(
            DependencyObject target,
            double from
        )
        {
            var animation = new DoubleAnimation
            {
                From = from,
                To = visible ? 1 : 0,
                Duration = TimeSpan.FromSeconds(.3),
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
            };
            Storyboard.SetTarget(animation, target);
            Storyboard.SetTargetProperty(animation, "Opacity");
            storyboard.Children.Add(animation);
        }
        Fade(card, cardOpacity);
        Fade(backdrop, backdropOpacity);
        if (visible)
        {
            var animation = new DoubleAnimationUsingKeyFrames { EnableDependentAnimation = true };
            animation.KeyFrames.Add(new DiscreteDoubleKeyFrame
            {
                KeyTime = KeyTime.FromTimeSpan(TimeSpan.Zero),
                Value = fromY
            });
            animation.KeyFrames.Add(new SplineDoubleKeyFrame
            {
                KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromSeconds(.3)),
                Value = 0,
                KeySpline = new KeySpline { ControlPoint1 = new(.16, 1), ControlPoint2 = new(.3, 1) }
            });
            Storyboard.SetTarget(animation, slide);
            Storyboard.SetTargetProperty(animation, "Y");
            storyboard.Children.Add(animation);
        }
        else
        {
            var animation = new DoubleAnimation
            {
                From = fromY,
                To = 24,
                Duration = TimeSpan.FromSeconds(.3),
                EnableDependentAnimation = true,
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
            };
            Storyboard.SetTarget(animation, slide);
            Storyboard.SetTargetProperty(animation, "Y");
            storyboard.Children.Add(animation);
        }
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        motionFinished = completion;
        motion = storyboard;
        storyboard.Completed += (_, _) => completion.TrySetResult();
        storyboard.Begin();
        return completion.Task;
    }

    public virtual void Dispose()
    {
        if (disposed)
            return;
        disposed = true;
        motion?.Stop();
        motionFinished?.TrySetResult();
        DismissRequested = null;
    }
}
