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
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App.Controls;

internal sealed class InputLevelMeter : UserControl
{
    private readonly SolidColorBrush[] segments = new SolidColorBrush[8];
    private int litCount = -1, percent = -1, presentationRevision;
    private bool presented;

    internal InputLevelMeter()
    {
        Width = 220;
        Height = ToolbarButton.ControlHeight;
        VerticalAlignment = VerticalAlignment.Center;
        var row = new Grid { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new());
        var title = Theme.Text("Input Level", 13, "#424954");
        title.FontFamily = new("Segoe UI");
        title.FontWeight = FontWeights.SemiBold;
        row.Children.Add(title);
        var bar = new Grid { Height = 8, ColumnSpacing = 2, VerticalAlignment = VerticalAlignment.Center };
        for (int index = 0; index < segments.Length; ++index)
        {
            bar.ColumnDefinitions.Add(new());
            var segment = new Border { Background = segments[index] = Theme.Brush("#E5E7EB") };
            Grid.SetColumn(segment, index);
            bar.Children.Add(segment);
        }
        RoundedClip.Attach(bar, 4);
        Grid.SetColumn(bar, 1);
        row.Children.Add(bar);
        Content = row;
        AutomationProperties.SetName(this, title.Text);
        string help = AppText.Get("Speak into your microphone to check the input.");
        AutomationProperties.SetHelpText(this, help);
        ToolTipService.SetToolTip(this, help);
        LoginMotion.Opacity(this, 0);
        Collapse();
    }

    internal void SetPresented(bool visible, bool animateHide)
    {
        if (visible == presented)
        {
            if (!visible && !animateHide) Collapse();
            return;
        }
        presented = visible;
        int current = ++presentationRevision;
        IsHitTestVisible = visible;
        if (visible) Visibility = Visibility.Visible;
        LoginMotion.Opacity(this, visible ? 1 : 0);
        if (visible) return;
        if (animateHide && IsLoaded && LoginMotion.Enabled) _ = CollapseAfterTransitionAsync(current);
        else Collapse();
    }

    private async Task CollapseAfterTransitionAsync(int current)
    {
        await Task.Delay(300);
        if (current == presentationRevision) Collapse();
    }

    private void Collapse()
    {
        Visibility = Visibility.Collapsed;
        Update(null);
    }

    internal void Update(float? level)
    {
        float value = level is { } sample && float.IsFinite(sample) ? Math.Clamp(sample, 0, 1) : 0;
        int count = (int)Math.Ceiling(value * segments.Length);
        if (litCount != count)
        {
            litCount = count;
            for (int index = 0; index < segments.Length; ++index)
                LoginMotion.Color(this, segments[index], index < count ? "#34C759" : "#E5E7EB");
        }
        int nextPercent = (int)Math.Round(value * 100, MidpointRounding.AwayFromZero);
        if (percent == nextPercent) return;
        percent = nextPercent;
        AutomationProperties.SetItemStatus(this, $"{percent}%");
    }
}
