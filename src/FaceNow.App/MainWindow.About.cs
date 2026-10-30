using FaceNow.App.Home;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private static string PublicAppVersion => typeof(App).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
    private AboutView? aboutView;
    private Control? aboutPreviousFocus;
    private bool aboutClosing;
    private Task ShowAboutAsync()
    {
        if (aboutView is not null || closing || Model.Active || Model.Busy) return Task.CompletedTask;
        ClosePopups();
        aboutPreviousFocus = FocusManager.GetFocusedElement(root.XamlRoot) as Control;
        var view = new AboutView();
        view.RequestDismiss = async () => await CloseAboutAsync();
        view.Contact = () => OpenLink("mailto:contact@xmaxai.com");
        aboutView = view; scroller.IsHitTestVisible = false; root.Children.Add(view);
        return Task.CompletedTask;
    }
    private async Task CloseAboutAsync()
    {
        if (aboutView is not { } view || aboutClosing) return;
        aboutClosing = true;
        try { await view.SetPresentedAsync(false); }
        finally
        {
            if (aboutView == view) DisposeAboutView();
            aboutClosing = false;
            if (!closing && aboutPreviousFocus is { IsLoaded: true, IsEnabled: true } previous) previous.Focus(FocusState.Programmatic);
            aboutPreviousFocus = null;
        }
    }
    private void DisposeAboutView()
    {
        if (aboutView is not { } view) return;
        aboutView = null; view.Dispose(); root.Children.Remove(view); scroller.IsHitTestVisible = true;
    }
}
