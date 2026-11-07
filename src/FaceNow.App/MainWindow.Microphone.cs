//
//  MainWindow.Microphone.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;
using Xmax.SDK;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private const double ModeTabsTopSpacing = 24;
    private readonly LandingInputButton homeMicrophone = new("Microphone Off");
    private readonly ToolbarButton sessionMicrophone = new(ToolbarButtonRole.Menu, ToolbarButtonTone.SoftAccent)
    {
        Text = "Microphone Off", Glyph = "microphoneOff", MaxWidth = 280, LabelMaxWidth = 190,
        HorizontalAlignment = HorizontalAlignment.Left, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
    };
    private readonly InputLevelMeter sessionInputLevel = new();
    private readonly Border sessionAudioControls = new() { Height = ToolbarButton.ControlHeight + 16, Margin = new(0, 12, 0, 0), Padding = new(8, 0, 8, 0),
        CornerRadius = new(16), Background = Theme.Brush("#FFFFFF"),
        BorderThickness = new(1), BorderBrush = Theme.Brush("#E5E7EB") };
    private IReadOnlyList<MicrophoneDevice> microphoneDevices = [];

    private void BindMicrophones()
    {
        foreach (var button in new Pill[] { homeMicrophone, sessionMicrophone })
        {
            AutomationProperties.SetName(button, AppText.Get("Select Microphone"));
            button.Click += async (_, _) => await OpenMicrophonesAsync(button);
        }
    }

    private void BuildSessionAudioControls()
    {
        sessionAudioControls.Child = new StackPanel
        {
            Orientation = Orientation.Horizontal, Spacing = 12, VerticalAlignment = VerticalAlignment.Center,
            Children = { sessionMicrophone, sessionInputLevel }
        };
        Model.MicrophoneLevelChanged += sessionInputLevel.Update;
    }

    private void RefreshMicrophoneUi()
    {
        var selection = Model.Microphone;
        string name = selection.DeviceId is { } id
            ? microphoneDevices.FirstOrDefault(device => device.Id == id)?.Name ?? "Select Microphone"
            : selection.IsEnabled ? "System Default Microphone" : "Microphone Off";
        foreach (var button in new Pill[] { homeMicrophone, sessionMicrophone })
        {
            button.IsEnabled = !Model.Busy && !Model.IsPreview;
            button.Text = name;
            ToolTipService.SetToolTip(button, button.Text);
        }
        sessionMicrophone.Glyph = selection.IsEnabled ? "microphone" : "microphoneOff";
        bool showLevel = Model.Active && selection.IsEnabled;
        sessionInputLevel.Visibility = showLevel ? Visibility.Visible : Visibility.Collapsed;
        if (!showLevel) sessionInputLevel.Update(null);
    }

    private async Task OpenMicrophonesAsync(Pill anchor)
    {
        try
        {
            var (devices, showSystemDefault) = await Model.ListMicrophonesAsync();
            if (closing || !anchor.IsEnabled || !anchor.IsLoaded || accountRepository?.CanAccessHome == false
                || Model.Active != (anchor == sessionMicrophone)) return;
            microphoneDevices = devices;
            RefreshMicrophoneUi();

            // The packaged WinUI runtime can fail to load RadioMenuFlyoutItem's default style.
            var list = new StackPanel { Spacing = 2 };
            Button? selectedItem = null;
            if (showSystemDefault)
                Add(AppText.Get("System Default Microphone"), RealtimeMicrophone.SystemDefault);
            foreach (var device in microphoneDevices)
                Add(device.Name, RealtimeMicrophone.Device(device.Id));
            Add(AppText.Get("Microphone Off"), RealtimeMicrophone.Disabled);

            const double width = 276, padding = 8;
            var scroll = new ScrollViewer
            {
                Content = list, MaxHeight = 250, HorizontalScrollMode = ScrollMode.Disabled,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
            scroll.Measure(new Size(width - padding * 2, double.PositiveInfinity));
            double anchorBottom = anchor.TransformToVisual(root).TransformPoint(new Point(0, anchor.ActualHeight)).Y;
            var popup = OpenPopup(anchor, scroll, width, padding,
                above: anchorBottom + 8 + padding * 2 + scroll.DesiredSize.Height > root.ActualHeight);
            DispatcherQueue.TryEnqueue(() =>
            {
                if (popup.IsOpen) (selectedItem ?? (Button)list.Children[0]).Focus(FocusState.Programmatic);
            });

            void Add(string label, RealtimeMicrophone selection)
            {
                bool selected = selection == Model.Microphone;
                var item = CreateInputPickerRow(label, selected);
                if (selected) selectedItem = item;
                item.Click += async (_, _) =>
                {
                    ClosePopups();
                    anchor.Focus(FocusState.Programmatic);
                    await Model.SelectMicrophoneAsync(selection);
                };
                list.Children.Add(item);
            }
        }
        catch (Exception error) { Model.ReportError(error); }
    }
}
