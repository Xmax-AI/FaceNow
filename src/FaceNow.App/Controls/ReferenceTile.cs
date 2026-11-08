//
//  ReferenceTile.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using FaceNow.Windows.Studio.ViewModels;
using FaceNow.App.Platform;

namespace FaceNow.App.Controls;

internal sealed class ReferenceTile : Button
{
    internal ReferenceItem Item { get; }

    private readonly Border circle;
    private readonly Image image;
    private readonly ReferenceUploadOverlay uploadOverlay = new();
    private readonly TextBlock name, state;
    private readonly bool compact;
    private bool hot, compactSelected, compactEnabled = true;

    internal ReferenceTile(
        ReferenceItem item,
        bool compact = false
    )
    {
        this.compact = compact;
        Item = item;
        DataContext = item;
        double avatar = compact ? HomeReferencePicker.AvatarSize : 64;
        Width = compact ? avatar + 4 : CenteredWrapPanel.CellWidth;
        Height = compact ? avatar : CenteredWrapPanel.CellHeight;
        Padding = new(0);
        BorderThickness = new(0);
        Background = Theme.Brush("#00FFFFFF");
        Template = Theme.ButtonTemplate;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        AutomationProperties.SetName(this, item.Name);
        AutomationProperties.SetAutomationId(
            this,
            item.Id.Length > 0 ? (compact ? "home_reference_" : "reference_") + item.Id : "upload_" + item.Mode
        );
        var root = new Grid();
        root.RowDefinitions.Add(new()
        {
            Height = new(avatar)
        });
        if (!compact)
        {
            root.RowDefinitions.Add(new()
            {
                Height = new(6)
            });
            root.RowDefinitions.Add(new()
            {
                Height = new(14)
            });
        }
        image = new()
        {
            Stretch = Stretch.UniformToFill
        };
        var thumbnail = new Grid();
        thumbnail.Children.Add(image);
        thumbnail.Children.Add(uploadOverlay);
        if (item.IsPromptOnly)
        {
            var promptLabel = Theme.RawText(item.Name, 10, "#6B7380");
            promptLabel.FontFamily = new("Segoe UI");
            promptLabel.TextWrapping = TextWrapping.Wrap;
            promptLabel.TextAlignment = TextAlignment.Center;
            promptLabel.MaxLines = 3;
            promptLabel.Margin = new(8);
            thumbnail.Children.Add(promptLabel);
        }
        circle = new()
        {
            Width = avatar,
            Height = avatar,
            CornerRadius = new(avatar / 2),
            BorderThickness = new(item.IsUpload ? 1 : 2),
            Background = Theme.Brush("#F7F8FA"),
            Child = thumbnail,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        RoundedClip.Attach(circle, (float)(avatar / 2));
        root.Children.Add(circle);
        if (item.IsUpload)
            root.Children.Add(new Glyph
            {
                Kind = "plus",
                Width = 24,
                Height = 24,
                Foreground = Theme.Brush("#6B7380"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            });
        state = Theme.Text("", 11, "#6B7380");
        state.HorizontalAlignment = HorizontalAlignment.Center;
        root.Children.Add(state);
        name = Theme.RawText(item.Name, 11, "#6B7380");
        name.FontFamily = new("Segoe UI");
        name.TextAlignment = TextAlignment.Center;
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        if (!compact)
        {
            Grid.SetRow(name, 2);
            root.Children.Add(name);
        }
        Content = root;
        Click += RetryThumbnail;
        if (!compact)
            item.PropertyChanged += ItemChanged;
        Loaded += async (_, _) =>
        {
            if (compact)
                item.PropertyChanged += ItemChanged;
            Refresh();
            await LoadAsync();
        };
        if (compact)
            Unloaded += (_, _) => item.PropertyChanged -= ItemChanged;
        PointerEntered += (_, _) =>
        {
            hot = true;
            Refresh();
        };
        PointerExited += (_, _) =>
        {
            hot = false;
            Refresh();
        };
        Refresh();
    }

    private void ItemChanged(
        object? sender,
        System.ComponentModel.PropertyChangedEventArgs args
    ) => Refresh();

    internal void UpdateCompactSelection(
        bool selected,
        bool enabled
    )
    {
        if (compactSelected == selected && compactEnabled == enabled)
            return;
        compactSelected = selected;
        compactEnabled = enabled;
        AutomationProperties.SetItemStatus(this, selected ? AppText.Get("Selected") : "");
        Refresh();
    }

    private void RetryThumbnail(
        object sender,
        RoutedEventArgs args
    )
    {
        if (Item.HasError && Item.Thumbnail is null)
        {
            Item.HasError = false;
            _ = LoadAsync();
        }
    }

    private async Task LoadAsync()
    {
        if (Item.IsUpload || Item.IsPromptOnly || Item.Thumbnail is not null || Item.IsLoading || Item.HasError ||
            (compact && Item.IsUploading))
            return;
        Item.IsLoading = true;
        try
        {
            Item.Thumbnail = await ThumbnailCache.LoadAsync(Item.ThumbnailUrl);
            Item.HasError = false;
        }
        catch (Exception error)
        {
            Item.HasError = true;
            Item.Error = "Unable to load thumbnail — click to retry. " + error.Message;
        }
        finally
        {
            Item.IsLoading = false;
        }
    }

    internal void Refresh()
    {
        bool selected = compact ? compactSelected : Item.IsSelected;
        circle.BorderBrush = Theme.Brush(selected ? "#2F46E2" : hot && (!compact || compactEnabled) ? "#C7D0F8" : "#F3F4F6");
        name.Foreground = Theme.Brush(selected ? "#2F46E2" : "#6B7380");
        name.FontWeight = selected ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal;
        image.Source = Item.Thumbnail as ImageSource;
        uploadOverlay.SetUploading(Item.IsUploading, Item.UploadProgress);
        state.Text = Item.IsUploading ? "" : Item.IsLoading ? "···" : Item.HasError ? AppText.Get("Retry") : "";
        ToolTipService.SetToolTip(this, Item.HasError ? AppText.Get(Item.Error) : Item.Name);
        IsEnabled = (!compact || compactEnabled) && !Item.IsUploading;
    }
}
