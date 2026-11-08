//
//  MainWindow.VirtualCamera.cs
//  FaceNow
//

using FaceNow.Core.VirtualCamera;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using FaceNow.App.Controls;
using FaceNow.Windows.Studio.ViewModels;
using Windows.Foundation;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private Popup? virtualCameraPopup;
    private Action? refreshCameraUsage;
    private bool cameraStatusRefreshing;

    private static string CameraUsageLabel => AppText.Get("Virtual Devices");

    private sealed record CameraUsage(
        string Title,
        string Description,
        string Color,
        bool OfferSetup = false,
        bool Ready = false
    );

    private static CameraUsage DescribeCameraUsage(
        CameraOutputStatus status,
        bool canInstall
    ) => status.Registration switch
    {
        CameraRegistrationState.Unsupported => new(
            "Unavailable",
            "The virtual camera requires Windows 10 version 2004 or later (x64), or Windows 11.",
            "#DC2626"
        ),
        CameraRegistrationState.ComponentMissing => new(
            "Unavailable",
            "The camera feature is missing from this copy of FaceNow. Reinstall the full app, then try again.",
            "#DC2626"
        ),
        _ when !canInstall && (status.State == CameraOutputState.Faulted || status.Registration == CameraRegistrationState.NotRegistered)
            => new(
                "Unavailable",
                "Your AI video is still using the camera. Stop your AI video, then set up the camera again.",
                "#DC2626"
            ),
        _ when status.State == CameraOutputState.Faulted => new(
            "Needs Setup",
            "Your camera needs to be set up again before FaceNow can be used in other apps.",
            "#D97706",
            OfferSetup: true
        ),
        CameraRegistrationState.NotRegistered => new(
            "Not Installed",
            "Set up once to add FaceNow to the camera list in your meeting or streaming app.",
            "#D97706",
            OfferSetup: true
        ),
        CameraRegistrationState.Registered when status.State is CameraOutputState.Stopped or CameraOutputState.Running
            => new(
                "Enabled",
                "Start Camera in FaceNow, then choose this camera in your meeting or streaming app.",
                "#15803D",
                Ready: true
            ),
        _ => new("Checking", "Checking camera availability…", "#6B7380")
    };

    private void RefreshVirtualCameraUi()
    {
        var status = CameraUsageStatus;
        var usage = DescribeCameraUsage(status, CanSetUpCamera);
        var button = homeVirtualCamera;
        button.Text = CameraUsageLabel;
        button.IsEnabled = !IsCameraSetupBusy;
        button.Refresh();
        string helpText = AppText.Get(IsCameraSetupBusy ? "Setting up your camera. Please wait…" : usage.Description);
        ToolTipService.SetToolTip(button, helpText);
        AutomationProperties.SetName(button, CameraUsageLabel);
        AutomationProperties.SetHelpText(button, helpText);
        if (virtualCameraPopup?.IsOpen == true)
            refreshCameraUsage?.Invoke();
    }

    private async Task SynchronizeVirtualCameraStatusAsync()
    {
        if (!initialized || closing || closed || Model.Active || Model.IsPreview || cameraSetupPreview
            || virtualCameraOutput.IsBusy || cameraStatusRefreshing)
            return;
        cameraStatusRefreshing = true;
        try
        {
            await virtualCameraOutput.RefreshAsync();
        }
        catch (Exception error)
        {
            if (!closing && !closed)
                Model.ReportError(error);
        }
        finally
        {
            cameraStatusRefreshing = false;
            if (!closing && !closed)
                RefreshVirtualCameraUi();
        }
    }

    private void OpenVirtualCameraSettings(
        FrameworkElement anchor
    )
    {
        if (Model.Active)
            return;
        RefreshVirtualCameraUi();
        var host = new StackPanel();
        CameraOutputStatus? displayed = null;
        bool previousCanInstall = false;
        VirtualMicrophoneState? displayedMicrophone = null;
        refreshCameraUsage = () =>
        {
            var status = CameraUsageStatus;
            bool canInstall = CanSetUpCamera;
            var microphone = Model.VirtualMicrophoneStatus;
            if (displayed == status && previousCanInstall == canInstall && displayedMicrophone == microphone)
                return;
            displayed = status;
            previousCanInstall = canInstall;
            displayedMicrophone = microphone;
            host.Children.Clear();
            host.Children.Add(BuildVirtualDevicesPanel(status, canInstall, anchor, microphone));
        };
        refreshCameraUsage();
        virtualCameraPopup = OpenPopup(anchor, host, 400, 0);
        _ = SynchronizeVirtualCameraStatusAsync();
        _ = Model.RefreshVirtualMicrophoneAsync();
    }

    private StackPanel BuildVirtualDevicesPanel(
        CameraOutputStatus status,
        bool canInstall,
        FrameworkElement anchor,
        VirtualMicrophoneState microphoneStatus = VirtualMicrophoneState.NotInstalled
    )
    {
        var usage = DescribeCameraUsage(status, canInstall);
        var panel = new StackPanel { Margin = new(16, 20, 16, 12) };
        var heading = Theme.Text(CameraUsageLabel, 18, "#424954");
        heading.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        heading.Margin = new(4, 0, 4, 18);
        panel.Children.Add(heading);

        var microphoneUsage = DescribeVirtualMicrophone(microphoneStatus);
        double statusWidth = 14 + Math.Max(
            DeviceTextWidth(usage.Title),
            DeviceTextWidth(microphoneUsage.Label)
        );
        double setupWidth = DeviceTextWidth("Set Up", semibold: true) + 2;

        Button? cameraSetup = null;
        if (usage.OfferSetup || usage.Ready)
        {
            cameraSetup = DeviceLink("Set Up", async () =>
            {
                if (usage.Ready)
                {
                    ClosePopups();
                    if (!Model.IsPreview)
                        OpenLink("ms-settings:camera");
                }
                else if (cameraSetupPreview)
                    await SimulateCameraSetupAsync(anchor);
                else
                    await RunCameraActionAsync(virtualCameraOutput.InstallAndEnableAsync, anchor);
            });
            cameraSetup.IsEnabled = usage.Ready || canInstall;
            AutomationProperties.SetAutomationId(cameraSetup, "camera_setup");
            AutomationProperties.SetName(cameraSetup, AppText.Get("Set up camera"));
            if (usage.OfferSetup)
                ToolTipService.SetToolTip(
                    cameraSetup,
                    AppText.Get("Windows will ask for administrator permission.")
                );
        }
        var camera = DeviceRow(
            "Virtual Camera",
            "camera",
            usage.Title,
            usage.Color,
            statusWidth,
            setupWidth,
            cameraSetup
        );
        camera.Margin = new(0, 0, 0, 10);
        ToolTipService.SetToolTip(camera, AppText.Get(usage.Description));
        panel.Children.Add(camera);

        var microphoneSetup = DeviceLink("Set Up", async () => await ShowVirtualMicrophoneSetupAsync(anchor));
        AutomationProperties.SetAutomationId(microphoneSetup, "microphone_setup");
        AutomationProperties.SetName(microphoneSetup, AppText.Get("Set Up Virtual Microphone"));
        var microphone = DeviceRow("Virtual Microphone", "microphone", microphoneUsage.Label,
            microphoneUsage.Color, statusWidth, setupWidth, microphoneSetup);
        panel.Children.Add(microphone);
        return panel;
    }

    private static double DeviceTextWidth(
        string text,
        bool semibold = false
    )
    {
        var label = Theme.Text(text, 13);
        if (semibold)
            label.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        label.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        return Math.Ceiling(label.DesiredSize.Width);
    }

    private static Border DeviceRow(
        string name,
        string icon,
        string status,
        string color,
        double statusWidth,
        double setupWidth,
        Button? setup
    )
    {
        var row = new Grid { ColumnSpacing = 14 };
        row.ColumnDefinitions.Add(new());
        row.ColumnDefinitions.Add(new()
        {
            Width = new(statusWidth)
        });
        row.ColumnDefinitions.Add(new()
        {
            Width = new(setupWidth)
        });

        var identity = new Grid { ColumnSpacing = 10 };
        identity.ColumnDefinitions.Add(new()
        {
            Width = new(22)
        });
        identity.ColumnDefinitions.Add(new());
        identity.Children.Add(new Glyph
        {
            Kind = icon,
            Width = 22,
            Height = 22,
            Foreground = Theme.Brush("#6B7380"),
            VerticalAlignment = VerticalAlignment.Center
        });
        var title = Theme.Text(name, 13, "#424954");
        title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        title.TextTrimming = TextTrimming.CharacterEllipsis;
        Grid.SetColumn(title, 1);
        identity.Children.Add(title);
        row.Children.Add(identity);

        var state = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            VerticalAlignment = VerticalAlignment.Center
        };
        state.Children.Add(new Microsoft.UI.Xaml.Shapes.Ellipse
        {
            Width = 8,
            Height = 8,
            Fill = Theme.Brush(color),
            VerticalAlignment = VerticalAlignment.Center
        });
        state.Children.Add(Theme.Text(status, 13, "#6B7380"));
        Grid.SetColumn(state, 1);
        row.Children.Add(state);
        if (setup is not null)
        {
            Grid.SetColumn(setup, 2);
            setup.HorizontalAlignment = HorizontalAlignment.Right;
            row.Children.Add(setup);
        }
        return new Border
        {
            Child = row,
            Height = 48,
            Padding = new(12, 0, 12, 0),
            Background = Theme.Brush("#F7F8FA"),
            CornerRadius = new(12)
        };
    }

    private static Button DeviceLink(
        string text,
        Action action
    )
    {
        var link = Theme.Link(text, action);
        link.Height = 28;
        link.VerticalAlignment = VerticalAlignment.Center;
        var label = (TextBlock)link.Content;
        label.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        label.Foreground = Theme.Brush("#2F46E2");
        AutomationProperties.SetName(link, AppText.Get(text));
        return link;
    }

    private async Task RunCameraActionAsync(
        Func<Task> action,
        FrameworkElement anchor
    )
    {
        ClosePopups();
        try
        {
            await action();
            await Model.SynchronizeCameraOutputAsync();
            if (!Model.Active && !Model.IsPreview)
                await Model.RefreshCamerasAsync();
        }
        catch (Exception error)
        {
            Model.ReportError(error);
        }
        if (!closing)
        {
            RefreshVirtualCameraUi();
            if (!Model.Active)
                OpenVirtualCameraSettings(anchor);
        }
    }

}
