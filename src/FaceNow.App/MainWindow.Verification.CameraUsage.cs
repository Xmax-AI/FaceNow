using FaceNow.Core.VirtualCamera;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private async Task VerifyCameraUsageAsync()
    {
        // Render state fixtures without installing, removing, or starting a camera.
        foreach (var (name, registration, state, canInstall, expectedTitle, setupEnabled) in new[]
        {
            ("ready", CameraRegistrationState.Registered, CameraOutputState.Stopped, true, "Ready to use", (bool?)null),
            ("video-ready", CameraRegistrationState.Registered, CameraOutputState.Running, false, "Ready to use", (bool?)null),
            ("waiting", CameraRegistrationState.Registered, CameraOutputState.Stopped, false, "Ready to use", (bool?)null),
            ("setup", CameraRegistrationState.NotRegistered, CameraOutputState.Stopped, true, "Setup needed", (bool?)true),
            ("repair", CameraRegistrationState.Registered, CameraOutputState.Faulted, true, "Setup needed", (bool?)true),
            ("stop-before-repair", CameraRegistrationState.Registered, CameraOutputState.Faulted, false, "Unavailable", (bool?)null),
            ("unsupported", CameraRegistrationState.Unsupported, CameraOutputState.Unavailable, false, "Unavailable", (bool?)null),
            ("missing", CameraRegistrationState.ComponentMissing, CameraOutputState.Unavailable, false, "Unavailable", (bool?)null)
        })
        {
            var panel = BuildCameraUsagePanel(new(state, "Internal diagnostic detail", registration), canInstall, homeVirtualCamera);
            var popup = OpenPopup(homeVirtualCamera, panel, 360, 20);
            await UntilAsync(() => panel.IsLoaded);
            root.UpdateLayout();
            var elements = CameraUsageDescendants(panel).ToArray();
            var texts = elements.OfType<TextBlock>().Select(text => text.Text).ToArray();
            Check(texts.Contains(expectedTitle) && !texts.Contains("Internal diagnostic detail"), "Camera usage exposes an internal status or omits the next step: " + name);
            var setup = elements.OfType<Button>().SingleOrDefault(button => AutomationProperties.GetAutomationId(button) == "camera_setup");
            Check(setupEnabled is null ? setup is null : setup is not null && setup.IsEnabled == setupEnabled,
                "Setup must only be offered when needed and available: " + name);
            Check(!texts.Any(text => text is "Install & Enable" or "Remove Camera" or "Refresh Status" or "Registered"), "Maintenance controls are exposed in the camera usage panel.");
            if (name == "stop-before-repair") Check(texts.Any(text => text.Contains("Stop your AI video")), "Unavailable setup does not explain how to continue.");
            if (name == "unsupported") Check(texts.Any(text => text.Contains("requires Windows 11")), "Unsupported setup does not explain the system requirement.");
            if (name == "missing") Check(texts.Any(text => text.Contains("Reinstall the full app")), "Missing components do not explain how to continue.");
            if (name == "ready")
            {
                Check(texts.Contains(FaceNowCameraName), "The camera name users need to select is missing.");
                var help = elements.OfType<Button>().Single(button => AutomationProperties.GetAutomationId(button) == "camera_help");
                var helpContent = panel.Children.OfType<StackPanel>().Last();
                Check(helpContent.Visibility == Visibility.Collapsed, "Troubleshooting should start collapsed.");
                ((IInvokeProvider)FrameworkElementAutomationPeer.CreatePeerForElement(help)!.GetPattern(PatternInterface.Invoke)).Invoke();
                await UntilAsync(() => helpContent.Visibility == Visibility.Visible);
                await SaveScreenshotAsync("camera-usage-help", (FrameworkElement)popup.Child);
            }
            if (name is "setup" or "video-ready" or "repair" or "unsupported" or "missing" or "stop-before-repair") await SaveScreenshotAsync("camera-usage-" + name, (FrameworkElement)popup.Child);
            ClosePopups();
        }
        Check(Model.Session is null, "Camera usage verification created an AI session.");
    }
    private static IEnumerable<DependencyObject> CameraUsageDescendants(DependencyObject parent)
    {
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            yield return child;
            foreach (var descendant in CameraUsageDescendants(child)) yield return descendant;
        }
    }
}
