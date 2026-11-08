//
//  MainWindow.VirtualMicrophone.cs
//  FaceNow
//

using FaceNow.App.Controls;
using FaceNow.Windows.Studio.ViewModels;
using FaceNow.Windows.VirtualMicrophone;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private ContentDialog? virtualMicrophoneDialog;

    private string GetMicrophoneInstructions()
    {
        string name = Model.VirtualMicrophoneOutputName;
        string instructions = AppText.Format(
            "In your meeting app, select “{0}” as the microphone. Local listening volume does not affect this output. When no audio is available, the microphone outputs silence.",
            name
        );
        if (name.StartsWith(VbCablePlayback.OutputEndpointLabel, StringComparison.OrdinalIgnoreCase))
            instructions += "\n\n" + AppText.Format("To show it as “{0}”, open Sound Settings, choose “{1}” under Input, and rename it.",
                AppText.Get("FaceNow Virtual Microphone"), name);
        return instructions;
    }

    private static (string Label, string Color) DescribeVirtualMicrophone(
        VirtualMicrophoneState state
    ) => state switch
    {
        VirtualMicrophoneState.Enabled => ("Enabled", "#15803D"),
        VirtualMicrophoneState.Disabled => ("Disabled", "#DC2626"),
        VirtualMicrophoneState.NotInstalled => ("Not Installed", "#D97706"),
        VirtualMicrophoneState.Pending => ("Pending", "#D97706"),
        VirtualMicrophoneState.Failed => ("Error", "#DC2626"),
        _ => ("Checking", "#6B7380")
    };

    private ContentDialog CreateVirtualMicrophoneDialog(
        VirtualMicrophoneState state,
        Action<ContentDialogResult>? choose = null
    )
    {
        string primary = state switch
        {
            VirtualMicrophoneState.NotInstalled => "Install",
            VirtualMicrophoneState.Disabled => "Enable",
            VirtualMicrophoneState.Enabled => "Disable",
            _ => "Recheck Virtual Microphone"
        };
        string description = state switch
        {
            VirtualMicrophoneState.NotInstalled => AppText.Get("Install the VB-CABLE audio driver. Administrator authorization is required. After installation, return here to enable the virtual microphone."),
            VirtualMicrophoneState.Pending => AppText.Get("The audio driver is installed, but Windows has not made the virtual microphone available. Check Sound Settings, then check again."),
            VirtualMicrophoneState.Enabled or VirtualMicrophoneState.Disabled =>
                GetMicrophoneInstructions() + "\n\n" + AppText.Get(DescribeVirtualMicrophone(state).Label),
            VirtualMicrophoneState.Failed => AppText.Get("Virtual microphone output failed. Check that VB-CABLE is available."),
            _ => AppText.Get("Checking")
        };
        var dialog = new ContentDialog
        {
            XamlRoot = root.XamlRoot,
            Background = Theme.Brush("#00FFFFFF"),
            BorderThickness = new(0),
            Padding = new(0),
            HorizontalContentAlignment = HorizontalAlignment.Center
        };
        AutomationProperties.SetName(dialog, AppText.Get("Virtual Microphone"));

        var panel = new StackPanel();
        panel.Children.Add(new Image
        {
            Width = 64,
            Height = 64,
            HorizontalAlignment = HorizontalAlignment.Left,
            Margin = new(4, 0, 0, 16),
            Source = new BitmapImage(new Uri("ms-appx:///Assets/FaceNow.png"))
        });
        var title = Theme.Text("Virtual Microphone", 13, "#222222");
        title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        title.Margin = new(6, 0, 6, 16);
        panel.Children.Add(title);
        var body = Theme.RawText(description, 13, "#222222");
        body.Margin = new(6, 0, 6, 16);
        body.TextWrapping = TextWrapping.Wrap;
        panel.Children.Add(body);

        var actions = new StackPanel { Spacing = 6 };
        var primaryButton = AddAction(primary, "microphone_primary", ContentDialogResult.Primary);
        AddAction("Close Window", "microphone_close", ContentDialogResult.None);
        AddAction("Sound Settings", "microphone_sound_settings", ContentDialogResult.Secondary);
        panel.Children.Add(actions);
        dialog.Content = new Border
        {
            Width = 260,
            Padding = new(16, 20, 16, 16),
            CornerRadius = new(28),
            Background = Theme.Brush("#EEEEEE"),
            Child = panel
        };
        dialog.Opened += (_, _) => primaryButton.Focus(FocusState.Programmatic);
        dialog.KeyDown += (_, args) =>
        {
            if (args.Key != global::Windows.System.VirtualKey.Escape)
                return;
            args.Handled = true;
            dialog.Hide();
        };
        return dialog;

        Button AddAction(
            string label,
            string id,
            ContentDialogResult result
        )
        {
            var button = new Button
            {
                Template = Theme.ButtonTemplate,
                Content = Theme.Text(label, 13, "#222222"),
                Height = 28,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Center,
                VerticalContentAlignment = VerticalAlignment.Center,
                Padding = new(0),
                BorderThickness = new(0),
                CornerRadius = new(14),
                Background = Theme.Brush("#DDDDDD")
            };
            AutomationProperties.SetName(button, AppText.Get(label));
            AutomationProperties.SetAutomationId(button, id);
            button.PointerEntered += (_, _) => button.Background = Theme.Brush("#D2D2D2");
            button.PointerExited += (_, _) => button.Background = Theme.Brush("#DDDDDD");
            button.Click += (_, _) =>
            {
                choose?.Invoke(result);
                dialog.Hide();
            };
            actions.Children.Add(button);
            return button;
        }
    }

    private async Task ShowVirtualMicrophoneSetupAsync(
        FrameworkElement anchor
    )
    {
        if (virtualMicrophoneDialog is not null || closing || Model.Active)
            return;
        ClosePopups();
        var state = Model.VirtualMicrophoneStatus;
        var result = ContentDialogResult.None;
        var dialog = CreateVirtualMicrophoneDialog(state, choice => result = choice);
        virtualMicrophoneDialog = dialog;
        try
        {
            await dialog.ShowAsync();
            if (closing || Model.IsPreview)
                return;
            if (result == ContentDialogResult.Secondary)
                OpenLink("ms-settings:sound");
            if (result != ContentDialogResult.Primary)
                return;
            switch (state)
            {
                case VirtualMicrophoneState.Enabled:
                case VirtualMicrophoneState.Disabled:
                    Model.SetVirtualMicrophoneEnabled(state == VirtualMicrophoneState.Disabled);
                    break;
                case VirtualMicrophoneState.NotInstalled:
                    OpenLink("https://vb-audio.com/Cable/");
                    break;
                default:
                    await Model.RefreshVirtualMicrophoneAsync(retry: true);
                    if (!closing)
                        OpenVirtualCameraSettings(anchor);
                    break;
            }
        }
        catch (Exception error)
        {
            if (!closing)
                Model.ReportError(error);
        }
        finally
        {
            virtualMicrophoneDialog = null;
        }
    }
}
