//
//  CreditsWarningCard.cs
//  FaceNow
//

using FaceNow.App.Controls;
using FaceNow.Core.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace FaceNow.App.User;

/// <summary>Prompts the user to top up when their credits are exhausted.</summary>
internal sealed class CreditsWarningCard : UserControl
{
    internal CreditsWarningCard(
        Action recharge
    )
    {
        var body = new StackPanel();
        var header = new Grid { ColumnSpacing = 10, Margin = new(0, 0, 0, 14) };
        header.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        header.Children.Add(new Border
        {
            Width = 32,
            Height = 32,
            CornerRadius = new(9),
            Background = Theme.Brush("#FDF2F2"),
            BorderBrush = Theme.Brush("#F1BABA"),
            BorderThickness = new(1),
            Child = new Glyph
            {
                Kind = "warningTriangle",
                Width = 16,
                Height = 16,
                Foreground = Theme.Brush("#DC2626")
            }
        });
        var title = LoginTypography.Text(CreditPolicy.InsufficientMessage, 14);
        title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        title.VerticalAlignment = VerticalAlignment.Center;
        title.TextWrapping = TextWrapping.Wrap;
        Grid.SetColumn(title, 1);
        header.Children.Add(title);
        body.Children.Add(header);
        var label = LoginTypography.Text("Top Up", 12, "#FFFFFF");
        label.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        var fill = Theme.Brush("#2F46E2");
        var buy = new Button
        {
            Template = Theme.ButtonTemplate,
            Height = 32,
            MinHeight = 0,
            Padding = new(0),
            CornerRadius = new(8),
            BorderThickness = new(0),
            Background = fill,
            Content = label,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center
        };
        LoginMotion.Color(buy, fill, "#2F46E2");
        LoginMotion.Opacity(buy, 1);
        buy.PointerEntered += (_, _) => LoginMotion.Color(buy, fill, "#2438C4");
        buy.PointerExited += (_, _) =>
        {
            LoginMotion.Color(buy, fill, "#2F46E2");
            LoginMotion.Opacity(buy, 1);
        };
        buy.PointerPressed += (_, _) => LoginMotion.Opacity(buy, .85);
        buy.PointerReleased += (_, _) => LoginMotion.Opacity(buy, 1);
        buy.Click += (_, _) => recharge();
        AutomationProperties.SetName(buy, label.Text);
        body.Children.Add(buy);
        Content = body;
    }
}
