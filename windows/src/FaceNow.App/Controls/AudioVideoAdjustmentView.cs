//
//  AudioVideoAdjustmentView.cs
//  FaceNow
//

using System.Globalization;
using FaceNow.Windows.Media;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace FaceNow.App.Controls;

internal sealed class AudioVideoAdjustmentView : UserControl
{
    internal const string Title = "Audio & Video";
    private const int OffsetLimit = MeetingOutputTiming.OffsetLimit;
    private static readonly FontFamily SystemFont = new("Segoe UI");
    // Keep the native Slider parts so pointer, keyboard, and automation use the same range.
    private static readonly ControlTemplate OffsetSliderTemplate = (ControlTemplate)XamlReader.Load("""
        <ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                         xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Slider">
            <Grid x:Name="SliderContainer" Background="Transparent">
                <Grid x:Name="HorizontalTemplate">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="*" />
                    </Grid.ColumnDefinitions>
                    <Rectangle Grid.ColumnSpan="3" Height="6" RadiusX="3" RadiusY="3" Fill="{TemplateBinding Background}" />
                    <Rectangle x:Name="HorizontalDecreaseRect" Height="6" RadiusX="3" RadiusY="3" Fill="{TemplateBinding Foreground}" />
                    <Thumb x:Name="HorizontalThumb" Grid.Column="1" Width="18" Height="18" AutomationProperties.AccessibilityView="Raw">
                        <Thumb.Template>
                            <ControlTemplate TargetType="Thumb">
                                <Ellipse Fill="White" Stroke="#2F46E2" StrokeThickness="1.5" />
                            </ControlTemplate>
                        </Thumb.Template>
                    </Thumb>
                </Grid>
            </Grid>
        </ControlTemplate>
        """);
    private readonly Button closeButton;

    internal AudioVideoAdjustmentView(
        int initialOffset,
        bool preview,
        Action<int> offsetChanged,
        Action close
    )
    {
        AutomationProperties.SetName(this, AppText.Get(Title));
        var content = new StackPanel();
        Content = content;

        closeButton = new Button
        {
            Content = new Glyph
            {
                Kind = "close",
                Width = 18,
                Height = 18,
                Foreground = Theme.Brush("#6B7380")
            },
            Width = 30,
            Height = 30,
            MinWidth = 0,
            MinHeight = 0,
            Padding = new(0),
            BorderThickness = new(0),
            Background = Theme.Brush("#00FFFFFF"),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        AutomationProperties.SetName(closeButton, AppText.Get("Close audio and video adjustments"));
        closeButton.Click += (_, _) => close();
        var header = new Grid();
        header.Children.Add(Label(Title, 22, strong: true));
        header.Children.Add(closeButton);
        content.Children.Add(header);

        var automatic = new Grid { Margin = new(0, 30, 0, 0) };
        automatic.Children.Add(Label("Automatic A/V Sync", 16, strong: true));
        automatic.Children.Add(new Border
        {
            Background = Theme.Brush(preview ? "#F3F4F6" : "#E8F6ED"),
            CornerRadius = new(10),
            Padding = new(9, 3, 9, 3),
            HorizontalAlignment = HorizontalAlignment.Right,
            Child = Label(preview ? "Preview" : "Enabled", 12, strong: true, secondary: preview)
        });
        content.Children.Add(automatic);
        var automaticHint = Label("Automatically align audio with generated video", secondary: true);
        automaticHint.Margin = new(0, 6, 0, 0);
        content.Children.Add(automaticHint);
        content.Children.Add(new Border
        {
            Height = 1,
            Margin = new(0, 18, 0, 18),
            Background = Theme.Brush("#E5E7EB")
        });

        content.Children.Add(Label("Manual Sync Offset", 16, strong: true));
        var manualHint = Label("Fine-tune the automatic synchronization", secondary: true);
        manualHint.Margin = new(0, 6, 0, 0);
        content.Children.Add(manualHint);
        var slider = new Slider
        {
            Template = OffsetSliderTemplate,
            Minimum = -OffsetLimit,
            Maximum = OffsetLimit,
            StepFrequency = 1,
            LargeChange = 100,
            Height = 26,
            MinHeight = 0,
            Margin = new(0, 20, 0, 0),
            IsThumbToolTipEnabled = false,
            Background = Theme.Brush("#D6D9E2"),
            Foreground = Theme.Brush("#2F46E2")
        };
        AutomationProperties.SetName(slider, AppText.Get("Manual Sync Offset"));
        content.Children.Add(slider);

        var sliderLabels = new Grid { Margin = new(0, 4, 0, 0) };
        var offsetLabel = Label("", strong: true);
        offsetLabel.HorizontalAlignment = HorizontalAlignment.Center;
        var later = Label("Audio later", secondary: true);
        later.HorizontalAlignment = HorizontalAlignment.Right;
        sliderLabels.Children.Add(Label("Audio earlier", secondary: true));
        sliderLabels.Children.Add(offsetLabel);
        sliderLabels.Children.Add(later);
        content.Children.Add(sliderLabels);

        var editor = new TextBox
        {
            Width = 126,
            Height = 32,
            MinHeight = 0,
            Padding = new(11, 4, 36, 4),
            FontFamily = SystemFont,
            FontSize = 14,
            BorderThickness = new(1),
            CornerRadius = new(7),
            BorderBrush = Theme.Brush("#E5E7EB"),
            Background = Theme.Brush("#FFFFFF"),
            IsSpellCheckEnabled = false,
            IsTextPredictionEnabled = false
        };
        AutomationProperties.SetName(editor, AppText.Get("Offset"));
        AutomationProperties.SetHelpText(editor, "−5000 … 5000 ms");
        var unit = Label("ms", 14, secondary: true);
        unit.HorizontalAlignment = HorizontalAlignment.Right;
        unit.Margin = new(0, 0, 12, 0);
        unit.IsHitTestVisible = false;
        var input = new Grid { Children = { editor, unit } };
        var reset = new Button
        {
            Content = Label("Reset", 13),
            Width = 82,
            Height = 32,
            MinHeight = 0,
            Padding = new(0),
            CornerRadius = new(7),
            Background = Theme.Brush("#FFFFFF"),
            BorderBrush = Theme.Brush("#E5E7EB"),
            BorderThickness = new(1)
        };
        content.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 18,
            Margin = new(0, 24, 0, 0),
            Children = { Label("Offset", 14), input, reset }
        });
        var footer = Label(
            preview ? "Preview only. Changes do not affect meeting output." : "Adjustments apply to meeting output",
            secondary: true
        );
        footer.Margin = new(0, 24, 0, 0);
        content.Children.Add(footer);

        int offset = initialOffset;
        bool updating = false;
        void DisplayOffset(
            int value,
            bool updateEditor = true
        )
        {
            value = Math.Clamp(value, -OffsetLimit, OffsetLimit);
            string text = value.ToString(CultureInfo.InvariantCulture);
            updating = true;
            slider.Value = value;
            if (updateEditor)
                editor.Text = text;
            offsetLabel.Text = $"{text} ms";
            updating = false;
            if (offset == value)
                return;
            offset = value;
            offsetChanged(value);
        }
        bool ReadOffset(
            out int value
        ) => int.TryParse(
            editor.Text,
            NumberStyles.Integer,
            CultureInfo.InvariantCulture,
            out value
        );
        void Commit() => DisplayOffset(ReadOffset(out int value) ? value : offset);

        DisplayOffset(initialOffset);
        slider.ValueChanged += (_, args) => { if (!updating) DisplayOffset((int)Math.Round(args.NewValue)); };
        editor.TextChanged += (_, _) =>
        {
            if (!updating && ReadOffset(out int value) && value is >= -OffsetLimit and <= OffsetLimit)
                DisplayOffset(value, updateEditor: false);
        };
        editor.LostFocus += (_, _) => Commit();
        editor.KeyDown += (_, args) =>
        {
            if (args.Key == VirtualKey.Enter)
            {
                Commit();
                args.Handled = true;
            }
        };
        reset.Click += (_, _) => DisplayOffset(0);
        KeyDown += (_, args) =>
        {
            if (args.Key == VirtualKey.Escape)
            {
                close();
                args.Handled = true;
            }
        };
    }

    internal void FocusCloseButton() => closeButton.Focus(FocusState.Programmatic);

    private static TextBlock Label(
        string text,
        double size = 13,
        bool strong = false,
        bool secondary = false
    )
    {
        var label = Theme.Text(text, size, secondary ? "#6B7380" : "#111318");
        label.FontFamily = SystemFont;
        label.FontWeight = strong ? FontWeights.SemiBold : FontWeights.Normal;
        label.TextWrapping = TextWrapping.Wrap;
        return label;
    }
}
