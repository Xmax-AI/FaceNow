//
//  CameraStartButton.cs
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
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;

namespace FaceNow.App.Controls;

internal sealed class CameraStartButton : Pill
{
    private readonly SolidColorBrush surface = Theme.Brush("#2F46E2");
    private readonly SolidColorBrush textBrush = Theme.Brush("#FFFFFF");
    private readonly TextBlock measureLabel = LoginTypography.Text();
    private bool loading;

    internal CameraStartButton()
    {
        Primary = true;
        FontFamily = LoginTypography.Font;
        measureLabel.FontWeight = FontWeights.SemiBold;
        HorizontalAlignment = HorizontalAlignment.Center;
        UseSystemFocusVisuals = true;
        Background = surface;
        ContentSpacing = 10;
        Glyph = "camera";
        Text = "Start Camera";
    }

    internal void SetViewportWidth(double width)
    {
        FontSize = Math.Clamp(width * .003 + 12, 15, 18);
        double inset = Math.Clamp(width * .0075 + 18, 25, 40);
        Padding = new(inset - 2, 0, inset, 0);
        measureLabel.FontSize = FontSize;
        var idle = MeasureLabel("Start Camera");
        var starting = MeasureLabel("Starting…");
        MinWidth = Math.Ceiling(Math.Max(idle.Width, starting.Width) + IconSize + ContentSpacing + Padding.Left + Padding.Right);
        Height = Math.Max(20, Math.Ceiling(Math.Max(idle.Height, starting.Height))) + Math.Clamp(width * .0028 + 9, 12, 16) * 2;
        Refresh();
    }

    private Size MeasureLabel(string text)
    {
        measureLabel.Text = AppText.Get(text);
        measureLabel.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        return measureLabel.DesiredSize;
    }

    internal void SetLoading(bool value)
    {
        if (loading == value) return;
        loading = value;
        ShowLoadingIcon(value);
        Refresh();
    }

    protected override void ApplyAppearance(bool hot, bool pressed, bool focused)
    {
        SetContentForeground(textBrush);
        BorderThickness = new(0);
        LoginMotion.Color(this, surface, IsEnabled && hot ? (pressed ? "#2235B8" : "#2438C4") : "#2F46E2");
        LoginMotion.Opacity(this, loading ? .65 : 1);
    }
}
