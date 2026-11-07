//
//  InputLevelMeter.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App.Controls;

internal sealed class InputLevelMeter : UserControl
{
    private readonly SolidColorBrush[] segments = new SolidColorBrush[8];
    private int litCount = -1;

    internal InputLevelMeter()
    {
        Width = 220;
        VerticalAlignment = VerticalAlignment.Center;
        var row = new Grid { ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new());
        var title = Theme.Text("Input Level", 12, "#6B7380");
        title.FontFamily = new("Segoe UI");
        row.Children.Add(title);
        var bar = new Grid { Height = 7, ColumnSpacing = 3, VerticalAlignment = VerticalAlignment.Center };
        for (int index = 0; index < segments.Length; ++index)
        {
            bar.ColumnDefinitions.Add(new());
            var segment = new Border { CornerRadius = new(2), Background = segments[index] = Theme.Brush("#E5E7EB") };
            Grid.SetColumn(segment, index);
            bar.Children.Add(segment);
        }
        Grid.SetColumn(bar, 1);
        row.Children.Add(bar);
        Content = row;
        AutomationProperties.SetName(this, title.Text);
        Update(null);
    }

    internal void Update(float? level)
    {
        float value = level is { } sample && float.IsFinite(sample) ? Math.Clamp(sample, 0, 1) : 0;
        int count = (int)Math.Ceiling(value * segments.Length);
        if (litCount == count) return;
        litCount = count;
        for (int index = 0; index < segments.Length; ++index)
            LoginMotion.Color(this, segments[index], index < count ? "#34C759" : "#E5E7EB");
        AutomationProperties.SetItemStatus(this, $"{Math.Round(value * 100)}%");
    }
}
