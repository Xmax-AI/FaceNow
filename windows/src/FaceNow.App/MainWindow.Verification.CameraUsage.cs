//
//  MainWindow.Verification.CameraUsage.cs
//  FaceNow
//

using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.Studio.ViewModels;
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
            ("ready", CameraRegistrationState.Registered, CameraOutputState.Stopped, true, "Enabled", (bool?)true),
            ("video-ready", CameraRegistrationState.Registered, CameraOutputState.Running, false, "Enabled", (bool?)true),
            ("waiting", CameraRegistrationState.Registered, CameraOutputState.Stopped, false, "Enabled", (bool?)true),
            ("setup", CameraRegistrationState.NotRegistered, CameraOutputState.Stopped, true, "Not Installed", (bool?)true),
            ("repair", CameraRegistrationState.Registered, CameraOutputState.Faulted, true, "Needs Setup", (bool?)true),
            ("stop-before-repair", CameraRegistrationState.Registered, CameraOutputState.Faulted, false, "Unavailable", (bool?)null),
            ("unsupported", CameraRegistrationState.Unsupported, CameraOutputState.Unavailable, false, "Unavailable", (bool?)null),
            ("missing", CameraRegistrationState.ComponentMissing, CameraOutputState.Unavailable, false, "Unavailable", (bool?)null)
        })
        {
            var panel = BuildVirtualDevicesPanel(
                new(
                state,
                "Internal diagnostic detail",
                registration
            ),
                canInstall,
                homeVirtualCamera
            );
            var popup = OpenPopup(homeVirtualCamera, panel, 400, 0);
            await UntilAsync(() => panel.IsLoaded);
            root.UpdateLayout();
            var elements = CameraUsageDescendants(panel).ToArray();
            var texts = elements.OfType<TextBlock>().Select(text => text.Text).ToArray();
            Check(
                texts.Contains(AppText.Get(expectedTitle)) && !texts.Contains("Internal diagnostic detail"),
                "Camera usage exposes an internal status or omits the next step: " + name
            );
            var setup = elements.OfType<Button>().SingleOrDefault(button => AutomationProperties.GetAutomationId(button) == "camera_setup");
            Check(setupEnabled is null ? setup is null : setup is not null && setup.IsEnabled == setupEnabled,
                "Setup must only be offered when needed and available: " + name);
            var microphone = elements.OfType<Button>().Single(button => AutomationProperties.GetAutomationId(button) == "microphone_setup");
            Check(microphone.IsEnabled && microphone.Content is TextBlock { Text: var linkText } && linkText == AppText.Get("Set Up"),
                "The microphone must open setup even when the driver is missing.");
            Check(
                !texts.Any(text => text is "Install & Enable" or "Remove Camera" or "Refresh Status" or "Registered"),
                "Maintenance controls are exposed in the camera usage panel."
            );
            Check(
                panel.Children.Count == 3 && panel.Children[1] is Border && panel.Children[2] is Border,
                "The virtual devices panel must end after the two device rows."
            );
            string? expectedHint = name switch
            {
                "stop-before-repair" => "Your AI video is still using the camera. Stop your AI video, then set up the camera again.",
                "unsupported" => "The virtual camera requires Windows 10 version 2004 or later (x64), or Windows 11.",
                "missing" => "The camera feature is missing from this copy of FaceNow. Reinstall the full app, then try again.",
                _ => null
            };
            if (expectedHint is not null)
                Check(
                    Equals(ToolTipService.GetToolTip(panel.Children[1]), AppText.Get(expectedHint)),
                    "The camera row does not explain how to continue: " + name
                );
            if (name is "setup" or "video-ready" or "repair" or "unsupported" or "missing" or "stop-before-repair")
                await SaveScreenshotAsync("camera-usage-" + name, (FrameworkElement)popup.Child);
            ClosePopups();
        }
        Check(Model.Session is null, "Camera usage verification created an AI session.");
    }

    private async Task VerifyVirtualMicrophoneSetupAsync()
    {
        var panel = BuildVirtualDevicesPanel(new(
            CameraOutputState.Stopped,
            "",
            CameraRegistrationState.Registered
        ),
            false, homeVirtualCamera, VirtualMicrophoneState.Disabled);
        var popup = OpenPopup(homeVirtualCamera, panel, 400, 0);
        await UntilAsync(() => panel.IsLoaded);
        await SaveScreenshotAsync("virtual-microphone-popover", (FrameworkElement)popup.Child, 2);
        var setup = CameraUsageDescendants(panel).OfType<Button>()
            .Single(button => AutomationProperties.GetAutomationId(button) == "microphone_setup");
        ((IInvokeProvider)FrameworkElementAutomationPeer.CreatePeerForElement(setup)!.GetPattern(PatternInterface.Invoke)).Invoke();
        await UntilAsync(() => virtualMicrophoneDialog is { IsLoaded: true });
        Check(!popup.IsOpen && AutomationProperties.GetName(virtualMicrophoneDialog!) == AppText.Get("Virtual Microphone"),
            "The setup action must close the device list and open a microphone dialog.");
        virtualMicrophoneDialog!.Hide();
        await UntilAsync(() => virtualMicrophoneDialog is null);

        foreach (var (state, action) in new[]
        {
            (VirtualMicrophoneState.NotInstalled, "Install"), (VirtualMicrophoneState.Pending, "Recheck Virtual Microphone"),
            (VirtualMicrophoneState.Disabled, "Enable"), (VirtualMicrophoneState.Enabled, "Disable"),
            (VirtualMicrophoneState.Failed, "Recheck Virtual Microphone")
        })
        {
            var dialog = CreateVirtualMicrophoneDialog(state);
            var card = (Border)dialog.Content;
            var showing = dialog.ShowAsync();
            try
            {
                await UntilAsync(() => card.IsLoaded && card.ActualWidth > 0);
                var buttons = CameraUsageDescendants(card).OfType<Button>().ToArray();
                Check(buttons.Select(AutomationProperties.GetAutomationId).SequenceEqual(new[] { "microphone_primary", "microphone_close", "microphone_sound_settings" }) &&
                    AutomationProperties.GetName(buttons[0]) == AppText.Get(action), "Unexpected microphone setup actions for " + state);
                if (state is VirtualMicrophoneState.Disabled or VirtualMicrophoneState.NotInstalled)
                    await SaveScreenshotAsync(
                        "virtual-microphone-" + state.ToString().ToLowerInvariant(),
                        card,
                        2
                    );
            }
            finally
            {
                dialog.Hide();
                await showing;
            }
        }
        Check(Model.Session is null, "Microphone setup verification started a session.");
    }

    private static IEnumerable<DependencyObject> CameraUsageDescendants(
        DependencyObject parent
    )
    {
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            yield return child;
            foreach (var descendant in CameraUsageDescendants(child))
                yield return descendant;
        }
    }
}
