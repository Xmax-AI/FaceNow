//
//  MainWindow.Verification.CameraSetup.cs
//  FaceNow
//

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using FaceNow.Core.VirtualCamera;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private async Task VerifyCameraSetupPreviewAsync()
    {
        var actualStatus = virtualCameraOutput.Status;
        Check(
            cameraSetupPreview && Model.IsPreview && Model.Session is null && !StartButton.IsEnabled,
            "Setup preview can start a real camera session."
        );
        async Task StartSetupAsync()
        {
            await UntilAsync(() => virtualCameraPopup?.Child is FrameworkElement { IsLoaded: true });
            var setup = CameraUsageDescendants(virtualCameraPopup!.Child).OfType<Button>()
                .Single(button => AutomationProperties.GetAutomationId(button) == "camera_setup");
            InvokePreviewButton(setup);
            await UntilAsync(() => cameraSetupPermission is { IsLoaded: true });
        }
        Button PermissionButton(
            string name
        ) => CameraUsageDescendants(cameraSetupPermission!).OfType<Button>()
            .Single(button => button.Content as string == name || FrameworkElementAutomationPeer.CreatePeerForElement(button)?.GetName() == name);

        Check(
            CameraUsageStatus.Registration == CameraRegistrationState.NotRegistered,
            "Preview did not start with an unregistered camera."
        );
        await SaveScreenshotAsync("setup-1-first-use", (FrameworkElement)virtualCameraPopup!.Child);
        await StartSetupAsync();
        await SaveScreenshotAsync("setup-2-permission-simulation", cameraSetupPermission);
        InvokePreviewButton(PermissionButton("Cancel"));
        await UntilAsync(() => cameraSetupPermission is null && virtualCameraPopup?.IsOpen == true);
        Check(
            CameraUsageStatus.Registration == CameraRegistrationState.NotRegistered && !previewCameraBusy,
            "Canceling setup changed its registration state."
        );
        await SaveScreenshotAsync("setup-canceled", (FrameworkElement)virtualCameraPopup!.Child);
        await StartSetupAsync();
        InvokePreviewButton(PermissionButton("Continue simulation"));
        await UntilAsync(() => previewCameraBusy);
        Check(
            !homeVirtualCamera.IsEnabled && !previewBadge.IsEnabled,
            "Setup can be started twice while busy."
        );
        await SaveScreenshotAsync("setup-3-setting-up");
        await UntilAsync(() => !previewCameraBusy && CameraUsageStatus.Registration == CameraRegistrationState.Registered);
        await UntilAsync(() => virtualCameraPopup?.Child is FrameworkElement { IsLoaded: true });
        Check(
            !CameraUsageDescendants(virtualCameraPopup!.Child).OfType<Button>().Any(button => AutomationProperties.GetAutomationId(button) == "camera_setup"),
            "Completed setup still offers an installation button."
        );
        await SaveScreenshotAsync("setup-4-ready", (FrameworkElement)virtualCameraPopup.Child);
        ResetCameraSetupPreview();
        Check(CameraUsageStatus.Registration == CameraRegistrationState.NotRegistered && virtualCameraOutput.Status == actualStatus && Model.Session is null,
            "Preview reset touched the real camera state or created an AI session.");
    }

    private static void InvokePreviewButton(
        Button button
    ) =>
        ((IInvokeProvider)FrameworkElementAutomationPeer.CreatePeerForElement(button)!.GetPattern(PatternInterface.Invoke)).Invoke();
}
