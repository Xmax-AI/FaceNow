//
//  CameraAspectPicker.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using FaceNow.App.User;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Markup;
using Xmax.SDK;

namespace FaceNow.App.Controls;

internal sealed class CameraAspectPicker : UserControl
{
    private static readonly ControlTemplate SegmentTemplate = (ControlTemplate)XamlReader.Load("""
        <ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="RadioButton">
          <Border Background="{TemplateBinding Background}" CornerRadius="13">
            <ContentPresenter Content="{TemplateBinding Content}" HorizontalContentAlignment="Center" VerticalContentAlignment="Center"/>
          </Border>
        </ControlTemplate>
        """);

    private readonly Dictionary<VideoFormat, RadioButton> segments = [];
    internal event Action<VideoFormat>? SelectionChanged;

    internal CameraAspectPicker(IReadOnlyList<(string Ratio, VideoFormat Format)> options)
    {
        Height = 34;
        HorizontalAlignment = HorizontalAlignment.Center;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2 };
        Content = new Border
        {
            CornerRadius = new(17), Padding = new(3), BorderThickness = new(1),
            Background = Theme.Brush("#47000000"), BorderBrush = Theme.Brush("#29FFFFFF"), Child = row
        };
        foreach (var (ratio, format) in options)
        {
            var label = LoginTypography.Text(ratio, 13.5, "#D9FFFFFF");
            label.FontWeight = FontWeights.Medium;
            var surface = Theme.Brush("#00000000");
            var foreground = Theme.Brush("#D9FFFFFF");
            label.Foreground = foreground;
            var segment = new RadioButton
            {
                Template = SegmentTemplate, Content = label, Background = surface, Width = 52, Height = 26,
                MinWidth = 0, MinHeight = 0, Padding = new(0), UseSystemFocusVisuals = true
            };
            bool hovered = false, pressed = false;
            void RefreshSegment()
            {
                bool selected = segment.IsChecked == true;
                LoginMotion.Color(segment, surface, selected ? (pressed ? "#2438C4" : "#2F46E2")
                    : pressed ? "#26FFFFFF" : hovered ? "#14FFFFFF" : "#00000000");
                LoginMotion.Color(segment, foreground, selected || hovered ? "#FFFFFF" : "#D9FFFFFF");
            }
            segment.RegisterPropertyChangedCallback(ToggleButton.IsCheckedProperty, (_, _) => RefreshSegment());
            segment.Checked += (_, _) => SelectionChanged?.Invoke(format);
            segment.PointerEntered += (_, _) => { hovered = true; RefreshSegment(); };
            segment.PointerExited += (_, _) => { hovered = pressed = false; RefreshSegment(); };
            segment.PointerPressed += (_, _) => { pressed = true; RefreshSegment(); };
            segment.PointerReleased += (_, _) => { pressed = false; RefreshSegment(); };
            AutomationProperties.SetName(segment, ratio);
            ToolTipService.SetToolTip(segment, $"{format.Width} × {format.Height}");
            segments.Add(format, segment);
            row.Children.Add(segment);
        }
    }

    internal void Update(VideoFormat format, bool enabled)
    {
        if (segments.TryGetValue(format, out var selected)) selected.IsChecked = true;
        IsEnabled = enabled;
        LoginMotion.Opacity(this, enabled ? 1 : .5);
    }
}
