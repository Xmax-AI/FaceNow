using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private async Task VerifyAccountCardStyleAsync()
    {
        foreach (var (width, height, name) in new[] { (1360, 890, "default"), (1180, 800, "minimum"), (1920, 1080, "wide") })
        {
            ClosePopups(); ResizeWindow(width, height); await Task.Delay(200); ArrangePage();
            await OpenAccountAsync(); await UntilAsync(() => accountCard is { IsLoaded: true, ActualWidth: > 0 });
            var card = accountCard!;
            await Task.Delay(100); card.UpdateLayout();
            await SaveScreenshotAsync("account-card-" + name, card, 2);
            Check(Math.Abs(accountButton.ActualWidth - accountButton.ActualHeight) < .1 && accountButton.ActualWidth == 36,
                "The account entry is not a 36-point circular avatar.");
            Check(Math.Abs(card.ActualWidth - 340) < .1 && Math.Abs(card.ActualHeight - 238) < .1,
                $"The account card does not match macOS geometry: {card.ActualWidth:F2} x {card.ActualHeight:F2}.");
            var labels = CameraUsageDescendants(card).OfType<TextBlock>().Select(label => label.Text).ToArray();
            foreach (string label in new[] { "Buy Credits", "View Usage", "Privacy Policy", "Terms of Use", "Sign out", "••••••••view" })
                Check(labels.Contains(label), "Missing account card content: " + label);
            Check(!labels.Contains("Generation API key") && labels.All(label => !label.Contains("uk-")), "Account card exposes the old credential list.");
            var actions = CameraUsageDescendants(card).OfType<Button>().Where(button => AutomationProperties.GetName(button) is "View Usage" or "Privacy Policy" or "Terms of Use" or "Sign out").ToArray();
            var recharge = CameraUsageDescendants(card).OfType<Button>().Single(button => AutomationProperties.GetName(button) == "Buy Credits");
            Check(recharge.ActualWidth == 88 && recharge.ActualHeight == 28, "The credit purchase action lost its fixed width or padding.");
            Check(actions.Length == 4 && actions.All(button => button.ActualHeight == 34), "Account menu rows have inconsistent hit areas.");
            if (name == "default") await SaveScreenshotAsync("account-header", homeControls, 2);
            Check(accountPopup is { HorizontalOffset: >= 0, VerticalOffset: >= 0 }, "The account card escaped its root bounds.");
        }
        await OpenAccountAsync(); Check(accountPopup?.IsOpen != true, "A second avatar activation did not dismiss the account card.");
    }
}
