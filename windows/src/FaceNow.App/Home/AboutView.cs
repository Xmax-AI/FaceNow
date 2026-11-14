//
//  AboutView.cs
//  FaceNow
//

using FaceNow.App.Controls;
using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace FaceNow.App.Home;

/// <summary>Scrollable product information displayed in a modal dialog.</summary>
internal sealed class AboutView : ModalView
{
    internal Action? Contact;

    internal AboutView() : base("About Us", "Close About Us", 980, 760)
    {
        var content = new StackPanel { Spacing = 28 };
        var intro = new StackPanel { Spacing = 18 };
        intro.Children.Add(Paragraph(AboutContent.ModelTitle, 28, semibold: true));
        intro.Children.Add(Paragraph(AboutContent.Introduction, 15, "#6B7380"));
        content.Children.Add(intro);
        var advantages = new StackPanel { Spacing = 14 };
        advantages.Children.Add(Paragraph(AboutContent.AdvantagesTitle, 18, semibold: true));
        var row = new Grid { ColumnSpacing = 12 };
        foreach (var item in AboutContent.Advantages)
        {
            int index = row.ColumnDefinitions.Count;
            row.ColumnDefinitions.Add(new());
            var advantage = Advantage(item.Icon, item.Title, item.Metric, item.Detail);
            Grid.SetColumn(advantage, index);
            row.Children.Add(advantage);
        }
        advantages.Children.Add(row);
        content.Children.Add(advantages);
        var partnership = new StackPanel();
        partnership.Children.Add(Paragraph(AboutContent.PartnershipTitle, 21, semibold: true));
        var description = Paragraph(AboutContent.PartnershipDetail, 15, "#6B7380");
        description.Margin = new(0, 12, 0, 0);
        partnership.Children.Add(description);
        var contactRow = new Grid { ColumnSpacing = 14, Margin = new(0, 20, 0, 0) };
        contactRow.ColumnDefinitions.Add(new()
        {
            Width = GridLength.Auto
        });
        contactRow.ColumnDefinitions.Add(new());
        var contactButton = ActionButton("Contact Us", primary: true);
        contactButton.Height = 40;
        contactButton.Padding = new(18, 0, 18, 0);
        contactButton.HorizontalAlignment = HorizontalAlignment.Left;
        contactButton.Click += (_, _) => { if (!IsDismissing) Contact?.Invoke(); };
        contactButton.TabIndex = 1;
        contactRow.Children.Add(contactButton);
        var caption = Paragraph(AboutContent.ContactDetail, 12, "#6B7380");
        caption.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(caption, 1);
        contactRow.Children.Add(caption);
        partnership.Children.Add(contactRow);
        content.Children.Add(new Border
        {
            Background = Theme.Brush("#092F46E2"),
            CornerRadius = new(18),
            Padding = new(22),
            Child = partnership
        });
        var scroll = new ScrollViewer
        {
            Content = content,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            HorizontalScrollMode = ScrollMode.Disabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollMode = ScrollMode.Enabled,
            ZoomMode = ZoomMode.Disabled,
            IsTabStop = false
        };
        Body = scroll;
        SizeChanged += (_, _) => scroll.MaxHeight = BodyMaxHeight;
        Loaded += (_, _) => scroll.MaxHeight = BodyMaxHeight;
    }

    private static TextBlock Paragraph(
        string text,
        double size,
        string color = "#111318",
        bool semibold = false
    )
    {
        var label = LoginTypography.Text(text, size, color);
        label.TextWrapping = TextWrapping.Wrap;
        label.VerticalAlignment = VerticalAlignment.Top;
        label.IsTextSelectionEnabled = true;
        if (semibold)
            label.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        return label;
    }

    private static Border Advantage(
        string icon,
        string title,
        string metric,
        string detail
    )
    {
        var content = new StackPanel();
        var header = new Grid { ColumnSpacing = 10, Margin = new(0, 0, 0, 16) };
        header.ColumnDefinitions.Add(new()
        {
            Width = new(32)
        });
        header.ColumnDefinitions.Add(new());
        header.Children.Add(new Border
        {
            Width = 32,
            Height = 32,
            CornerRadius = new(9),
            Background = Theme.Brush("#0F2F46E2"),
            Child = new Glyph
            {
                Kind = icon,
                Width = 16,
                Height = 16,
                Foreground = Theme.Brush("#2F46E2"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        });
        var heading = Paragraph(title, 14, "#6B7380");
        heading.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        heading.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(heading, 1);
        header.Children.Add(heading);
        content.Children.Add(header);
        var number = Paragraph(metric, 30, semibold: true);
        number.Height = 40;
        number.VerticalAlignment = VerticalAlignment.Center;
        number.TextWrapping = TextWrapping.NoWrap;
        number.Margin = new(0, 0, 0, 12);
        content.Children.Add(number);
        var description = Paragraph(detail, 13, "#6B7380");
        description.LineHeight = 20;
        content.Children.Add(description);
        return new Border
        {
            Background = Theme.Brush("#FFFFFF"),
            CornerRadius = new(14),
            BorderThickness = new(1),
            BorderBrush = Theme.Brush("#CCE5E7EB"),
            Padding = new(20),
            Child = content,
            VerticalAlignment = VerticalAlignment.Stretch
        };
    }

    public override void Dispose()
    {
        Contact = null;
        base.Dispose();
    }
}
