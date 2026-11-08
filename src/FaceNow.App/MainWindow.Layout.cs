//
//  MainWindow.Layout.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.Collections.ObjectModel;
using System.Text.RegularExpressions;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using FaceNow.Windows.Studio.ViewModels;
using FaceNow.App.Controls;
using FaceNow.App.User;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private void BuildUi()
    {
        scroller.Content = page; root.Children.Add(scroller);
        foreach (var element in new UIElement[] { header, landing, workspace, footer, previewFooter }) page.Children.Add(element);
        previewFooter.TextAlignment = TextAlignment.Center;
        var branding = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top, Margin = new(-8, 8, 0, 0) };
        brandName.FontFamily = new("Segoe UI");
        brandName.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        brandName.VerticalAlignment = VerticalAlignment.Center;
        branding.Children.Add(brand); branding.Children.Add(brandName); branding.Children.Add(previewBadge); header.Children.Add(branding);
        foreach (var button in new[] { modelButton, keyButton, homeVirtualCamera }) homeControls.Children.Add(button);
        homeControls.VerticalAlignment = sessionControls.VerticalAlignment = VerticalAlignment.Top;
        header.Children.Add(homeControls); header.Children.Add(sessionControls);
        foreach (var element in new UIElement[] { statisticsButton, elapsed, stopButton }) sessionControls.Children.Add(element);
        BindMicrophones();
        homeVirtualCamera.Click += (_, _) => OpenVirtualCameraSettings(homeVirtualCamera);
        AutomationProperties.SetName(cameraButton, "Select Camera"); AutomationProperties.SetName(keyButton, "API Key");
        AutomationProperties.SetName(StartButton, "Start Camera"); AutomationProperties.SetName(statisticsButton, "Show / hide statistics");
        ToolTipService.SetToolTip(statisticsButton, AppText.Get("Show / hide statistics")); ToolTipService.SetToolTip(keyButton, AppText.Get("API Key"));
        cameraButton.Click += (_, _) => OpenCameras(); modelButton.Click += (_, _) => OpenModels(); keyButton.Click += (_, _) => OpenKey();
        statisticsButton.Click += (_, _) => Model.StatisticsVisible = !Model.StatisticsVisible;
        stopButton.Click += async (_, _) => { try { await Model.StopAsync(); } catch (Exception error) { Model.ReportError(error); } };
        StartButton.Click += (_, _) => Model.StartCommand.Execute(null);
        title.HorizontalAlignment = HorizontalAlignment.Center; title.TextAlignment = TextAlignment.Center;
        title.FontFamily = LoginTypography.Font; title.FontWeight = Microsoft.UI.Text.FontWeights.Medium; title.CharacterSpacing = -30;
        landing.Children.Add(title);
        landingStage.Children.Add(new CheckerboardSurface());
        var actions = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        var startHost = new Grid { HorizontalAlignment = HorizontalAlignment.Center };
        var startShadow = new Grid { IsHitTestVisible = false };
        _ = new LoginShadow(startShadow, () => (float)(StartButton.Height / 2), Theme.Brush("#2F46E2").Color, 15, 10, .35f);
        Theme.Bind(startShadow, UIElement.OpacityProperty, nameof(StartButton.Opacity), StartButton);
        startHost.Children.Add(startShadow); startHost.Children.Add(StartButton);
        actions.Children.Add(startHost);
        var inputPickers = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new(0, 16, 0, 0) };
        inputPickers.Children.Add(cameraButton);
        inputPickers.Children.Add(homeMicrophone);
        actions.Children.Add(inputPickers);
        cameraAspect.Margin = new(0, 14, 0, 0);
        cameraAspect.SelectionChanged += format => Model.SelectedFormat = format;
        actions.Children.Add(cameraAspect);
        homeReferences.Margin = new(0, 16, 0, 0);
        homeReferences.ReferenceSelected += Model.SelectHomeReference;
        homeReferences.UploadRequested += async () => await ChooseHomeReferenceAsync();
        actions.Children.Add(homeReferences);
        landingStage.Children.Add(actions);
        terms.TextAlignment = TextAlignment.Center; terms.TextWrapping = TextWrapping.Wrap; terms.HorizontalAlignment = HorizontalAlignment.Center; terms.VerticalAlignment = VerticalAlignment.Bottom; terms.Margin = new(20, 0, 20, 28);
        const string cameraNotice = "We access your camera and, when enabled, microphone in accordance with our {0} and {1}.";
        foreach (string part in Regex.Split(AppText.Get(cameraNotice), @"(\{[01]\})"))
            terms.Inlines.Add(part switch
            {
                "{0}" => LinkInline("Terms of Use", "https://platform.xmaxsi.com/docs/resources/terms", "#C3C6CC"),
                "{1}" => LinkInline("Privacy Policy", "https://platform.xmaxsi.com/docs/resources/privacy", "#C3C6CC"),
                _ => new Run { Text = part }
            });
        landingStage.Children.Add(terms); landing.Children.Add(landingStage);
        var copyright = Theme.Text("Copyright © 2026 XMAX.AI PTE.LTD. All rights reserved.", 13, "#6B7380"); copyright.HorizontalAlignment = HorizontalAlignment.Center; copyright.Margin = new(0, 16, 0, 0); landing.Children.Add(copyright);
        ConfigureVideoRow();
        workspace.Children.Add(videoRow);
        BuildSessionAudioControls();
        workspace.Children.Add(sessionAudioControls);
        var tabBar = new Border { HorizontalAlignment = HorizontalAlignment.Center, CornerRadius = new(21), Background = Theme.Brush("#1A787880"), Height = 42, Padding = new(4), Margin = new(0, ModeTabsTopSpacing, 0, 28) };
        var tabRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2 };
        foreach (var (mode, text) in new[] { ("charx", "Character Swap"), ("clothx", "Virtual Try-On"), ("vibex", "Style Transfer"), ("dimx", "Virtual Summon"), ("free", "Free Prompt") })
        {
            var label = Theme.Text(text, 13.5, "#6B7380"); label.FontFamily = new("Segoe UI"); label.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
            var tab = new Button { Template = Theme.ButtonTemplate, Content = label, Height = 34, Padding = new(22, 0, 22, 0), CornerRadius = new(17), BorderThickness = new(1) };
            AutomationProperties.SetName(tab, text); tab.Click += (_, _) => Model.SelectedMode = mode; tabs[mode] = tab; tabRow.Children.Add(tab);
        }
        tabBar.Child = tabRow; workspace.Children.Add(tabBar); workspace.Children.Add(referenceArea);
        BuildReferences("charx", Model.CharacterReferences); BuildReferences("clothx", Model.ClothingReferences); BuildReferences("vibex", Model.StyleReferences); BuildReferences("dimx", Model.SummonReferences);
        var promptContent = new Grid();
        promptEditor.Margin = new(18, 18, 18, 0);
        promptEditor.Height = 78;
        promptEditor.VerticalAlignment = VerticalAlignment.Top;
        ScrollViewer.SetVerticalScrollBarVisibility(promptEditor, ScrollBarVisibility.Auto);
        promptContent.Children.Add(promptEditor);
        promptEditor.TextChanged += (_, _) => Model.Prompt = promptEditor.Text;
        var freeActions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, Margin = new(0, 0, 12, 12) };
        freeUpload.Click += async (_, _) => await ChooseUploadAsync(); freeActions.Children.Add(freeUpload);
        var freeButton = new Button { Template = Theme.ButtonTemplate, Padding = new(0), BorderThickness = new(0), Background = Theme.Brush("#E5E7EB"), CornerRadius = new(22), Content = freeReferenceImage };
        RoundedClip.Attach(freeButton, 22); freeButton.Click += async (_, _) => { if (Model.FreeReference is { } item) await SelectReferenceAsync(item); };
        freeReferenceHost.Children.Add(freeButton); freeReferenceHost.Children.Add(freeReferenceUploadOverlay); freeReferenceHost.Children.Add(freeReferenceStatus);
        var remove = new Pill { Glyph = "close", Width = 18, Height = 18, MinWidth = 18, Padding = new(0), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new(0, -4, -5, 0) };
        AutomationProperties.SetName(remove, "Remove reference"); remove.Click += (_, _) => Model.RemoveFreeReference(); freeReferenceHost.Children.Add(remove); freeActions.Children.Add(freeReferenceHost);
        submit.Click += (_, _) => Model.SubmitPromptCommand.Execute(null); ToolTipService.SetToolTip(submit, AppText.Get("Submit prompt")); freeActions.Children.Add(submit);
        promptContent.Children.Add(freeActions); freePromptBox.Child = promptContent; referenceArea.Children.Add(freePromptBox);
        BuildFooter();
        root.Children.Add(toast);
    }
    private static Border MetricBox(MetricRow[] rows)
    {
        var stack = new StackPanel();
        foreach (var row in rows)
        {
            var grid = new Grid { Height = 17 }; grid.ColumnDefinitions.Add(new()); grid.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
            grid.Children.Add(Theme.Text(row.Label, 11, "#E6FFFFFF"));
            var value = Theme.Text("—", 11, "#E6FFFFFF"); value.FontFamily = new("Segoe UI"); Theme.Bind(value, TextBlock.TextProperty, nameof(row.Value), row); Grid.SetColumn(value, 1); grid.Children.Add(value);
            if (row.Label == "Total startup") stack.Children.Add(new Border { BorderThickness = new(0, 1, 0, 0), BorderBrush = Theme.Brush("#30FFFFFF"), Padding = new(0, 6, 0, 0), Margin = new(0, 4, 0, 0), Child = grid });
            else stack.Children.Add(grid);
        }
        return new() { Width = 250, CornerRadius = new(10), Background = Theme.Brush("#99000000"), BorderBrush = Theme.Brush("#1FFFFFFF"), BorderThickness = new(1), Padding = new(10, 8, 10, 8), Margin = new(0, 0, 0, 8), Child = stack };
    }
    private void BuildReferences(string mode, ObservableCollection<ReferenceItem> items)
    {
        var panel = new CenteredWrapPanel(); referencePanels[mode] = panel;
        var viewer = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, HorizontalScrollMode = ScrollMode.Disabled };
        referenceScrollers[mode] = viewer; referenceArea.Children.Add(viewer);
        void Sync()
        {
            foreach (var item in items)
                if (!ReferenceTiles.ContainsKey(item)) { var tile = new ReferenceTile(item); tile.Click += async (_, _) => { if (item.IsUpload) await ChooseUploadAsync(); else await SelectReferenceAsync(item); }; ReferenceTiles[item] = tile; }
            panel.Children.Clear(); foreach (var item in items) panel.Children.Add(ReferenceTiles[item]);
        }
        items.CollectionChanged += (_, _) => Sync(); Sync();
    }
    private void BuildFooter()
    {
        var socials = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 28, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
        foreach (var (glyph, name, url) in new[] { ("wechat", "WeChat", ""), ("socialX", "X", "https://x.com/XmaxAIOfficial"), ("globe", "Website", "https://www.xmaxsi.com/") })
        {
            Button? link = null;
            link = Theme.Link("", () => { if (url.Length == 0) OpenWechat(link!); else OpenLink(url); });
            double size = glyph == "socialX" ? 18 : 20;
            link.Content = new Glyph { Kind = glyph, Width = size, Height = size, Foreground = Theme.Brush("#BF6B7380") };
            link.Width = 24; link.HorizontalContentAlignment = HorizontalAlignment.Center; link.VerticalContentAlignment = VerticalAlignment.Center;
            ToolTipService.SetToolTip(link, AppText.Get(name)); AutomationProperties.SetName(link, AppText.Get(name)); socials.Children.Add(link);
        }
        footer.Children.Add(socials);
        var links = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 40, HorizontalAlignment = HorizontalAlignment.Right };
        var version = Theme.Text("V" + PublicAppVersion, 13, "#6B7380"); version.FontFamily = new("Segoe UI"); links.Children.Add(version);
        foreach (var (text, url) in new[] { ("TroubleShooting", "https://xmaxai.com/facenow/guide"), ("Feedback", "mailto:contact@xmaxai.com"),
            ("About Us", ""), ("API Platform", "https://platform.xmaxsi.com/") })
        {
            var link = Theme.Link(text, () => { if (url.Length == 0) _ = ShowAboutAsync(); else OpenLink(url); });
            if (link.Content is TextBlock label) label.FontFamily = LoginTypography.Font;
            AutomationProperties.SetName(link, AppText.Get(text)); links.Children.Add(link);
        }
        footer.Children.Add(links);
    }
    private static Hyperlink LinkInline(string text, string url, string color)
    { var link = new Hyperlink { NavigateUri = new(FaceNow.Core.Product.ProductProfile.Current.ResolveLink(url)), Foreground = Theme.Brush(color) }; link.Inlines.Add(new Run { Text = AppText.Get(text) }); return link; }
}
