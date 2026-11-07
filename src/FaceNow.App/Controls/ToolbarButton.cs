//
//  ToolbarButton.cs
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
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App.Controls;

internal enum ToolbarButtonRole { Action, Menu, Toggle, Status }
internal enum ToolbarButtonTone { Neutral, Accent, Warm, Danger, FilledAccent, SoftAccent }

/// <summary>Shared geometry and interaction states for home and generation toolbar controls.</summary>
internal class ToolbarButton : Pill
{
    internal const double ControlHeight = 36;
    internal const double ControlSpacing = 12;
    private const double ContentInset = 13; // The one-pixel border completes the 14-pixel inset.
    private const double ContentGap = 7;
    private const double ArtworkSize = 12.125; // Artwork size for the lightning glyph inside its 15-unit slot.
    private const double DisclosureSize = 6;
    private static readonly FontFamily SystemFont = new("Segoe UI");
    private readonly ToolbarButtonRole role;
    private readonly bool alwaysCircular;
    private readonly SolidColorBrush textBrush = Theme.Brush("#6B7380");
    private readonly SolidColorBrush accentBrush = Theme.Brush("#2F46E2");
    private readonly SolidColorBrush outline = Theme.Brush("#EBEEF2");
    private readonly GradientStop top = new() { Offset = 0 };
    private readonly GradientStop bottom = new() { Offset = 1 };
    private ToolbarButtonTone tone;

    internal ToolbarButton(ToolbarButtonRole role = ToolbarButtonRole.Action,
        ToolbarButtonTone tone = ToolbarButtonTone.Neutral, bool circular = false)
    {
        this.role = role;
        this.tone = tone;
        alwaysCircular = circular;
        Height = ControlHeight;
        FontFamily = SystemFont;
        FontSize = 13;
        FontWeight = FontWeights.Medium;
        // Align the visible text with the glyphs rather than the font's line box.
        SetLabelVerticalOffset(-1);
        LabelMaxWidth = double.PositiveInfinity;
        Background = new LinearGradientBrush
        {
            StartPoint = new(0, 0),
            EndPoint = new(0, 1),
            GradientStops = { top, bottom }
        };
        BorderBrush = outline;
        if (role == ToolbarButtonRole.Status)
        {
            IsHitTestVisible = false;
            IsTabStop = false;
        }
        FitContentArtwork(DisclosureSize);
        ContentSpacing = ContentGap;
    }

    internal ToolbarButtonTone Tone
    {
        get => tone;
        set
        {
            if (tone == value) return;
            tone = value;
            Refresh();
        }
    }

    internal bool IsSelected
    {
        get => Accent;
        set => Accent = value;
    }

    protected override double IconSize => ArtworkSize;

    internal override void Refresh()
    {
        bool circular = alwaysCircular || (Glyph.Length > 0 && Text.Length == 0);
        Width = circular ? Height : double.NaN;
        ExtraChevron = role == ToolbarButtonRole.Menu && !circular;
        Padding = new(circular ? 0 : ContentInset, 0, circular ? 0 : ContentInset, 0);
        base.Refresh();
    }

    protected override void ApplyAppearance(bool hot, bool pressed, bool focused)
    {
        bool interactive = IsEnabled && role != ToolbarButtonRole.Status;
        hot &= interactive;
        bool selected = role == ToolbarButtonRole.Toggle && IsSelected;
        var (text, start, end, border) = tone switch
        {
            ToolbarButtonTone.Accent when selected => ("#2F46E2", "#EEF1FF", "#EEF1FF", "#D7DDFB"),
            ToolbarButtonTone.Warm when selected => ("#A96608", "#FFFAF0", "#FFF0CA", "#F0CF88"),
            ToolbarButtonTone.Danger => ("#DC2626", "#FFFFFF", hot ? "#FDE8E8" : "#FDF2F2", hot ? "#80DC2626" : "#47DC2626"),
            ToolbarButtonTone.FilledAccent => ("#FFFFFF", hot ? "#2438C4" : "#2F46E2", hot ? "#2438C4" : "#2F46E2", "#00000000"),
            ToolbarButtonTone.SoftAccent => ("#424954", hot ? "#2E2F46E2" : "#1F2F46E2", hot ? "#2E2F46E2" : "#1F2F46E2", "#00000000"),
            _ => (hot ? "#111318" : "#6B7380", "#FFFFFF", "#F3F4F6", hot ? "#C9CED6" : "#EBEEF2")
        };

        SetContentForeground(textBrush, tone == ToolbarButtonTone.SoftAccent ? accentBrush : null);
        LoginMotion.Color(this, textBrush, text);
        LoginMotion.Color(this, outline, focused && interactive ? "#2F46E2" : border);
        LoginMotion.Color(this, top, start, pressed && interactive);
        LoginMotion.Color(this, bottom, end, pressed && interactive);
        LoginMotion.Opacity(this, IsEnabled || role == ToolbarButtonRole.Status ? 1 : .5);
    }
}
