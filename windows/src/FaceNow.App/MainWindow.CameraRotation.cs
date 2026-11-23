//
//  MainWindow.CameraRotation.cs
//  FaceNow
//

using FaceNow.App.Controls;
using FaceNow.App.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Xmax.SDK;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private Popup? cameraRotationPopup;

    private void OpenCameraRotation()
    {
        if (!Model.CanEdit)
            return;

        var list = new StackPanel { Spacing = 2 };
        Button? selectedItem = null;
        foreach (var rotation in Enum.GetValues<CameraRotation>())
        {
            bool selected = rotation == Model.SelectedRotation;
            var label = LoginTypography.Text($"{(int)rotation}°", 13.5, "#FFFFFF");
            label.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
            var row = new Grid { ColumnSpacing = 4 };
            row.ColumnDefinitions.Add(new() { Width = new(16) });
            row.ColumnDefinitions.Add(new());
            row.Children.Add(new SymbolIcon(Symbol.Accept)
            {
                Foreground = Theme.Brush("#FFFFFF"),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Visibility = selected ? Visibility.Visible : Visibility.Collapsed
            });
            Grid.SetColumn(label, 1);
            row.Children.Add(label);
            var fill = Theme.Brush(selected ? "#007AFF" : "#00000000");
            var item = new Button
            {
                Template = Theme.ButtonTemplate,
                Content = row,
                Height = 28,
                Padding = new(6, 0, 6, 0),
                BorderThickness = new(0),
                CornerRadius = new(8),
                Background = fill,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                HorizontalAlignment = HorizontalAlignment.Stretch
            };
            AutomationProperties.SetName(item, label.Text);
            AutomationProperties.SetAutomationId(item, $"camera_rotation_{(int)rotation}");
            if (selected)
            {
                selectedItem = item;
                AutomationProperties.SetItemStatus(item, AppText.Get("Selected"));
            }
            item.PointerEntered += (_, _) => LoginMotion.Color(item, fill, selected ? "#007AFF" : "#1FFFFFFF");
            item.PointerExited += (_, _) => LoginMotion.Color(item, fill, selected ? "#007AFF" : "#00000000");
            item.Click += (_, _) =>
            {
                Model.SelectedRotation = rotation;
                ClosePopups();
                cameraRotation.Focus(FocusState.Programmatic);
            };
            list.Children.Add(item);
        }
        var popup = OpenPopup(cameraRotation, list, 88, 5, cornerRadius: 12,
            background: "#EB3C3C43", border: "#66FFFFFF");
        cameraRotationPopup = popup;
        DispatcherQueue.TryEnqueue(() =>
        {
            if (popup.IsOpen)
                selectedItem?.Focus(FocusState.Programmatic);
        });
    }
}
