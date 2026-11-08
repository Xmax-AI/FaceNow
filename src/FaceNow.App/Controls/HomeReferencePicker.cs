//
//  HomeReferencePicker.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using System.ComponentModel;
using FaceNow.App.User;
using FaceNow.Windows.Studio.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App.Controls;

internal sealed class HomeReferencePicker : UserControl
{
    internal const double AvatarSize = 52;
    private const double StripHeight = 56, Spacing = 8, VisiblePresets = 7;
    private readonly StackPanel tiles = new() { Orientation = Orientation.Horizontal, Spacing = Spacing, VerticalAlignment = VerticalAlignment.Center };
    private readonly ScrollViewer strip;
    private readonly Image preview = new() { Stretch = Stretch.UniformToFill };
    private readonly Button upload;
    private ReferenceTile? customTile;
    private ReferenceItem? selected;
    internal event Action? UploadRequested;
    internal event Action<ReferenceItem>? ReferenceSelected;

    internal HomeReferencePicker(IReadOnlyList<ReferenceItem> presets)
    {
        Height = StripHeight;
        HorizontalAlignment = HorizontalAlignment.Center;
        foreach (var item in presets) tiles.Children.Add(CreateTile(item));
        strip = new ScrollViewer
        {
            Width = VisiblePresets * (AvatarSize + 4) + (VisiblePresets - 1) * Spacing,
            Height = StripHeight, Content = tiles,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollMode = ScrollMode.Enabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, VerticalScrollMode = ScrollMode.Disabled,
            ZoomMode = ZoomMode.Disabled
        };
        strip.AddHandler(UIElement.PointerWheelChangedEvent, new PointerEventHandler(ScrollWithMouse), true);
        AutomationProperties.SetName(strip, AppText.Get("Reference images"));

        var portrait = new Grid { Width = AvatarSize, Height = AvatarSize, VerticalAlignment = VerticalAlignment.Center, Background = Theme.Brush("#F7F8FA") };
        RoundedClip.Attach(portrait, (float)(AvatarSize / 2));
        portrait.Children.Add(preview);
        var tint = Theme.Brush("#48FFFFFF");
        portrait.Children.Add(new Border { Background = tint, IsHitTestVisible = false });
        var badgeFill = Theme.Brush("#D91D1E22");
        var plus = new Glyph
        {
            Kind = "plus", Foreground = Theme.Brush("#FFFFFF"),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
        };
        plus.FitArtwork(11);
        portrait.Children.Add(new Border
        {
            Width = 22, Height = 22, CornerRadius = new(11), Background = badgeFill, Child = plus,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false
        });
        upload = new Button
        {
            Template = Theme.ButtonTemplate, Width = AvatarSize, Height = StripHeight,
            CornerRadius = new(0), Content = portrait, Background = Theme.Brush("#00000000"),
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center,
            BorderThickness = new(0), Padding = new(0), UseSystemFocusVisuals = true
        };
        void SetUploadHover(bool hovered)
        {
            LoginMotion.Color(upload, tint, hovered ? "#6BFFFFFF" : "#48FFFFFF");
            LoginMotion.Color(upload, badgeFill, hovered ? "#F0202227" : "#D91D1E22");
        }
        upload.PointerEntered += (_, _) => SetUploadHover(upload.IsEnabled);
        upload.PointerExited += (_, _) => SetUploadHover(false);
        upload.RegisterPropertyChangedCallback(Control.IsEnabledProperty, (_, _) =>
        {
            if (!upload.IsEnabled) SetUploadHover(false);
        });
        upload.Click += (_, _) => UploadRequested?.Invoke();
        string uploadLabel = AppText.Get("Upload your own reference image");
        AutomationProperties.SetName(upload, uploadLabel);
        ToolTipService.SetToolTip(upload, uploadLabel);
        Content = new StackPanel
        {
            Orientation = Orientation.Horizontal, Spacing = 12,
            Children =
            {
                upload,
                new Border { Width = 1, Height = 32, VerticalAlignment = VerticalAlignment.Center, Background = Theme.Brush("#40FFFFFF") },
                strip
            }
        };
    }

    internal void Update(ReferenceItem selection, ReferenceItem? custom, bool enabled, bool dimmed)
    {
        if (customTile?.Item != custom)
        {
            if (customTile is not null) tiles.Children.Remove(customTile);
            customTile = custom is null ? null : CreateTile(custom);
            if (customTile is not null)
            {
                tiles.Children.Insert(0, customTile);
                strip.ChangeView(0, null, null, true);
            }
        }
        if (selected != selection)
        {
            if (selected is not null) selected.PropertyChanged -= SelectedChanged;
            selected = selection;
            selected.PropertyChanged += SelectedChanged;
            preview.Source = selection.Thumbnail as ImageSource;
            AutomationProperties.SetItemStatus(upload, selection.Name);
        }
        upload.IsEnabled = enabled;
        tiles.Opacity = dimmed ? .5 : 1;
        foreach (ReferenceTile tile in tiles.Children) tile.UpdateCompactSelection(tile.Item == selection, enabled);
    }

    private ReferenceTile CreateTile(ReferenceItem item)
    {
        var tile = new ReferenceTile(item, compact: true);
        tile.Click += (_, _) => ReferenceSelected?.Invoke(item);
        return tile;
    }

    private void SelectedChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(ReferenceItem.Thumbnail)) preview.Source = selected?.Thumbnail as ImageSource;
    }

    private void ScrollWithMouse(object sender, PointerRoutedEventArgs args)
    {
        var properties = args.GetCurrentPoint(strip).Properties;
        if (properties.IsHorizontalMouseWheel || strip.ScrollableWidth <= 0) return;
        double target = Math.Clamp(strip.HorizontalOffset - properties.MouseWheelDelta * (AvatarSize + 4 + Spacing) / 120, 0, strip.ScrollableWidth);
        if (target == strip.HorizontalOffset) return;
        args.Handled = strip.ChangeView(target, null, null, true);
    }
}
