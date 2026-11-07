using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace FaceNow.App.User;

/// <summary>Contents of the 280-point low-credit popover with 16-point outer insets.</summary>
internal sealed class CreditsWarningCard : UserControl
{
    internal CreditsWarningCard(Action recharge)
    {
        var body = new StackPanel();
        var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        header.Children.Add(new Border
        {
            Width = 32, Height = 32, CornerRadius = new(9), Background = Theme.Brush("#FDF2F2"),
            BorderBrush = Theme.Brush("#F1BABA"), BorderThickness = new(1),
            Child = new Glyph { Kind = "warningTriangle", Width = 16, Height = 16, Foreground = Theme.Brush("#DC2626") }
        });
        var title = LoginTypography.Text("Low credits", 14);
        title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        title.VerticalAlignment = VerticalAlignment.Center;
        header.Children.Add(title); body.Children.Add(header);
        var message = LoginTypography.Text("You're running low on credits. Top up to avoid interruptions.", 12, "#6B7380");
        message.TextWrapping = TextWrapping.Wrap; message.Margin = new(0, 12, 0, 14);
        body.Children.Add(message);
        var label = LoginTypography.Text("Buy Credits", 12, "#FFFFFF");
        label.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        var fill = Theme.Brush("#2F46E2");
        var buy = new Button
        {
            Template = Theme.ButtonTemplate, Height = 32, MinHeight = 0, Padding = new(0),
            CornerRadius = new(8), BorderThickness = new(0), Background = fill, Content = label,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center
        };
        LoginMotion.Color(buy, fill, "#2F46E2"); LoginMotion.Opacity(buy, 1);
        buy.PointerEntered += (_, _) => LoginMotion.Color(buy, fill, "#2438C4");
        buy.PointerExited += (_, _) => { LoginMotion.Color(buy, fill, "#2F46E2"); LoginMotion.Opacity(buy, 1); };
        buy.PointerPressed += (_, _) => LoginMotion.Opacity(buy, .85);
        buy.PointerReleased += (_, _) => LoginMotion.Opacity(buy, 1);
        buy.Click += (_, _) => recharge();
        AutomationProperties.SetName(buy, "Buy Credits");
        body.Children.Add(buy); Content = body;
    }
}
