using FaceNow.Core.VirtualCamera;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using FaceNow.App.Controls;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private Popup? virtualCameraPopup;
    private Action? refreshCameraUsage;
    private bool cameraStatusRefreshing;
    private const string CameraUsageLabel = "Virtual Camera";
    private const string FaceNowCameraName = "FaceNow - Xmax Virtual Camera";

    private sealed record CameraUsage(string Title, string Description, string Color, string? Setup = null, bool Ready = false);
    private static CameraUsage DescribeCameraUsage(CameraOutputStatus status, bool canInstall) => status.Registration switch
    {
        CameraRegistrationState.Unsupported => new("Unavailable", "This feature requires Windows 11. Use FaceNow on a Windows 11 computer to continue.", "#DC2626"),
        CameraRegistrationState.ComponentMissing => new("Unavailable", "The camera feature is missing from this copy of FaceNow. Reinstall the full app, then try again.", "#DC2626"),
        _ when !canInstall && (status.State == CameraOutputState.Faulted || status.Registration == CameraRegistrationState.NotRegistered)
            => new("Unavailable", "Your AI video is still using the camera. Stop your AI video, then set up the camera again.", "#DC2626"),
        _ when status.State == CameraOutputState.Faulted => new("Setup needed", "Your camera needs to be set up again before FaceNow can be used in other apps.", "#DC2626", "Set up camera"),
        CameraRegistrationState.NotRegistered => new("Setup needed", "Set up once to add FaceNow to the camera list in your meeting or streaming app.", "#DC2626", "Set up camera"),
        CameraRegistrationState.Registered when status.State is CameraOutputState.Stopped or CameraOutputState.Running
            => new("Ready to use", "Start Camera in FaceNow, then choose this camera in your meeting or streaming app.", "#15803D", Ready: true),
        _ => new("Checking", "Checking camera availability…", "#DC2626")
    };

    private void RefreshVirtualCameraUi()
    {
        var status = CameraUsageStatus;
        var usage = DescribeCameraUsage(status, CanSetUpCamera);
        var button = homeVirtualCamera;
        button.Text = CameraUsageLabel;
        button.Available = usage.Ready && !IsCameraSetupBusy;
        button.IsEnabled = !IsCameraSetupBusy;
        button.Accent = false;
        button.Secondary = false;
        button.Destructive = false;
        button.Refresh();
        string helpText = IsCameraSetupBusy ? "Setting up your camera. Please wait…"
            : usage.Title.Length == 0 ? usage.Description : usage.Title + ". " + usage.Description;
        ToolTipService.SetToolTip(button, helpText);
        AutomationProperties.SetName(button, CameraUsageLabel);
        AutomationProperties.SetHelpText(button, helpText);
        if (virtualCameraPopup?.IsOpen == true) refreshCameraUsage?.Invoke();
    }

    private async Task SynchronizeVirtualCameraStatusAsync()
    {
        if (!initialized || closing || closed || Model.Active || Model.IsPreview || cameraSetupPreview
            || virtualCameraOutput.IsBusy || cameraStatusRefreshing) return;
        cameraStatusRefreshing = true;
        try { await virtualCameraOutput.RefreshAsync(); }
        catch (Exception error) { if (!closing && !closed) Model.ReportError(error); }
        finally { cameraStatusRefreshing = false; if (!closing && !closed) RefreshVirtualCameraUi(); }
    }

    private void OpenVirtualCameraSettings(FrameworkElement anchor)
    {
        if (Model.Active) return;
        RefreshVirtualCameraUi();
        var host = new StackPanel();
        CameraOutputStatus? displayed = null;
        bool previousCanInstall = false;
        refreshCameraUsage = () =>
        {
            var status = CameraUsageStatus;
            bool canInstall = CanSetUpCamera;
            if (displayed == status && previousCanInstall == canInstall) return;
            displayed = status; previousCanInstall = canInstall;
            host.Children.Clear(); host.Children.Add(BuildCameraUsagePanel(status, canInstall, anchor));
        };
        refreshCameraUsage();
        virtualCameraPopup = OpenPopup(anchor, host, 360, 20);
        _ = SynchronizeVirtualCameraStatusAsync();
    }

    private StackPanel BuildCameraUsagePanel(CameraOutputStatus status, bool canInstall, FrameworkElement anchor)
    {
        var usage = DescribeCameraUsage(status, canInstall);
        var panel = new StackPanel { Spacing = 16 };
        var headerRow = new Grid();
        headerRow.ColumnDefinitions.Add(new()); headerRow.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        var heading = Theme.Text("Use FaceNow in other apps", 16); heading.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        heading.TextWrapping = TextWrapping.Wrap; heading.Margin = new(0, 0, 16, 0); headerRow.Children.Add(heading);
        var state = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        state.Visibility = usage.Title.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        state.Children.Add(new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 7, Height = 7, Fill = Theme.Brush(usage.Color), VerticalAlignment = VerticalAlignment.Center });
        var label = Theme.Text(usage.Title, 12, "#6B7380"); label.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        state.Children.Add(label); Grid.SetColumn(state, 1); headerRow.Children.Add(state); panel.Children.Add(headerRow);
        var description = Theme.Text(usage.Description, 13, "#6B7380"); description.TextWrapping = TextWrapping.Wrap;
        panel.Children.Add(description);
        if (usage.Ready)
        {
            var device = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
            device.Children.Add(new Glyph { Kind = "camera", Width = 20, Height = 20, Foreground = Theme.Brush("#2F46E2"), VerticalAlignment = VerticalAlignment.Center });
            var name = Theme.Text(FaceNowCameraName, 13); name.FontWeight = Microsoft.UI.Text.FontWeights.Medium; device.Children.Add(name);
            panel.Children.Add(new Border { Child = device, Padding = new(12), Background = Theme.Brush("#F7F8FA"), CornerRadius = new(10) });
        }
        if (usage.Setup is { } setupLabel)
        {
            var setup = new Pill { Text = setupLabel, Primary = true, Height = 40, IsEnabled = canInstall, HorizontalAlignment = HorizontalAlignment.Stretch };
            AutomationProperties.SetAutomationId(setup, "camera_setup");
            setup.Click += async (_, _) =>
            {
                if (cameraSetupPreview) await SimulateCameraSetupAsync(anchor);
                else await RunCameraActionAsync(virtualCameraOutput.InstallAndEnableAsync, anchor);
            };
            panel.Children.Add(setup);
            var permission = Theme.Text("Windows will ask for administrator permission.", 11, "#6B7380");
            permission.TextWrapping = TextWrapping.Wrap; panel.Children.Add(permission);
        }
        if (status.Registration is CameraRegistrationState.Unsupported or CameraRegistrationState.ComponentMissing) return panel;
        var help = new StackPanel { Spacing = 8, Visibility = Visibility.Collapsed };
        var tip = Theme.Text("After setup, reopen the camera list in your other app. If FaceNow is still missing, restart that app.", 12, "#6B7380"); tip.TextWrapping = TextWrapping.Wrap;
        help.Children.Add(tip);
        var links = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 20 };
        var refresh = Theme.Link("Check again", () => { });
        refresh.Click += async (_, _) =>
        {
            if (cameraSetupPreview) OpenVirtualCameraSettings(anchor);
            else await RunCameraActionAsync(virtualCameraOutput.RefreshAsync, anchor);
        };
        links.Children.Add(refresh);
        links.Children.Add(Theme.Link("Camera permissions", () => { ClosePopups(); OpenLink("ms-settings:privacy-webcam"); }));
        help.Children.Add(links);
        string helpTitle = usage.Ready ? "Can't find FaceNow?" : "Need help?";
        Button? helpLink = null;
        helpLink = Theme.Link(helpTitle, () =>
        {
            bool expanded = help.Visibility == Visibility.Collapsed;
            help.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
            ((TextBlock)helpLink!.Content).Text = expanded ? "Hide help" : helpTitle;
        });
        ((TextBlock)helpLink.Content).Foreground = Theme.Brush("#2F46E2");
        helpLink.HorizontalAlignment = HorizontalAlignment.Left; helpLink.Height = 24;
        AutomationProperties.SetAutomationId(helpLink, "camera_help");
        panel.Children.Add(helpLink); panel.Children.Add(help);
        return panel;
    }

    private async Task RunCameraActionAsync(Func<Task> action, FrameworkElement anchor)
    {
        ClosePopups();
        try
        {
            await action();
            await Model.SynchronizeCameraOutputAsync();
            if (!Model.Active && !Model.IsPreview) await Model.RefreshCamerasAsync();
        }
        catch (Exception error) { Model.ReportError(error); }
        if (!closing)
        {
            RefreshVirtualCameraUi();
            if (!Model.Active) OpenVirtualCameraSettings(anchor);
        }
    }

}
