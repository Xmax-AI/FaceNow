//
//  MainWindow.HomeReferenceCatalog.cs
//  FaceNow
//

using FaceNow.App.Controls;
using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private void OpenHomeReferenceCatalog()
    {
        if (closing || modalView is not null || !Model.CanChooseHomeReference)
            return;

        var dialog = new ModalView("Reference images", "Close", 680, 480);
        var title = LoginTypography.Text("Reference images", 22, "#111318");
        title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        var categoryRow = new Grid { ColumnSpacing = 2 };
        var categoryBar = CreateModeTabBar(categoryRow);
        categoryBar.HorizontalAlignment = HorizontalAlignment.Stretch;
        categoryBar.MaxWidth = 480;
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
        dialog.Body = new StackPanel
        {
            Spacing = 18,
            Children = { title, categoryBar, list }
        };

        string? visibleMode = null;
        void ShowCategory(string mode)
        {
            if (mode == visibleMode)
                return;
            visibleMode = mode;
            foreach (var (category, tab) in categoryTabs)
            {
                StyleModeTab(tab, category == mode, inactiveColor: "#4B5563");
                AutomationProperties.SetItemStatus(tab, category == mode ? AppText.Get("Selected") : "");
            }
            panel.Children.Clear();
            foreach (var item in Model.References(mode).Where(item => !item.IsUpload && item.LocalPath is null))
            {
                var tile = new ReferenceTile(item);
                tile.Click += async (_, _) =>
                {
                    if (await CloseModalAsync(dialog))
                    {
                        Model.SelectHomeCatalogReference(item);
                        homeReferences.RevealSelection();
                    }
                };
                panel.Children.Add(tile);
            }
            list.ChangeView(null, 0, null, true);
        }

        foreach (var (mode, label) in ReferenceCategories)
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
        ShowCategory(Model.HomeSelectedReference.Mode);
        ShowModal(dialog);
    }
}
