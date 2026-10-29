using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private async Task VerifyHomeControlsAsync()
    {
        string original = Model.ApiKey;
        try
        {
            SetApiKey("facenow-ui-test-key");
            Check(keyButton.Text == "****************", "The header exposes part of the API Key.");
            await SaveScreenshotAsync("aligned-home-controls", homeControls);
            await SaveScreenshotAsync("aligned-footer-icons", (FrameworkElement)footer.Children[0]);
            Check(modelButton.Visibility == Visibility.Collapsed, "The model selector must remain hidden.");
            var keyPeer = FrameworkElementAutomationPeer.CreatePeerForElement(keyButton)!;
            ((IInvokeProvider)keyPeer.GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => apiKeyInput is { IsLoaded: true });
            Check(apiKeyInput!.Text == Model.ApiKey, "The API Key editor does not show its complete value.");
            await SaveScreenshotAsync("aligned-api-key-popup", (FrameworkElement)KeyPopup!.Child);
            apiKeyInput.Text = "another-ui-test-key";
            await UntilAsync(() => Model.ApiKey == apiKeyInput.Text);
            Check(keyButton.Text == "****************", "Editing the Key exposed its value in the header.");
            apiKeyInput.Text = "";
            await UntilAsync(() => Model.ApiKey.Length == 0 && keyButton.Text.Length == 0);
        }
        finally { SetApiKey(original); ClosePopups(); }
    }
}
