//
//  BeautyPanel.cs
//  FaceNow
//

using FaceNow.Core.Media;
using FaceNow.App.User;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;

namespace FaceNow.App.Controls;

internal sealed class BeautyPanel : UserControl
{
    private const double Inset = 10, DisclosureSize = 22, TitleSpacing = 4;
    private const double TrackWidth = 90, ValueWidth = 30, ColumnSpacing = 6;
    private static readonly FontFamily SystemFont = new("Segoe UI");
    private static readonly ControlTemplate DisclosureTemplate = (ControlTemplate)XamlReader.Load("""
        <ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
            <Border xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" x:Name="Surface" Background="Transparent" CornerRadius="4">
                <VisualStateManager.VisualStateGroups>
                    <VisualStateGroup x:Name="CommonStates">
                        <VisualState x:Name="Normal" />
                        <VisualState x:Name="PointerOver">
                            <VisualState.Setters><Setter Target="Surface.Background" Value="#1FFFFFFF" /></VisualState.Setters>
                        </VisualState>
                        <VisualState x:Name="Pressed">
                            <VisualState.Setters><Setter Target="Surface.Background" Value="#33FFFFFF" /></VisualState.Setters>
                        </VisualState>
                    </VisualStateGroup>
                </VisualStateManager.VisualStateGroups>
                <ContentPresenter Content="{TemplateBinding Content}" HorizontalContentAlignment="Center" VerticalContentAlignment="Center" />
            </Border>
        </ControlTemplate>
        """);
    // Keep the native slider's track and thumb parts for pointer and keyboard input.
    private static readonly ControlTemplate SliderTemplate = (ControlTemplate)XamlReader.Load("""
        <ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                         xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Slider">
            <Grid x:Name="SliderContainer" Background="Transparent">
                <Grid x:Name="HorizontalTemplate">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="*" />
                    </Grid.ColumnDefinitions>
                    <Rectangle x:Name="HorizontalDecreaseRect" Opacity="0" IsHitTestVisible="False" />
                    <Thumb x:Name="HorizontalThumb" Grid.Column="1" Width="16" Height="12" AutomationProperties.AccessibilityView="Raw">
                        <Thumb.Template>
                            <ControlTemplate TargetType="Thumb">
                                <Border Background="#E0FFFFFF" CornerRadius="6" />
                            </ControlTemplate>
                        </Thumb.Template>
                    </Thumb>
                </Grid>
            </Grid>
        </ControlTemplate>
        """);

    private readonly StackPanel rows = new() { Spacing = 2, Margin = new(0, 4, 0, 0) };
    private readonly Slider[] sliders = new Slider[4];
    private readonly TextBlock[] values = new TextBlock[4];
    private readonly Button disclosure;
    private readonly RotateTransform chevronRotation = new();
    private readonly double expandedWidth, collapsedWidth;
    private bool updating;
    private BeautySettings current = new();
    internal Action<BeautySettings>? SettingsChanged;

    internal BeautyPanel()
    {
        var title = Label("Beauty Controls", 12);
        title.FontWeight = FontWeights.SemiBold;
        title.Margin = new(0, 0, TitleSpacing, 0);
        title.TextTrimming = TextTrimming.CharacterEllipsis;
        AutomationProperties.SetName(this, title.Text);
        collapsedWidth = MeasureWidth(title) + DisclosureSize + 2 * Inset;

        var chevron = new Glyph
        {
            Kind = "chevron",
            Foreground = Theme.Brush("#E6FFFFFF"),
            RenderTransformOrigin = new(.5, .5),
            RenderTransform = chevronRotation
        };
        chevron.FitArtwork(10);
        disclosure = new Button
        {
            Template = DisclosureTemplate,
            Content = chevron,
            Width = DisclosureSize,
            Height = DisclosureSize,
            MinWidth = 0,
            MinHeight = 0,
            Padding = new(0),
            UseSystemFocusVisuals = true
        };
        disclosure.Click += (_, _) => SetExpanded(rows.Visibility == Visibility.Collapsed);
        var header = new Grid { Height = DisclosureSize };
        header.ColumnDefinitions.Add(new());
        header.ColumnDefinitions.Add(new()
        {
            Width = GridLength.Auto
        });
        header.Children.Add(title);
        Grid.SetColumn(disclosure, 1);
        header.Children.Add(disclosure);

        TextBlock[] labels = [Label("Smoothing"), Label("Brightening"), Label("Sharpening"), Label("Rosiness")];
        double labelWidth = labels.Max(MeasureWidth);
        expandedWidth = 2 * Inset + labelWidth + TrackWidth + ValueWidth + 2 * ColumnSpacing;
        for (int i = 0; i < labels.Length; ++i)
        {
            int index = i;
            var row = new Grid { Height = 22, ColumnSpacing = ColumnSpacing };
            row.ColumnDefinitions.Add(new()
            {
                Width = new(labelWidth)
            });
            row.ColumnDefinitions.Add(new());
            row.ColumnDefinitions.Add(new()
            {
                Width = new(ValueWidth)
            });
            row.Children.Add(labels[i]);
            var slider = new Slider
            {
                Template = SliderTemplate,
                Minimum = 0,
                Maximum = 100,
                StepFrequency = 1,
                MinWidth = 0,
                MinHeight = 0,
                Height = 22,
                IsThumbToolTipEnabled = false,
                UseSystemFocusVisuals = true
            };
            // The fill uses the full track width while the thumb stays within its own travel range.
            var fill = new Border
            {
                Width = 0,
                HorizontalAlignment = HorizontalAlignment.Left,
                Background = Theme.Brush("#0095FF"),
                CornerRadius = new(2)
            };
            var track = new Border
            {
                Height = 4,
                VerticalAlignment = VerticalAlignment.Center,
                IsHitTestVisible = false,
                Background = Theme.Brush("#21FFFFFF"),
                CornerRadius = new(2),
                Child = fill
            };
            Grid.SetColumn(track, 1);
            row.Children.Add(track);
            AutomationProperties.SetName(slider, labels[i].Text);
            sliders[i] = slider;
            Grid.SetColumn(slider, 1);
            row.Children.Add(slider);
            var value = Label("0%");
            value.TextAlignment = TextAlignment.Right;
            values[i] = value;
            Grid.SetColumn(value, 2);
            row.Children.Add(value);
            void UpdateFill() => fill.Width = slider.ActualWidth * slider.Value / slider.Maximum;
            slider.SizeChanged += (_, _) => UpdateFill();
            slider.ValueChanged += (_, args) =>
            {
                UpdateFill();
                if (updating || !slider.IsEnabled)
                    return;
                float strength = (float)args.NewValue / 100;
                current = index switch
                {
                    0 => current with { Smoothness = strength },
                    1 => current with { Lightening = strength },
                    2 => current with { Sharpness = strength },
                    _ => current with { Redness = strength }
                };
                values[index].Text = $"{args.NewValue:0}%";
                SettingsChanged?.Invoke(current);
            };
            rows.Children.Add(row);
        }

        Content = new Border
        {
            Padding = new(Inset - 1),
            CornerRadius = new(8),
            Background = Theme.Brush("#99000000"),
            BorderBrush = Theme.Brush("#1FFFFFFF"),
            BorderThickness = new(1),
            Child = new StackPanel { Children = { header, rows } }
        };
        SetExpanded(true);
        Visibility = Visibility.Collapsed;
        LoginMotion.Opacity(this, 0);
    }

    private void SetExpanded(
        bool expanded
    )
    {
        Width = expanded ? expandedWidth : collapsedWidth;
        rows.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
        chevronRotation.Angle = expanded ? 180 : 0;
        string action = AppText.Get(expanded ? "Hide beauty controls" : "Show beauty controls");
        AutomationProperties.SetName(disclosure, action);
        ToolTipService.SetToolTip(disclosure, action);
    }

    internal void Update(
        BeautySettings value,
        bool editable
    )
    {
        current = value;
        updating = true;
        float[] strengths = [value.Smoothness, value.Lightening, value.Sharpness, value.Redness];
        for (int i = 0; i < sliders.Length; ++i)
        {
            int percent = (int)Math.Round(strengths[i] * 100);
            sliders[i].Value = percent;
            values[i].Text = $"{percent}%";
            sliders[i].IsEnabled = editable;
        }
        rows.Opacity = editable ? 1 : .45;
        updating = false;
    }

    private static TextBlock Label(
        string text,
        double size = 11
    )
    {
        var label = Theme.Text(text, size, "#E6FFFFFF");
        label.FontFamily = SystemFont;
        return label;
    }

    private static double MeasureWidth(
        TextBlock label
    )
    {
        label.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        return Math.Ceiling(label.DesiredSize.Width);
    }
}
