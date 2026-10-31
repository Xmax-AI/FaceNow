using FaceNow.App.Controls;
using FaceNow.App.User;
using Microsoft.UI.Xaml;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private readonly Pill beautyButton = new() { Text = "Beauty", Glyph = "sparkles", FontFamily = new("Segoe UI"), FontSize = 13, ContentSpacing = 6 };
    private readonly BeautyPanel beautyPanel = new() { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, Margin = new(12, 0, 12, 12) };
    private long beautyVisibilityIntent;
    private bool beautyPresented;
    private void BuildBeautyUi()
    {
        sessionControls.Children.Insert(1, beautyButton);
        beautyButton.Click += (_, _) => Model.SetBeauty(Model.Beauty with { Enabled = !Model.Beauty.Enabled });
        beautyPanel.SettingsChanged = Model.SetBeauty;
        remotePanel.Children.Add(beautyPanel);
    }
    private void RefreshBeautyUi()
    {
        beautyButton.Accent = Model.Beauty.Enabled; beautyButton.IsEnabled = !Model.Busy; beautyButton.Text = AppText.Get("Beauty") + (Model.BeautyApplying ? "…" : ""); beautyButton.Refresh();
        beautyPanel.Update(Model.Beauty);
        bool show = Model.Active && Model.Beauty.Enabled;
        if (beautyPresented == show) return; beautyPresented = show; long current = ++beautyVisibilityIntent;
        if (show) beautyPanel.Visibility = Visibility.Visible;
        LoginMotion.Opacity(beautyPanel, show ? 1 : 0);
        if (!show) _ = HideAsync(current);
    }
    private async Task HideAsync(long current)
    { if (LoginMotion.Enabled) await Task.Delay(300); if (current == beautyVisibilityIntent && !beautyPresented) beautyPanel.Visibility = Visibility.Collapsed; }
}
