using FaceNow.Core.VirtualCamera;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private readonly bool cameraSetupPreview;
    private bool previewCameraBusy;
    private CameraOutputStatus previewCameraStatus = InitialCameraSetupStatus();
    private ContentDialog? cameraSetupPermission;
    private CameraOutputStatus CameraUsageStatus => cameraSetupPreview ? previewCameraStatus : virtualCameraOutput.Status;
    private bool IsCameraSetupBusy => cameraSetupPreview ? previewCameraBusy : virtualCameraOutput.IsBusy;
    private bool CanSetUpCamera => cameraSetupPreview ? !previewCameraBusy : virtualCameraOutput.CanInstall;
    private static CameraOutputStatus InitialCameraSetupStatus() => new(CameraOutputState.Stopped, "Setup preview", CameraRegistrationState.NotRegistered);

    internal void ResetCameraSetupPreview()
    {
        if (!cameraSetupPreview || previewCameraBusy || cameraSetupPermission is not null) return;
        previewCameraStatus = InitialCameraSetupStatus();
        RefreshVirtualCameraUi(); OpenVirtualCameraSettings(homeVirtualCamera);
    }
    private async Task SimulateCameraSetupAsync(FrameworkElement anchor)
    {
        if (!cameraSetupPreview || previewCameraBusy || cameraSetupPermission is not null) return;
        ClosePopups();
        var permission = new ContentDialog
        {
            XamlRoot = root.XamlRoot, Title = "Windows permission step · simulation",
            Content = "During real setup, Windows asks for administrator permission to install the FaceNow camera.\n\nThis is a preview. No Windows permission request or installation will run.",
            PrimaryButtonText = "Continue simulation", CloseButtonText = "Cancel", DefaultButton = ContentDialogButton.Close
        };
        cameraSetupPermission = permission;
        try
        {
            if (await permission.ShowAsync() == ContentDialogResult.Primary && !closing)
            {
                previewCameraBusy = true; previewBadge.IsEnabled = false; RefreshVirtualCameraUi();
                await Task.Delay(1800);
                previewCameraStatus = new(CameraOutputState.Stopped, "Setup preview complete", CameraRegistrationState.Registered);
            }
        }
        finally
        {
            cameraSetupPermission = null; previewCameraBusy = false; previewBadge.IsEnabled = true;
            if (!closing) { RefreshVirtualCameraUi(); OpenVirtualCameraSettings(anchor); }
        }
    }
}
