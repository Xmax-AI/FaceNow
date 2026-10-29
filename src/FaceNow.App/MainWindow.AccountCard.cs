using FaceNow.App.Controls;
using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Markup;
using Windows.Foundation;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private AccountCard? accountCard;
    private Popup? accountPopup;
    private async Task OpenAccountAsync()
    {
        if (accountPopup?.IsOpen == true) { ClosePopups(); return; }
        if (accountRepository?.HasVerifiedSession != true || closing) return;
        ClosePopups();
        var card = new AccountCard();
        void Link(string url) { ClosePopups(); OpenLink(url); }
        card.Recharge = () => Link("https://platform.xmax.ai/credits");
        card.Usage = () => Link("https://platform.xmax.ai/usage");
        card.Privacy = () => Link("https://platform.xmaxsi.com/docs/resources/privacy");
        card.Agreement = () => Link("https://platform.xmaxsi.com/docs/resources/terms");
        card.SignOut = async () => await SignOutAccountAsync();
        card.Update(AccountPresentation.From(accountRepository), accountRepository.CanAccessHome, !accountRepository.IsBusy && !accountStopping);
        var host = new Grid { Width = 388, Height = 294 };
        var shadow = new Grid { Margin = new(24, 32, 24, 24), IsHitTestVisible = false };
        _ = new LoginShadow(shadow, () => 16, Microsoft.UI.Colors.Black, 18, 5, .14f);
        host.Children.Add(shadow); card.Margin = new(24, 32, 24, 24); host.Children.Add(card);
        var arrow = (Microsoft.UI.Xaml.Shapes.Path)XamlReader.Load("""
            <Path xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Data="M0,8 L8,0 L16,8"
                  Fill="White" Stroke="#F0F1F3" StrokeThickness="1" Width="16" Height="8"
                  HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,25,34,0" IsHitTestVisible="False"/>
            """);
        host.Children.Add(arrow);
        var origin = accountButton.TransformToVisual(root).TransformPoint(new Point(accountButton.ActualWidth - 364, accountButton.ActualHeight - 18));
        var popup = new Popup { Child = host, XamlRoot = root.XamlRoot, IsLightDismissEnabled = true,
            HorizontalOffset = Math.Clamp(origin.X, 0, Math.Max(0, root.ActualWidth - host.Width)),
            VerticalOffset = Math.Clamp(origin.Y, 0, Math.Max(0, root.ActualHeight - host.Height)) };
        accountCard = card; accountPopup = popup;
        popup.Closed += (_, _) => { if (accountPopup == popup) { accountPopup = null; accountCard = null; } };
        popups.Add(popup); popup.IsOpen = true;
        await RefreshCreditsQuietlyAsync();
    }
}
