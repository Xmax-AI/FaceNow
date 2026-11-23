//
//  MainWindow.HomeReferenceCatalog.cs
//  FaceNow
//

using System.Collections.Specialized;
using System.ComponentModel;
using FaceNow.App.Controls;
using FaceNow.App.User;
using FaceNow.Windows.Studio.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private void OpenHomeReferenceCatalog()
    {
        if (closing || modalView is not null || !Model.CanChooseHomeReference)
            return;

        var dialog = new ModalView("Reference images", "Close", 680, 520);
        var title = LoginTypography.Text("Reference images", 22, "#111318");
        title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        var categoryRow = new Grid { ColumnSpacing = 2 };
        var categoryBar = CreateModeTabBar(categoryRow);
        categoryBar.HorizontalAlignment = HorizontalAlignment.Stretch;
        var categoryTabs = new Dictionary<string, Button>();
        var panel = new CenteredWrapPanel();
        var list = new ScrollViewer
        {
            Content = panel,
            Height = 296,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            HorizontalScrollMode = ScrollMode.Disabled
        };
        var freePrompt = BuildHomeFreePrompt(dialog);
        freePrompt.VerticalAlignment = VerticalAlignment.Top;
        var content = new Grid { Height = 296, Children = { list, freePrompt } };
        var error = Theme.RawText("", 12, "#DC2626");
        error.TextWrapping = TextWrapping.Wrap;
        dialog.Body = new StackPanel
        {
            Spacing = 18,
            Children = { title, categoryBar, content, error }
        };

        string visibleMode = Model.HomeSelectedReference.Mode;

        void SyncReferences()
        {
            panel.Children.Clear();
            if (visibleMode == "free")
                return;
            foreach (var item in Model.References(visibleMode))
            {
                var tile = new ReferenceTile(item);
                tile.Click += async (_, _) =>
                {
                    if (item.IsUpload)
                    {
                        if (await ChooseHomeReferenceAsync(item.Mode) && modalView == dialog)
                            await CloseModalAsync(dialog);
                    }
                    else if (await CloseModalAsync(dialog))
                    {
                        Model.SelectHomeCatalogReference(item);
                        homeReferences.RevealSelection();
                    }
                };
                panel.Children.Add(tile);
            }
        }

        void Refresh()
        {
            foreach (var tab in categoryTabs.Values)
                tab.IsEnabled = Model.CanChooseHomeReference;
            list.IsEnabled = Model.CanChooseHomeReference;
            error.Text = AppText.Get(Model.Error);
            error.Visibility = Model.Error.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        }

        void ShowCategory(string mode)
        {
            visibleMode = mode;
            foreach (var (category, tab) in categoryTabs)
            {
                StyleModeTab(tab, category == mode, inactiveColor: "#4B5563");
                AutomationProperties.SetItemStatus(tab, category == mode ? AppText.Get("Selected") : "");
            }
            list.Visibility = mode == "free" ? Visibility.Collapsed : Visibility.Visible;
            freePrompt.Visibility = mode == "free" ? Visibility.Visible : Visibility.Collapsed;
            SyncReferences();
            list.ChangeView(null, 0, null, true);
        }

        foreach (var (mode, label) in ReferenceCategories.Append(("free", "Custom Prompt")))
        {
            var tab = CreateModeTab(label);
            tab.Padding = new(8, 0, 8, 0);
            tab.HorizontalAlignment = HorizontalAlignment.Stretch;
            AutomationProperties.SetAutomationId(tab, "home_catalog_" + mode);
            tab.Click += (_, _) => ShowCategory(mode);
            categoryTabs.Add(mode, tab);
            Grid.SetColumn(tab, categoryRow.ColumnDefinitions.Count);
            categoryRow.ColumnDefinitions.Add(new());
            categoryRow.Children.Add(tab);
        }
        PropertyChangedEventHandler modelChanged = (_, _) => Refresh();
        NotifyCollectionChangedEventHandler referencesChanged = (_, _) => SyncReferences();
        dialog.Loaded += (_, _) =>
        {
            Model.PropertyChanged += modelChanged;
            foreach (var (mode, _) in ReferenceCategories)
                Model.References(mode).CollectionChanged += referencesChanged;
            Refresh();
        };
        dialog.Unloaded += (_, _) =>
        {
            Model.PropertyChanged -= modelChanged;
            foreach (var (mode, _) in ReferenceCategories)
                Model.References(mode).CollectionChanged -= referencesChanged;
        };
        ShowCategory(visibleMode);
        ShowModal(dialog);
    }

    private Border BuildHomeFreePrompt(
        ModalView dialog
    )
    {
        var editor = new TextBox
        {
            Text = Model.Prompt,
            PlaceholderText = AppText.Get("Describe how you want the video to change"),
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            BorderThickness = new(0),
            Background = Theme.Brush("#00FFFFFF"),
            Padding = new(0),
            FontFamily = new("Segoe UI"),
            FontSize = 15,
            Margin = new(18, 18, 18, 0),
            Height = 78,
            VerticalAlignment = VerticalAlignment.Top
        };
        LoginInput.ConfigureEditor(editor);
        editor.VerticalAlignment = VerticalAlignment.Top;
        editor.VerticalContentAlignment = VerticalAlignment.Top;
        AutomationProperties.SetAutomationId(editor, "home_prompt_input");
        AutomationProperties.SetName(editor, AppText.Get("Custom Prompt"));
        ScrollViewer.SetVerticalScrollBarVisibility(editor, ScrollBarVisibility.Auto);

        var image = new Image { Stretch = Stretch.UniformToFill };
        var add = new Glyph { Kind = "plus", Width = 18, Height = 18, Foreground = Theme.Brush("#6B7380") };
        var overlay = new ReferenceUploadOverlay(compact: true);
        var thumbnail = new Grid { Children = { image, add, overlay } };
        RoundedClip.Attach(thumbnail, 22);
        var upload = new Button
        {
            Template = Theme.ButtonTemplate,
            Width = 44,
            Height = 44,
            Padding = new(0),
            BorderThickness = new(1),
            BorderBrush = Theme.Brush("#E5E7EB"),
            Background = Theme.Brush("#F7F8FA"),
            CornerRadius = new(22),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Stretch,
            Content = thumbnail
        };
        AutomationProperties.SetAutomationId(upload, "home_prompt_upload");
        AutomationProperties.SetName(upload, AppText.Get("Upload your own reference image"));
        ToolTipService.SetToolTip(upload, AppText.Get("Upload your own reference image"));
        upload.Click += async (_, _) => await ChooseHomeReferenceAsync("free");
        var remove = new Pill
        {
            Glyph = "close",
            Width = 18,
            Height = 18,
            MinWidth = 18,
            Padding = new(0),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new(0, -4, -5, 0)
        };
        AutomationProperties.SetName(remove, AppText.Get("Remove reference"));
        AutomationProperties.SetAutomationId(remove, "home_prompt_remove");
        remove.Click += (_, _) => Model.RemoveFreeReference();
        var referenceHost = new Grid { Children = { upload, remove } };
        var use = new Pill { Glyph = "arrow", Primary = true, Width = 44, Height = 44, Padding = new(0) };
        AutomationProperties.SetName(use, AppText.Get("Submit prompt"));
        AutomationProperties.SetAutomationId(use, "home_prompt_submit");
        ToolTipService.SetToolTip(use, AppText.Get("Submit prompt"));
        use.Click += async (_, _) =>
        {
            string prompt = editor.Text;
            if (await CloseModalAsync(dialog) && Model.SelectHomeFreePrompt(prompt))
                homeReferences.RevealSelection();
        };

        void Refresh()
        {
            editor.IsEnabled = upload.IsEnabled = remove.IsEnabled = Model.CanChooseHomeReference;
            use.IsEnabled = Model.CanChooseHomeReference && !string.IsNullOrWhiteSpace(editor.Text) &&
                (Model.FreeReference is null || !Model.FreeReference.IsUploading &&
                    !Model.FreeReference.HasError && Model.FreeReference.ReferenceUrl.Length > 0);
            image.Source = Model.FreeReference?.Thumbnail as ImageSource;
            add.Visibility = Model.HasFreeReference ? Visibility.Collapsed : Visibility.Visible;
            remove.Visibility = Model.HasFreeReference ? Visibility.Visible : Visibility.Collapsed;
            overlay.SetUploading(Model.FreeReference?.IsUploading == true, Model.FreeReference?.UploadProgress);
        }

        editor.TextChanged += (_, _) =>
        {
            Model.Prompt = editor.Text;
            Refresh();
        };
        var actions = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 10,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new(0, 0, 12, 12),
            Children = { referenceHost, use }
        };
        var surface = new Border
        {
            Height = 168,
            CornerRadius = new(18),
            Background = Theme.Brush("#F7F8FA"),
            BorderBrush = Theme.Brush("#E5E7EB"),
            BorderThickness = new(1),
            Child = new Grid { Children = { editor, actions } }
        };
        PropertyChangedEventHandler modelChanged = (_, _) => Refresh();
        dialog.Loaded += (_, _) =>
        {
            Model.PropertyChanged += modelChanged;
            Refresh();
        };
        dialog.Unloaded += (_, _) => Model.PropertyChanged -= modelChanged;
        Refresh();
        return surface;
    }
}
