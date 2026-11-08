//
//  MainWindow.Verification.SignOut.cs
//  FaceNow
//

using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private async Task VerifySignOutAsync()
    {
        Check(
            Model.IsPreview && accountRepository is not null && loginView is not null,
            "Sign-out regression requires an isolated account."
        );
        void Phase(
            string message
        )
        {
            string? output = Environment.GetEnvironmentVariable("FACENOW_SMOKE_OUTPUT");
            if (output is not null)
                System.IO.File.AppendAllText(
                    System.IO.Path.Combine(
                    output,
                    "signout-phases.txt"
                ),
                    message + Environment.NewLine
                );
        }
        static Button? SignOutButton(
            DependencyObject parent
        )
        {
            if (parent is Button button && AutomationProperties.GetName(button) == "Sign out")
                return button;
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); ++i)
                if (SignOutButton(VisualTreeHelper.GetChild(parent, i)) is { } found)
                    return found;
            return null;
        }
        for (int cycle = 0; cycle < 4; ++cycle)
        {
            Phase($"cycle {cycle}: login");
            if (!accountRepository!.HasVerifiedSession)
            {
                if (cycle % 2 == 0)
                    await loginView!.VerifyCodeLoginAsync(FaceNow.Core.Product.ProductProfile.Current.ShowsPhoneLogin ? 0 : 1);
                else
                    await loginView!.VerifyApiKeyLoginAsync();
            }
            Check(scroller.Visibility == Visibility.Visible, "Verified account did not show home.");
            await OpenAccountAsync();
            await Task.Delay(150);
            var button = SignOutButton(accountCard!) ?? throw new InvalidOperationException("Sign-out action missing.");
            var peer = FrameworkElementAutomationPeer.CreatePeerForElement(button)!;
            Phase($"cycle {cycle}: invoke popup sign-out");
            ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => !accountStopping && !accountRepository.CanAccessHome && loginView!.Visibility == Visibility.Visible);
            Check(
                Model.Session is null && Model.ApiKey.Length == 0 && scroller.Visibility == Visibility.Collapsed,
                "Sign-out retained studio access."
            );
            Phase($"cycle {cycle}: verify login video resumes");
            await loginView!.VerifyVideoPlaybackAsync();
            loginView.VerifyResetAndRegionalChannels();
            await Task.Delay(400);
            Phase($"cycle {cycle}: passed");
        }
    }
}
