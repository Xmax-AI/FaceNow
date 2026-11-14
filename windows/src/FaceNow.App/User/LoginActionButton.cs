//
//  LoginActionButton.cs
//  FaceNow
//

using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App.User;

/// <summary>
/// Presents a login action with pointer, focus, and loading feedback.
/// </summary>
internal sealed class LoginActionButton : Button
{
    private readonly TextBlock label = LoginTypography.Text();
    private readonly ActivitySpinner spinner = new() { Visibility = Visibility.Collapsed };
    private readonly SolidColorBrush surface = Theme.Brush("#2F46E2");
    private bool hovered, pressed, loading;
    private double scale = 1;

    internal string Text
    {
        get => label.Text;
        set
        {
            if (label.Text != value)
                label.Text = AppText.Get(value);
        }
    }

    internal LoginActionButton(
        string text
    )
    {
        Template = Theme.ButtonTemplate;
        UseSystemFocusVisuals = true;
        Background = surface;
        BorderThickness = new(0);
        MinHeight = MinWidth = 0;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        label.Text = AppText.Get(text);
        label.Foreground = Theme.Brush("#FFFFFF");
        label.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        label.TextAlignment = TextAlignment.Center;
        var content = new Grid();
        content.Children.Add(label);
        content.Children.Add(spinner);
        Content = content;
        label.HorizontalAlignment = HorizontalAlignment.Center;
        spinner.HorizontalAlignment = HorizontalAlignment.Center;
        spinner.VerticalAlignment = VerticalAlignment.Center;
        AutomationProperties.SetName(this, AppText.Get(text));
        PointerEntered += (_, _) =>
        {
            hovered = true;
            Refresh();
        };
        PointerExited += (_, _) =>
        {
            hovered = pressed = false;
            Refresh();
        };
        PointerPressed += (_, _) =>
        {
            pressed = true;
            Refresh();
        };
        PointerReleased += (_, _) =>
        {
            pressed = false;
            Refresh();
        };
        RegisterPropertyChangedCallback(IsEnabledProperty, (_, _) => Refresh());
        ApplyScale(1, false);
        Refresh();
    }

    internal void ApplyScale(
        double value,
        bool compact
    )
    {
        scale = value;
        Height = (compact ? 38 : 54) * scale;
        CornerRadius = new((compact ? 6 : 12) * scale);
        label.FontSize = (compact ? 12.5 : 16) * scale;
        Padding = new(0);
    }

    internal double PreferredWidth
    {
        get
        {
            label.Measure(new(double.PositiveInfinity, double.PositiveInfinity));
            return Math.Ceiling(label.DesiredSize.Width) + 24 * scale;
        }
    }

    internal void SetLoading(
        bool value
    )
    {
        if (loading == value)
            return;
        loading = value;
        spinner.IsActive = value;
        spinner.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
        label.Visibility = value ? Visibility.Collapsed : Visibility.Visible;
        AutomationProperties.SetItemStatus(this, value ? "Loading" : "");
        Refresh();
    }

    private void Refresh()
    {
        LoginMotion.Color(this, surface, hovered && IsEnabled ? "#2438C4" : "#2F46E2");
        LoginMotion.Opacity(this, loading ? .9 : !IsEnabled ? .65 : pressed ? .85 : 1);
    }
}
