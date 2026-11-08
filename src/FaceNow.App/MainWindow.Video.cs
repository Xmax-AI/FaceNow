//
//  MainWindow.Video.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using FaceNow.App.Controls;
using FaceNow.Windows.Studio.ViewModels;
using Xmax.SDK;
using Xmax.SDK.WinUI;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private void ConfigureVideoRow()
    {
        videoRow.ColumnDefinitions.Add(new());
        videoRow.ColumnDefinitions.Add(new());
        Grid.SetColumn(resultVideoPanel, 1);
        videoRow.Children.Add(localVideoPanel);
        videoRow.Children.Add(resultVideoPanel);

        ConfigureVideoCanvas(localVideoPanel, localVideoView, localPlaceholder, localStatistics, "Preview",
            [Model.TimingRows, Model.UplinkRows, Model.UplinkNetworkRows]);
        ConfigureVideoCanvas(resultVideoPanel, resultVideoView, resultPlaceholder, remoteStatistics, "Result",
            [Model.DownlinkRows, Model.DownlinkNetworkRows]);

        var caption = Theme.Text("Preview", 12, "#A6FFFFFF");
        caption.FontFamily = new("Segoe UI");
        localVideoPanel.Children.Add(new Border
        {
            Child = caption,
            Background = Theme.Brush("#59000000"),
            CornerRadius = new(8),
            Padding = new(6, 3, 6, 3),
            Margin = new(12),
            IsHitTestVisible = false,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top
        });
    }

    private static void ConfigureVideoCanvas(
        Grid canvas,
        XmaxRealtimeVideoView video,
        TextBlock placeholder,
        StackPanel statistics,
        string title,
        MetricRow[][] groups
    )
    {
        canvas.Background = Theme.Brush("#000000");
        RoundedClip.Attach(canvas, 24);
        AutomationProperties.SetName(canvas, AppText.Get(title));
        canvas.Children.Add(video);

        placeholder.FontFamily = new("Segoe UI");
        placeholder.TextAlignment = TextAlignment.Center;
        placeholder.TextWrapping = TextWrapping.Wrap;
        placeholder.Margin = new(20, 0, 20, 0);
        placeholder.IsHitTestVisible = false;
        canvas.Children.Add(placeholder);

        statistics.Margin = new(14, 12, 14, 0);
        statistics.VerticalAlignment = VerticalAlignment.Top;
        statistics.HorizontalAlignment = HorizontalAlignment.Left;
        foreach (var rows in groups)
            statistics.Children.Add(MetricBox(rows));
        canvas.Children.Add(statistics);
    }

    private void RefreshVideoPanels()
    {
        var format = Model.SelectedFormat;
        localVideoView.ContentMode = resultVideoView.ContentMode = format.Width * 9 == format.Height * 16
            ? VideoContentMode.Fill : VideoContentMode.Fit;
        localPlaceholder.Text = Model.LocalPlaceholder;
        resultPlaceholder.Text = Model.ResultPlaceholder;
        localStatistics.Visibility = remoteStatistics.Visibility = Model.StatisticsVisible ? Visibility.Visible : Visibility.Collapsed;
    }
}
