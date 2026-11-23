//
//  MainWindow.Verification.HomeControls.cs
//  FaceNow
//

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using FaceNow.App.Controls;
using FaceNow.App.Home;
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
            var appearance = homeReferences.TransformToVisual(landingStage).TransformPoint(default);
            Check(picker.Y >= camera.Y + cameraButton.ActualHeight &&
                Math.Abs(appearance.Y - picker.Y - cameraAspect.ActualHeight - 16) < 1 &&
                appearance.Y + homeReferences.ActualHeight < notice.Y,
                "Aspect ratio and reference controls must fit between the inputs and the service notice.");
            ratios[1].IsChecked = true;
            Check(Model.SelectedFormat == new RealtimeVideoFormat(1080, 1920) && localVideoView.ContentMode == VideoContentMode.Fit &&
                resultVideoView.ContentMode == VideoContentMode.Fit &&
                ratios.Count(ratio => ratio.IsChecked == true) == 1, "Selecting portrait must set the camera format and fit the preview.");
            ratios[0].IsChecked = true;
            Check(Model.SelectedFormat == new RealtimeVideoFormat(1920, 1080) && localVideoView.ContentMode == VideoContentMode.Fill &&
                resultVideoView.ContentMode == VideoContentMode.Fill,
                "Selecting landscape must restore the widescreen camera format.");
            var angle = cameraRotation.TransformToVisual(landingStage).TransformPoint(default);
            Check(Math.Abs(angle.Y - picker.Y) < 1 && angle.X >= picker.X + cameraAspect.ActualWidth + 9,
                "The angle capsule must sit to the right of the aspect presets.");
            foreach (var rotation in Enum.GetValues<CameraRotation>())
            {
                var anglePeer = FrameworkElementAutomationPeer.CreatePeerForElement(cameraRotation)!;
                ((IInvokeProvider)anglePeer.GetPattern(PatternInterface.Invoke)).Invoke();
                await UntilAsync(() => cameraRotationPopup is { IsOpen: true, Child: FrameworkElement { IsLoaded: true } });
                var options = CameraUsageDescendants(cameraRotationPopup!.Child).OfType<Button>().ToArray();
                Check(options.Select(AutomationProperties.GetName).SequenceEqual(new[] { "0°", "90°", "180°", "270°" }),
                    "The rotation menu must show the four supported angles in order.");
                var selected = options.Single(button => AutomationProperties.GetItemStatus(button) == AppText.Get("Selected"));
                Check(AutomationProperties.GetName(selected) == $"{(int)Model.SelectedRotation}°",
                    "The angle menu must mark the current rotation.");
                if (rotation == CameraRotation.Clockwise90)
                    await SaveScreenshotAsync("camera-rotation-menu", (FrameworkElement)cameraRotationPopup.Child);
                var option = options.Single(button => AutomationProperties.GetName(button) == $"{(int)rotation}°");
                var peer = FrameworkElementAutomationPeer.CreatePeerForElement(option)!;
                ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
                await UntilAsync(() => Model.SelectedRotation == rotation && cameraRotationPopup.IsOpen == false);
                Check(cameraRotation.Text == $"{(int)rotation}°" && Model.SelectedFormat == new RealtimeVideoFormat(1920, 1080),
                    "The selected angle must update its capsule and retain the chosen aspect.");
            }
            Model.SelectedRotation = CameraRotation.None;
            await SaveScreenshotAsync("camera-format-controls", (FrameworkElement)cameraAspect.Parent);
            var references = CameraUsageDescendants(homeReferences).OfType<ReferenceTile>().ToArray();
            Check(references.Length == 5 && references.Select(tile => tile.Item).SequenceEqual(Model.HomeReferencePresets) &&
                references.All(tile => tile.ActualHeight == 52), "Home must show five preset avatars as a compact reference strip.");
            Check(CameraUsageDescendants(homeReferences).OfType<Button>().Count() == 6,
                "Home must contain the five avatars and More.");
            var referencePeer = FrameworkElementAutomationPeer.CreatePeerForElement(references[2])!;
            ((IInvokeProvider)referencePeer.GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => Model.HomeSelectedReference == references[2].Item);
            Check(
                AutomationProperties.GetItemStatus(references[2]) == AppText.Get("Selected"),
                "The home reference selection must be visible."
            );
            Model.ResetHomeReferences();
            await SaveScreenshotAsync("aligned-home-references", homeReferences);
            await VerifyHomeCatalogAsync();
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
        finally
        {
            DisposeModal();
            SetApiKey(original);
            ClosePopups();
        }
    }

    private async Task VerifyHomeCatalogAsync()
    {
        ResizeWindow(1180, 800);
        await Task.Delay(250);
        root.UpdateLayout();
        var more = CameraUsageDescendants(homeReferences).OfType<Button>().Single(
            button => AutomationProperties.GetAutomationId(button) == "home_reference_more"
        );
        Check(more.Content is Grid circle && circle.Children.OfType<Glyph>().Any(icon => icon.Kind == "plus") &&
            Math.Abs(circle.ActualWidth - circle.ActualHeight) < 1 && circle.ActualWidth > 0,
            "The reference entry must show a circular button with a plus.");
        more.Focus(FocusState.Programmatic);
        Invoke(more);
        await UntilAsync(() => modalView?.Body is FrameworkElement { IsLoaded: true, ActualWidth: > 0 });
        var catalog = (FrameworkElement)modalView!.Body!;
        var close = await WaitForModalCloseButtonAsync();
        var card = (FrameworkElement)VisualTreeHelper.GetParent(close);
        var closeOrigin = close.TransformToVisual(card).TransformPoint(default);
        Check(AutomationProperties.GetIsDialog(modalView) && !scroller.IsHitTestVisible,
            "The catalog must block interaction with the home page while open.");
        Check(close.Content is Glyph { Kind: "close", Width: 24, Height: 24 } && close.ActualWidth >= 40 &&
            closeOrigin.X > card.ActualWidth / 2 &&
            closeOrigin.Y >= 0 && closeOrigin.Y < card.ActualHeight / 4,
            $"The close icon must be in the upper-right corner of the card ({closeOrigin}, {card.ActualWidth} × {card.ActualHeight}).");
        foreach (var (mode, _) in ReferenceCategories)
        {
            var tab = CameraUsageDescendants(catalog).OfType<Button>().Single(
                button => AutomationProperties.GetAutomationId(button) == "home_catalog_" + mode
            );
            var origin = tab.TransformToVisual(catalog).TransformPoint(default);
            Check(tab.ActualWidth > 0 && origin.X >= -1 && origin.X + tab.ActualWidth <= catalog.ActualWidth + 1,
                "The dialog clips the " + mode + " category at the minimum window size.");
            Invoke(tab);
            await UntilAsync(() => CatalogTiles().FirstOrDefault()?.Item.Mode == mode);
            Check(CatalogTiles().Select(tile => tile.Item).SequenceEqual(Model.References(mode)) &&
                CatalogTiles()[0].Item.IsUpload,
                "The home catalog must show the mode's upload entry and every reference.");
        }

        await UntilAsync(() => CatalogTiles().All(tile => tile.Item.IsUpload || tile.Item.IsPromptOnly || tile.Item.Thumbnail is not null || tile.Item.HasError));
        await Task.Delay(300);
        await SaveScreenshotAsync("home-reference-catalog");
        var preset = CatalogTiles().First(tile => tile.Item.IsPromptOnly);
        Invoke(preset);
        await UntilAsync(() => modalView is null && Model.HomeSelectedReference == preset.Item);
        Check(Model.HomeReferences.Count == 6 && Model.HomeReferences[0] == preset.Item &&
            Model.HomeSelectedReference == preset.Item, "The new catalog preset must appear first and be selected at home.");
        Check(CameraUsageDescendants(homeReferences).OfType<ReferenceTile>().First().Item == preset.Item,
            "The new catalog preset must be first in the displayed home list.");

        Invoke(more);
        await UntilAsync(() => modalView?.Body is FrameworkElement { IsLoaded: true } body &&
            CameraUsageDescendants(body).OfType<ReferenceTile>().Any(tile => tile.IsLoaded && tile.Item == preset.Item));
        catalog = (FrameworkElement)modalView!.Body!;
        Invoke(CatalogTiles().Single(tile => tile.Item == preset.Item));
        await UntilAsync(() => modalView is null);
        Check(Model.HomeReferences.Count == 6, "Selecting the same catalog preset must leave a single tile.");

        Invoke(more);
        Invoke(await WaitForModalCloseButtonAsync());
        await UntilAsync(() => modalView is null);
        Check(scroller.IsHitTestVisible && Model.HomeSelectedReference == preset.Item,
            "Closing with the upper-right icon must restore the home page without changing its selection.");

        Invoke(more);
        await UntilAsync(() => modalView?.Body is FrameworkElement { IsLoaded: true });
        catalog = (FrameworkElement)modalView!.Body!;
        var freeTab = CameraUsageDescendants(catalog).OfType<Button>().Single(
            button => AutomationProperties.GetAutomationId(button) == "home_catalog_free");
        var freeOrigin = freeTab.TransformToVisual(catalog).TransformPoint(default);
        Check(freeOrigin.X >= 0 && freeOrigin.X + freeTab.ActualWidth <= catalog.ActualWidth + 1,
            "The fifth category must fit the minimum window.");
        Invoke(freeTab);
        var editor = CameraUsageDescendants(catalog).OfType<TextBox>().Single(
            input => AutomationProperties.GetAutomationId(input) == "home_prompt_input");
        var apply = CameraUsageDescendants(catalog).OfType<Button>().Single(
            button => AutomationProperties.GetAutomationId(button) == "home_prompt_submit");
        editor.Text = " ";
        await UntilAsync(() => !apply.IsEnabled);
        const string customPrompt = "A watercolor portrait / 水彩人物";
        editor.Text = customPrompt;
        await UntilAsync(() => apply.IsEnabled);
        await Task.Delay(300);
        await SaveScreenshotAsync("home-free-prompt");
        Invoke(apply);
        await UntilAsync(() => modalView is null && Model.HomeSelectedReference.Mode == "free");
        await Model.StartLandingAsync();
        Check(Model.SelectedMode == "free" && Model.Prompt == customPrompt && Model.FreeReference is null,
            "The free prompt must reach generation with the user's text.");
        await Model.StopAsync();

        ShowAbout();
        await UntilAsync(() => modalView is AboutView { IsLoaded: true });
        Invoke(await WaitForModalCloseButtonAsync());
        await UntilAsync(() => modalView is null);
        Model.ResetHomeReferences();
        ResizeWindow(1360, 890);

        ReferenceTile[] CatalogTiles() => CameraUsageDescendants(catalog).OfType<ReferenceTile>().ToArray();

        async Task<Button> WaitForModalCloseButtonAsync()
        {
            Button? closeButton = null;
            await UntilAsync(() =>
            {
                if (modalView is not { IsLoaded: true } view)
                    return false;
                closeButton = CameraUsageDescendants(view).OfType<Button>().FirstOrDefault(button =>
                    AutomationProperties.GetAutomationId(button) == "modal_close" && button.ActualWidth > 0);
                return closeButton is not null;
            });
            return closeButton!;
        }

        static void Invoke(Button button)
        {
            var peer = FrameworkElementAutomationPeer.CreatePeerForElement(button)!;
            ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
        }
    }
}
