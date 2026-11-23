//
//  MainWindow.Beauty.cs
//  FaceNow
//

using FaceNow.App.Controls;
using FaceNow.App.User;
using Microsoft.UI.Xaml;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private readonly ToolbarButton beautyButton = new(ToolbarButtonRole.Toggle, ToolbarButtonTone.Warm)
    {
        Text = "Beauty",
        Glyph = "sparkles"
    };
    private readonly BeautyPanel beautyPanel = new()
    {
        HorizontalAlignment = HorizontalAlignment.Right,
        VerticalAlignment = VerticalAlignment.Top,
        Margin = new(12)
    };
    private long beautyVisibilityIntent;
    private bool beautyPresented;

    private void BuildBeautyUi()
    {
        sessionControls.Children.Insert(1, beautyButton);
        beautyButton.Click += (_, _) => Model.SetBeauty(Model.Beauty with { Enabled = !Model.Beauty.Enabled });
        beautyPanel.SettingsChanged = Model.SetBeauty;
        resultVideoPanel.Children.Add(beautyPanel);
    }

    private void RefreshBeautyUi()
    {
        beautyButton.IsSelected = Model.Beauty.Enabled;
        beautyButton.IsEnabled = !Model.Busy;
        bool show = Model.Active && Model.Beauty.Enabled;
        beautyPanel.Update(Model.Beauty, show && !Model.IsClosing);
        if (beautyPresented == show)
            return;
        beautyPresented = show;
        long current = ++beautyVisibilityIntent;
        if (show)
            beautyPanel.Visibility = Visibility.Visible;
        LoginMotion.Opacity(beautyPanel, show ? 1 : 0);
        if (!show)
            _ = HideAsync(current);
    }

    private async Task HideAsync(
        long current
    )
    {
        if (LoginMotion.Enabled)
            await Task.Delay(300);
        if (current == beautyVisibilityIntent && !beautyPresented)
            beautyPanel.Visibility = Visibility.Collapsed;
    }
}
