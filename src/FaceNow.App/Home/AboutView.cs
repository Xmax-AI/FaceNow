using FaceNow.App.Controls;
using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.System;

namespace FaceNow.App.Home;

/// <summary>Static, scrolling product information in the same modal geometry as macOS.</summary>
internal sealed class AboutView : UserControl, IDisposable
{
    private readonly Border backdrop = new() { Background = Theme.Brush("#59000000"), Opacity = 0 };
    private readonly Grid card = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Opacity = 0 };
    private readonly ScrollViewer scroll = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        HorizontalScrollMode = ScrollMode.Disabled, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        VerticalScrollMode = ScrollMode.Enabled, ZoomMode = ZoomMode.Disabled, IsTabStop = false };
    private readonly TranslateTransform slide = new() { Y = 24 };
    private readonly Button closeButton, contactButton;
    private Storyboard? motion;
    private TaskCompletionSource? motionFinished;
    private bool dismissing, disposed;
    internal Action? RequestDismiss, Contact;

    internal AboutView()
    {
        HorizontalContentAlignment = HorizontalAlignment.Stretch; VerticalContentAlignment = VerticalAlignment.Stretch;
        HorizontalAlignment = HorizontalAlignment.Stretch; VerticalAlignment = VerticalAlignment.Stretch;
        IsTabStop = true; UseSystemFocusVisuals = false; TabFocusNavigation = KeyboardNavigationMode.Cycle;
        AutomationProperties.SetName(this, "About Us"); AutomationProperties.SetIsDialog(this, true);
        var overlay = new Grid { Background = Theme.Brush("#00FFFFFF") }; overlay.Children.Add(backdrop);
        backdrop.Tapped += (_, args) => { args.Handled = true; if (!dismissing) RequestDismiss?.Invoke(); };
        card.RenderTransform = slide;
        var shadow = new Grid { IsHitTestVisible = false };
        _ = new LoginShadow(shadow, () => 22, Microsoft.UI.Colors.Black, 28, 8, .16f);
        card.Children.Add(shadow);
        var content = new StackPanel { Spacing = 28 };
        var intro = new StackPanel { Spacing = 18 };
        intro.Children.Add(Paragraph(AboutContent.ModelTitle, 28, semibold: true));
        intro.Children.Add(Paragraph(AboutContent.Introduction, 15, "#6B7380")); content.Children.Add(intro);
        var advantages = new StackPanel { Spacing = 14 };
        advantages.Children.Add(Paragraph(AboutContent.AdvantagesTitle, 18, semibold: true));
        var row = new Grid { ColumnSpacing = 12 };
        foreach (var item in AboutContent.Advantages)
        {
            int index = row.ColumnDefinitions.Count; row.ColumnDefinitions.Add(new());
            var advantage = Advantage(item.Icon, item.Title, item.Metric, item.Detail);
            Grid.SetColumn(advantage, index); row.Children.Add(advantage);
        }
        advantages.Children.Add(row); content.Children.Add(advantages);
        var partnership = new StackPanel();
        partnership.Children.Add(Paragraph(AboutContent.PartnershipTitle, 21, semibold: true));
        var description = Paragraph(AboutContent.PartnershipDetail, 15, "#6B7380"); description.Margin = new(0, 12, 0, 0);
        partnership.Children.Add(description);
        var contactRow = new Grid { ColumnSpacing = 14, Margin = new(0, 20, 0, 0) };
        contactRow.ColumnDefinitions.Add(new() { Width = GridLength.Auto }); contactRow.ColumnDefinitions.Add(new());
        contactButton = ActionButton("Contact Us", primary: true);
        contactButton.Height = 40; contactButton.Padding = new(18, 0, 18, 0); contactButton.HorizontalAlignment = HorizontalAlignment.Left;
        contactButton.Click += (_, _) => { if (!dismissing) Contact?.Invoke(); }; contactButton.TabIndex = 1;
        contactRow.Children.Add(contactButton);
        var caption = Paragraph(AboutContent.ContactDetail, 12, "#6B7380"); caption.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(caption, 1); contactRow.Children.Add(caption); partnership.Children.Add(contactRow);
        content.Children.Add(new Border { Background = Theme.Brush("#092F46E2"), CornerRadius = new(18), Padding = new(22), Child = partnership });
        scroll.Content = content;
        card.Children.Add(new Border { Background = Theme.Brush("#FFFFFF"), CornerRadius = new(22), Padding = new(28, 32, 28, 28), Child = scroll });
        closeButton = ActionButton("Close About Us", primary: false);
        closeButton.Width = closeButton.Height = 32; closeButton.HorizontalAlignment = HorizontalAlignment.Right;
        closeButton.VerticalAlignment = VerticalAlignment.Top; closeButton.Margin = new(0, 22, 22, 0);
        closeButton.Content = new Glyph { Kind = "close", Width = 16, Height = 16, Foreground = Theme.Brush("#6B7380") };
        closeButton.Click += (_, _) => { if (!dismissing) RequestDismiss?.Invoke(); }; closeButton.TabIndex = 0;
        card.Children.Add(closeButton); overlay.Children.Add(card); Content = overlay;
        SizeChanged += (_, _) => UpdateSize();
        Loaded += (_, _) => { UpdateSize(); closeButton.Focus(FocusState.Programmatic); _ = SetPresentedAsync(true); };
        PreviewKeyDown += (_, args) =>
        {
            if (args.Key == VirtualKey.Escape) { args.Handled = true; if (!dismissing) RequestDismiss?.Invoke(); }
            else if (dismissing) args.Handled = true;
        };
    }

    private void UpdateSize()
    {
        card.Width = Math.Max(0, Math.Min(980, ActualWidth - 64));
        card.MaxHeight = Math.Max(0, Math.Min(760, ActualHeight - 64));
        scroll.MaxHeight = Math.Max(0, card.MaxHeight - 60);
    }

    private static TextBlock Paragraph(string text, double size, string color = "#111318", bool semibold = false)
    {
        var label = LoginTypography.Text(text, size, color); label.TextWrapping = TextWrapping.Wrap;
        label.VerticalAlignment = VerticalAlignment.Top; label.IsTextSelectionEnabled = true;
        if (semibold) label.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        return label;
    }

    private static Border Advantage(string icon, string title, string metric, string detail)
    {
        var content = new StackPanel();
        var header = new Grid { ColumnSpacing = 10, Margin = new(0, 0, 0, 16) };
        header.ColumnDefinitions.Add(new() { Width = new(32) }); header.ColumnDefinitions.Add(new());
        header.Children.Add(new Border { Width = 32, Height = 32, CornerRadius = new(9), Background = Theme.Brush("#0F2F46E2"),
            Child = new Glyph { Kind = icon, Width = 16, Height = 16, Foreground = Theme.Brush("#2F46E2"),
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } });
        var heading = Paragraph(title, 14, "#6B7380"); heading.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        heading.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(heading, 1); header.Children.Add(heading); content.Children.Add(header);
        var number = Paragraph(metric, 30, semibold: true); number.Height = 40; number.VerticalAlignment = VerticalAlignment.Center;
        number.TextWrapping = TextWrapping.NoWrap; number.Margin = new(0, 0, 0, 12); content.Children.Add(number);
        var description = Paragraph(detail, 13, "#6B7380"); description.LineHeight = 20; content.Children.Add(description);
        return new Border { Background = Theme.Brush("#FFFFFF"), CornerRadius = new(14), BorderThickness = new(1),
            BorderBrush = Theme.Brush("#CCE5E7EB"), Padding = new(20), Child = content, VerticalAlignment = VerticalAlignment.Stretch };
    }

    private static Button ActionButton(string name, bool primary)
    {
        var fill = Theme.Brush(primary ? "#2F46E2" : "#00FFFFFF");
        var border = Theme.Brush("#002F46E2");
        var label = LoginTypography.Text(name, 13, primary ? "#FFFFFF" : "#6B7380"); label.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        var button = new Button { Template = Theme.ButtonTemplate, Content = label, Background = fill, BorderBrush = border,
            BorderThickness = new(1), CornerRadius = new(primary ? 10 : 8), MinHeight = 0, MinWidth = 0,
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center, UseSystemFocusVisuals = false };
        AutomationProperties.SetName(button, name);
        bool hot = false, pressed = false, keyboard = false;
        void Refresh()
        {
            LoginMotion.Color(button, fill, primary ? hot ? "#2438C4" : "#2F46E2" : hot ? "#F7F8FA" : "#00FFFFFF");
            LoginMotion.Color(button, border, keyboard ? "#2F46E2" : "#002F46E2");
            LoginMotion.Opacity(button, !button.IsEnabled ? .5 : pressed ? .85 : 1);
        }
        button.PointerEntered += (_, _) => { hot = true; Refresh(); };
        button.PointerExited += (_, _) => { hot = pressed = false; Refresh(); };
        button.PointerPressed += (_, _) => { pressed = true; Refresh(); };
        button.PointerReleased += (_, _) => { pressed = false; Refresh(); };
        button.GotFocus += (_, _) => { keyboard = button.FocusState == FocusState.Keyboard; Refresh(); };
        button.LostFocus += (_, _) => { keyboard = false; Refresh(); };
        button.RegisterPropertyChangedCallback(IsEnabledProperty, (_, _) => Refresh()); Refresh();
        return button;
    }

    internal Task SetPresentedAsync(bool visible)
    {
        if (disposed) return Task.CompletedTask;
        dismissing = !visible;
        if (dismissing) { Focus(FocusState.Programmatic); card.IsHitTestVisible = false; closeButton.IsTabStop = contactButton.IsTabStop = false; }
        double cardOpacity = card.Opacity, backdropOpacity = backdrop.Opacity, fromY = slide.Y;
        motion?.Stop(); motionFinished?.TrySetResult();
        card.Opacity = backdrop.Opacity = visible ? 1 : 0; slide.Y = visible ? 0 : 24;
        if (!IsLoaded || !LoginMotion.Enabled) return Task.CompletedTask;
        var storyboard = new Storyboard { FillBehavior = FillBehavior.Stop };
        void Fade(DependencyObject target, double from)
        {
            var animation = new DoubleAnimation { From = from, To = visible ? 1 : 0, Duration = TimeSpan.FromSeconds(.3),
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
            Storyboard.SetTarget(animation, target); Storyboard.SetTargetProperty(animation, "Opacity"); storyboard.Children.Add(animation);
        }
        Fade(card, cardOpacity); Fade(backdrop, backdropOpacity);
        if (visible)
        {
            var animation = new DoubleAnimationUsingKeyFrames { EnableDependentAnimation = true };
            animation.KeyFrames.Add(new DiscreteDoubleKeyFrame { KeyTime = KeyTime.FromTimeSpan(TimeSpan.Zero), Value = fromY });
            animation.KeyFrames.Add(new SplineDoubleKeyFrame { KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromSeconds(.3)), Value = 0,
                KeySpline = new KeySpline { ControlPoint1 = new(.16, 1), ControlPoint2 = new(.3, 1) } });
            Storyboard.SetTarget(animation, slide); Storyboard.SetTargetProperty(animation, "Y"); storyboard.Children.Add(animation);
        }
        else
        {
            var animation = new DoubleAnimation { From = fromY, To = 24, Duration = TimeSpan.FromSeconds(.3), EnableDependentAnimation = true,
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
            Storyboard.SetTarget(animation, slide); Storyboard.SetTargetProperty(animation, "Y"); storyboard.Children.Add(animation);
        }
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        motionFinished = completion; motion = storyboard; storyboard.Completed += (_, _) => completion.TrySetResult(); storyboard.Begin();
        return completion.Task;
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true; motion?.Stop(); motionFinished?.TrySetResult(); RequestDismiss = Contact = null;
    }
}
