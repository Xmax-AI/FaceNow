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
using Microsoft.UI.Xaml.Controls.Primitives;
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
    private readonly ToolbarButton sessionAudioAdjustments = new(tone: ToolbarButtonTone.SoftAccent)
    {
        Text = AudioVideoAdjustmentView.Title, Glyph = "adjustments"
    };
    private readonly Border sessionAudioControls = new() { Height = ToolbarButton.ControlHeight + 16, Margin = new(0, 12, 0, 0), Padding = new(8, 0, 8, 0),
        CornerRadius = new(16), Background = Theme.Brush("#FFFFFF"),
        BorderThickness = new(1), BorderBrush = Theme.Brush("#E5E7EB") };
    private Popup? audioAdjustmentPopup;

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
        var row = new Grid { VerticalAlignment = VerticalAlignment.Center, ColumnSpacing = 20 };
        row.ColumnDefinitions.Add(new());
        row.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
        row.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal, Spacing = 12, VerticalAlignment = VerticalAlignment.Center,
            Children = { sessionMicrophone, sessionInputLevel }
        });
        Grid.SetColumn(sessionAudioAdjustments, 1);
        row.Children.Add(sessionAudioAdjustments);
        sessionAudioControls.Child = row;
        Model.MicrophoneLevelChanged += sessionInputLevel.Update;
        sessionAudioAdjustments.Click += (_, _) => OpenAudioAdjustments();
        root.SizeChanged += (_, _) => { if (audioAdjustmentPopup?.IsOpen == true) ClosePopups(); };
    }

    private void OpenAudioAdjustments()
    {
        if (audioAdjustmentPopup?.IsOpen == true) { ClosePopups(); return; }
        var content = new AudioVideoAdjustmentView(Model.AudioSyncOffsetMilliseconds, Model.IsPreview,
            Model.SetAudioSyncOffsetMilliseconds,
            () => { ClosePopups(); sessionAudioAdjustments.Focus(FocusState.Programmatic); });
        var popup = OpenPopup(sessionAudioAdjustments, content, 480, 23, above: null, cornerRadius: 16);
        audioAdjustmentPopup = popup;
        DispatcherQueue.TryEnqueue(() => { if (popup.IsOpen) content.FocusCloseButton(); });
    }

    private void RefreshMicrophoneUi()
    {
        var selection = Model.Microphone;
        string name = selection.DeviceId is not null
            ? Model.SelectedMicrophoneName ?? "Select Microphone"
            : selection.IsEnabled ? "System Default Microphone" : "Microphone Off";
        foreach (var button in new Pill[] { homeMicrophone, sessionMicrophone })
        {
            button.IsEnabled = !Model.Busy && !Model.IsPreview;
            button.Text = name;
            ToolTipService.SetToolTip(button, button.Text);
        }
        sessionMicrophone.Glyph = selection.IsEnabled ? "microphone" : "microphoneOff";
        sessionInputLevel.SetPresented(Model.Active && selection.IsEnabled, animateHide: Model.Active);
        sessionAudioAdjustments.IsEnabled = Model.Active && !Model.IsClosing;
    }

    private async Task OpenMicrophonesAsync(Pill anchor)
    {
        try
        {
            var (devices, showSystemDefault) = await Model.ListMicrophonesAsync();
            if (closing || !anchor.IsEnabled || !anchor.IsLoaded || accountRepository?.CanAccessHome == false
                || Model.Active != (anchor == sessionMicrophone)) return;
            RefreshMicrophoneUi();

            // The packaged WinUI runtime can fail to load RadioMenuFlyoutItem's default style.
            var list = new StackPanel { Spacing = 2 };
            Button? selectedItem = null;
            if (showSystemDefault)
                Add(AppText.Get("System Default Microphone"), RealtimeMicrophone.SystemDefault);
            foreach (var device in devices)
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
