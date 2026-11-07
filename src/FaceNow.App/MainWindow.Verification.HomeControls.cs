using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using Xmax.SDK;

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
            var camera = cameraButton.TransformToVisual(landingStage).TransformPoint(default);
            var microphone = homeMicrophone.TransformToVisual(landingStage).TransformPoint(default);
            var start = StartButton.TransformToVisual(landingStage).TransformPoint(default);
            Check(Math.Abs(camera.Y - microphone.Y) < 1 && microphone.X >= camera.X + cameraButton.ActualWidth &&
                camera.Y >= start.Y + StartButton.ActualHeight, "The microphone picker must sit next to the camera picker below Start Camera.");
            var ratios = CameraUsageDescendants(cameraAspect).OfType<RadioButton>().ToArray();
            Check(ratios.Select(AutomationProperties.GetName).SequenceEqual(new[] { "16:9", "9:16", "1:1", "3:4", "4:3" }) &&
                ratios[0].IsChecked == true, "The aspect ratio picker must show the five presets with 16:9 selected.");
            var picker = cameraAspect.TransformToVisual(landingStage).TransformPoint(default);
            var notice = terms.TransformToVisual(landingStage).TransformPoint(default);
            Check(picker.Y >= camera.Y + cameraButton.ActualHeight && picker.Y + cameraAspect.ActualHeight < notice.Y,
                "The aspect ratio picker must sit between the inputs and the service notice.");
            ratios[1].IsChecked = true;
            Check(Model.SelectedFormat == new VideoFormat(1080, 1920) && localVideoView.ContentMode == VideoContentMode.Fit &&
                resultVideoView.ContentMode == VideoContentMode.Fit &&
                ratios.Count(ratio => ratio.IsChecked == true) == 1, "Selecting portrait must set the camera format and fit the preview.");
            ratios[0].IsChecked = true;
            Check(Model.SelectedFormat == new VideoFormat(1920, 1080) && localVideoView.ContentMode == VideoContentMode.Fill &&
                resultVideoView.ContentMode == VideoContentMode.Fill,
                "Selecting landscape must restore the widescreen camera format.");
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
