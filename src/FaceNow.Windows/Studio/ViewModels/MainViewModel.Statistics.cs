//
//  MainViewModel.Statistics.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using FaceNow.Core.Localization;
using FaceNow.Windows.VirtualCamera;
using Xmax.SDK;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private readonly long[] lastStatisticsLog = new long[2];

    private void ReceiveUplinkStatistics(
        UplinkVideoStatistics? stats
    )
    {
        int? fps = stats?.SendFrameRate;
        UpdateVideoRows(UplinkRows, stats?.Width, stats?.Height, fps, stats?.BitrateKbps);
        UplinkNetworkRows[0].Value = FormatMetric(stats?.PacketLossPercent, "%");
        UpdateVideoSummary(false, stats?.Width, stats?.Height, fps, stats?.BitrateKbps, null);
    }

    private void ReceiveDownlinkStatistics(
        DownlinkVideoStatistics? stats
    )
    {
        int? fps = stats?.RenderFrameRate ?? stats?.DecodeFrameRate;
        UpdateVideoRows(DownlinkRows, stats?.Width, stats?.Height, fps, stats?.BitrateKbps);
        DownlinkNetworkRows[1].Value = FormatMetric(stats?.PacketLossPercent, "%");
        DownlinkNetworkRows[4].Value = FormatMetric(stats?.EndToEndDelayMs, " ms");
        UpdateVideoSummary(
            true,
            stats?.Width,
            stats?.Height,
            fps,
            stats?.BitrateKbps,
            stats?.EndToEndDelayMs
        );
    }

    private static void UpdateVideoRows(
        MetricRow[] rows,
        int? width,
        int? height,
        int? fps,
        int? bitrate
    )
    {
        rows[0].Value = width is > 0 && height is > 0 ? $"{width}×{height}" : "—";
        rows[1].Value = FormatMetric(fps, " fps");
        rows[2].Value = FormatMetric(bitrate, " kbps");
    }

    private static string FormatMetric(
        int? value,
        string unit = ""
    ) => value is { } measured ? $"{measured}{unit}" : "—";

    private void UpdateVideoSummary(
        bool downlink,
        int? width,
        int? height,
        int? fps,
        int? bitrate,
        int? delay
    )
    {
        if (width is not > 0 || height is not > 0)
            return;
        Metrics = AppText.Format("{0}  {1} × {2}  ·  {3} fps  ·  {4} kbps  ·  Latency {5} ms",
            AppText.Get(downlink ? "Downlink" : "Uplink"), width, height, FormatMetric(fps), FormatMetric(bitrate), FormatMetric(delay));
        int direction = downlink ? 1 : 0;
        long now = Environment.TickCount64;
        if (now - lastStatisticsLog[direction] >= 10000)
        {
            lastStatisticsLog[direction] = now;
            CameraDiagnostics.Write($"RTC {(downlink ? "downlink" : "uplink")} {width}x{height} fps={fps} kbps={bitrate}");
        }
    }

    private void ReceiveLaunchTiming(RealtimeLaunchTiming timing)
    {
        double?[] values = [timing.SessionMilliseconds, timing.RtcJoinMilliseconds, timing.PublishMilliseconds,
            timing.FirstFrameMilliseconds, timing.TotalMilliseconds];
        for (int i = 0; i < values.Length; ++i)
            TimingRows[i].Value = values[i] is { } milliseconds ? $"{milliseconds:F1} ms" : "—";
        if (timing.FirstFrameMilliseconds is { } firstFrame && timing.TotalMilliseconds is { } total)
            Metrics = AppText.Format("First frame {0:F0} ms  ·  Total startup {1:F0} ms", firstFrame, total);
    }

    private void ReceiveNetworkQuality(RealtimeNetworkQuality quality)
    {
        UplinkNetworkRows[1].Value = FormatNetworkQuality(quality.Uplink);
        DownlinkNetworkRows[2].Value = FormatNetworkQuality(quality.Downlink);
    }

    private static string FormatNetworkQuality(RealtimeNetworkQualityLevel quality) =>
        quality == RealtimeNetworkQualityLevel.Unknown ? "—" : ((int)quality).ToString();
}
