//
//  AccountCard.cs
//  FaceNow
//

using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;

namespace FaceNow.App.User;

internal sealed class AccountAvatarButton : ToolbarButton
{
    internal AccountAvatarButton() : base(ToolbarButtonRole.Menu, ToolbarButtonTone.FilledAccent, circular: true)
    {
        VerticalAlignment = VerticalAlignment.Center;
        SetInitials("");
    }

    internal void SetInitials(
        string value
    )
    {
        SetValue(TextProperty, value);
        Glyph = value.Length == 0 ? "person" : "";
    }
}

/// <summary>A 340-point account card showing identity, credits, and four account actions.</summary>
internal sealed class AccountCard : UserControl
{
    private readonly AccountAvatarButton avatar = new() { IsHitTestVisible = false, IsTabStop = false };
    private readonly TextBlock title = LoginTypography.Text("", 13, "#6B7380");
    private readonly TextBlock credits = LoginTypography.Text("", 10.5, "#6B7380");
    private readonly Button recharge;
    private readonly Button signOut;
    private readonly Border highlight = new()
    {
        Height = 34,
        CornerRadius = new(12),
        Background = Theme.Brush("#F7F8FA"),
        VerticalAlignment = VerticalAlignment.Top,
        IsHitTestVisible = false,
        Opacity = 0
    };
    private readonly TranslateTransform highlightOffset = new();
    private Storyboard? highlightMotion;
    private int hovered = -1;
    internal Action? Recharge, Usage, Privacy, Agreement, SignOut;

    internal AccountCard()
    {
        Height = 238;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        var content = new Grid();
        content.RowDefinitions.Add(new()
        {
            Height = new(68)
        });
        content.RowDefinitions.Add(new()
        {
            Height = new(8)
        });
        content.RowDefinitions.Add(new()
        {
            Height = new(142)
        });
        var identity = new Grid
        {
            Background = Theme.Brush("#F7F8FA"),
            CornerRadius = new(12),
            Padding = new(12, 0, 12, 0),
            ColumnSpacing = 10
        };
        identity.ColumnDefinitions.Add(new()
        {
            Width = new(36)
        });
        identity.ColumnDefinitions.Add(new());
        identity.ColumnDefinitions.Add(new()
        {
            Width = new(88)
        });
        identity.Children.Add(avatar);
        var details = new StackPanel
        {
            Spacing = 4,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new(0, 0, 2, 0)
        };
        title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        title.TextTrimming = TextTrimming.CharacterEllipsis;
        title.IsTextSelectionEnabled = true;
        credits.TextTrimming = TextTrimming.CharacterEllipsis;
        details.Children.Add(title);
        details.Children.Add(credits);
        Grid.SetColumn(details, 1);
        identity.Children.Add(details);
        var buyLabel = LoginTypography.Text("Buy Credits", 11, "#FFFFFF");
        buyLabel.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        recharge = new Button
        {
            Template = Theme.ButtonTemplate,
            Width = 88,
            Height = 28,
            MinHeight = 0,
            MinWidth = 0,
            CornerRadius = new(8),
            Padding = new(0),
            BorderThickness = new(0),
            Background = Theme.Brush("#2F46E2"),
            Content = buyLabel,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        var buyFill = (SolidColorBrush)recharge.Background;
        LoginMotion.Color(recharge, buyFill, "#2F46E2");
        LoginMotion.Opacity(recharge, 1);
        recharge.PointerEntered += (_, _) => LoginMotion.Color(recharge, buyFill, "#2438C4");
        recharge.PointerExited += (_, _) =>
        {
            LoginMotion.Color(recharge, buyFill, "#2F46E2");
            LoginMotion.Opacity(recharge, recharge.IsEnabled ? 1 : .5);
        };
        recharge.PointerPressed += (_, _) => LoginMotion.Opacity(recharge, .85);
        recharge.PointerReleased += (_, _) => LoginMotion.Opacity(recharge, recharge.IsEnabled ? 1 : .5);
        recharge.RegisterPropertyChangedCallback(
            IsEnabledProperty,
            (_, _) => LoginMotion.Opacity(
            recharge,
            recharge.IsEnabled ? 1 : .5
        )
        );
        recharge.Click += (_, _) => Recharge?.Invoke();
        AutomationProperties.SetName(recharge, "Buy Credits");
        Grid.SetColumn(recharge, 2);
        identity.Children.Add(recharge);
        content.Children.Add(identity);
        var actions = new Grid { RowSpacing = 2 };
        highlight.RenderTransform = highlightOffset;
        LoginMotion.Opacity(highlight, 0);
        Grid.SetRowSpan(highlight, 4);
        actions.Children.Add(highlight);
        Button ActionRow(
            string label,
            string glyph,
            int index,
            Action clicked
        )
        {
            actions.RowDefinitions.Add(new()
            {
                Height = new(34)
            });
            var row = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 10,
                VerticalAlignment = VerticalAlignment.Center
            };
            row.Children.Add(new Glyph
            {
                Kind = glyph,
                Width = 16,
                Height = 16,
                Foreground = Theme.Brush("#6B7380"),
                VerticalAlignment = VerticalAlignment.Center
            });
            row.Children.Add(LoginTypography.Text(label, 13, "#6B7380"));
            var button = new Button
            {
                Template = Theme.ButtonTemplate,
                Content = row,
                Background = Theme.Brush("#00FFFFFF"),
                BorderThickness = new(0),
                CornerRadius = new(12),
                Padding = new(12, 0, 12, 0),
                MinHeight = 0,
                MinWidth = 0,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                VerticalContentAlignment = VerticalAlignment.Center,
                UseSystemFocusVisuals = false
            };
            AutomationProperties.SetName(button, label);
            button.Click += (_, _) => clicked();
            LoginMotion.Opacity(button, 1);
            button.PointerEntered += (_, _) => { if (button.IsEnabled) MoveHighlight(index); };
            button.PointerExited += (_, _) => { if (hovered == index) MoveHighlight(-1); };
            button.GotFocus += (_, _) => { if (button.FocusState == FocusState.Keyboard) MoveHighlight(index); };
            button.LostFocus += (_, _) => { if (hovered == index) MoveHighlight(-1); };
            button.PointerPressed += (_, _) => LoginMotion.Opacity(button, .85);
            button.PointerReleased += (_, _) => LoginMotion.Opacity(button, button.IsEnabled ? 1 : .5);
            button.RegisterPropertyChangedCallback(
                IsEnabledProperty,
                (_, _) => LoginMotion.Opacity(
                button,
                button.IsEnabled ? 1 : .5
            )
            );
            Grid.SetRow(button, index);
            actions.Children.Add(button);
            return button;
        }
        ActionRow("View Usage", "statistics", 0, () => Usage?.Invoke());
        ActionRow("Privacy Policy", "privacy", 1, () => Privacy?.Invoke());
        ActionRow("Terms of Use", "document", 2, () => Agreement?.Invoke());
        signOut = ActionRow("Sign out", "logout", 3, () => SignOut?.Invoke());
        Grid.SetRow(actions, 2);
        content.Children.Add(actions);
        Content = new Border
        {
            Background = Theme.Brush("#FFFFFF"),
            CornerRadius = new(16),
            Padding = new(10),
            Child = content
        };
        Unloaded += (_, _) =>
        {
            highlightMotion?.Stop();
            highlight.Opacity = 0;
            hovered = -1;
        };
    }

    internal void Update(
        AccountPresentation value,
        bool canRecharge,
        bool canSignOut
    )
    {
        avatar.SetInitials(value.AvatarText);
        title.Text = value.Title;
        credits.Text = AppText.Get("Credits: ") + value.Credits;
        ToolTipService.SetToolTip(title, value.Title);
        recharge.IsEnabled = canRecharge;
        signOut.IsEnabled = canSignOut;
    }

    private void MoveHighlight(
        int index
    )
    {
        if (hovered == index)
            return;
        hovered = index;
        LoginMotion.Opacity(highlight, index < 0 ? 0 : 1);
        if (index < 0)
            return;
        double current = highlightOffset.Y, target = index * 36;
        highlightMotion?.Stop();
        highlightOffset.Y = target;
        if (!IsLoaded || !LoginMotion.Enabled || Math.Abs(current - target) < .01)
            return;
        var animation = new DoubleAnimation
        {
            From = current,
            To = target,
            Duration = TimeSpan.FromSeconds(.3),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut },
            EnableDependentAnimation = true
        };
        Storyboard.SetTarget(animation, highlightOffset);
        Storyboard.SetTargetProperty(animation, "Y");
        highlightMotion = new Storyboard { FillBehavior = FillBehavior.Stop };
        highlightMotion.Children.Add(animation);
        highlightMotion.Begin();
    }
}
