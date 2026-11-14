//
//  MainWindow.Verification.Video.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;
using Xmax.SDK;
using Xmax.SDK.WinUI;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private void VerifyGenerationLayout()
    {
        var local = localVideoPanel.TransformToVisual(videoRow).TransformPoint(default);
        var result = resultVideoPanel.TransformToVisual(videoRow).TransformPoint(default);
        Check(Math.Abs(local.Y - result.Y) < 1 && Math.Abs(localVideoPanel.ActualWidth - resultVideoPanel.ActualWidth) < 1 &&
            Math.Abs(result.X - local.X - localVideoPanel.ActualWidth - VideoPanelSpacing) < 1 &&
            Math.Abs(localVideoPanel.ActualHeight - localVideoPanel.ActualWidth * 9 / 16) < 1 &&
            Math.Abs(resultVideoPanel.ActualHeight - localVideoPanel.ActualHeight) < 1,
            "Generation must have two equal 16:9 canvases with a 24-pixel gap.");
        var audio = sessionAudioControls.TransformToVisual(videoRow).TransformPoint(default);
        Check(Math.Abs(audio.X - local.X) < 1 && Math.Abs(sessionAudioControls.ActualWidth - videoRow.ActualWidth) < 1 &&
            Math.Abs(audio.Y - videoRow.ActualHeight - 12) < 1,
            "The audio bar must span the two canvases and sit 12 pixels below them.");
    }

    private async Task VerifyFramesAsync()
    {
        VerifyGenerationLayout();
        using var client = new XmaxClient();
        await using var realtime = client.CreateRealtimeManager();
        var source = new VideoVerificationSource();
        var stream = await realtime.CreateExternalVideoStreamAsync(source);
        var sink = source.Sink!;
        localVideoView.Track = stream.VideoTrack;
        Model.StatisticsVisible = false;
        localVideoView.Width = 160;
        localVideoView.Height = 80;
        byte[] pixels = new byte[64 * 8];
        for (int y = 0; y < 8; ++y)
            for (int x = 0; x < 16; ++x)
            {
                int i = y * 64 + x * 4;
                pixels[i + (x < 8 ? 2 : 0)] = 255;
                pixels[i + 3] = 255;
            }
        workspace.Visibility = Visibility.Collapsed;
        sink.PushBgra(pixels, 64, 1000);
        await UntilAsync(() => localVideoView.PresentedFrameCount >= 1);
        workspace.Visibility = Visibility.Visible;
        await Task.Delay(100);
        await VerifyFramePixelsAsync(localVideoView, true);
        await SaveScreenshotAsync("render-mirrored", localVideoView);
        localVideoView.IsMirrored = false;
        await Task.Delay(100);
        await VerifyFramePixelsAsync(localVideoView, false);
        await SaveScreenshotAsync("render-bgra", localVideoView);
        localVideoView.IsMirrored = true;
        sink.PushBgra(pixels, 64, 2000);
        await UntilAsync(() => localVideoView.PresentedFrameCount >= 2);
        await Task.Delay(100);
        await VerifyFramePixelsAsync(localVideoView, true);
        await Task.Run(() => { for (int i = 3; i <= 100; ++i) sink.PushBgra(pixels, 64, i * 1000); });
        await UntilAsync(() => localVideoView.LastPresentedTimestampMicroseconds == 100000);
        localVideoPanel.Children.Remove(localVideoView);
        await Task.Delay(50);
        localVideoPanel.Children.Insert(0, localVideoView);
        sink.PushBgra(pixels, 64, 101000);
        await UntilAsync(() => localVideoView.LastPresentedTimestampMicroseconds == 101000);
        await using var resultController = client.CreateRealtimeManager();
        var resultSource = new VideoVerificationSource();
        var result = await resultController.CreateExternalVideoStreamAsync(resultSource);
        resultVideoView.Width = 160;
        resultVideoView.Height = 80;
        resultVideoView.Track = result.VideoTrack;
        Check(resultVideoView.PresentedFrameCount == 0, "Result appeared before its first frame.");
        resultSource.Sink!.PushBgra(pixels, 64, 1000);
        await UntilAsync(() => resultVideoView.PresentedFrameCount == 1);
        await Task.Delay(350);
        await VerifyFramePixelsAsync(resultVideoView, true);
        sink.PushBgra(pixels, 64, 102000);
        await UntilAsync(() => localVideoView.LastPresentedTimestampMicroseconds == 102000);
        resultVideoView.Track = null;
        Check(resultVideoView.PresentedFrameCount == 0 && localVideoView.PresentedFrameCount > 0,
            "Clearing the result must leave the local preview running.");
        localVideoView.Track = null;
        await VerifyGenerationMicrophoneLevelAsync();
    }

    private async Task VerifyGenerationMicrophoneLevelAsync()
    {
        string Level() => AutomationProperties.GetItemStatus(sessionInputLevel);
        Check(
            sessionInputLevel.Visibility == Visibility.Collapsed,
            "The input meter must start hidden with the microphone off."
        );
        await Model.SelectMicrophoneAsync(RealtimeMicrophone.SystemDefault);
        var receiveLevel = Model.CreateMicrophoneLevelHandler();
        receiveLevel(.55f);
        await UntilAsync(() => sessionInputLevel.Visibility == Visibility.Visible && Level() == "55%");
        receiveLevel(.60f);
        await UntilAsync(() => Level() == "60%");
        await Task.Delay(350);
        await SaveScreenshotAsync("generation-microphone-level", sessionAudioControls);

        receiveLevel(null);
        await UntilAsync(() => Level() == "0%");
        await Model.SelectMicrophoneAsync(RealtimeMicrophone.Disabled);
        receiveLevel(1);
        await UntilAsync(() => sessionInputLevel.Visibility == Visibility.Collapsed);
        Check(Level() == "0%", "A microphone-off generation page retained an input level.");

        await Model.StopAsync();
        await Model.StartLandingAsync();
        await Model.SelectMicrophoneAsync(RealtimeMicrophone.SystemDefault);
        receiveLevel(1);
        await Task.Delay(100);
        Check(Level() == "0%", "The input meter accepted a reading from the previous session.");
        await Model.SelectMicrophoneAsync(RealtimeMicrophone.Disabled);
    }

    private static async Task VerifyFramePixelsAsync(
        XmaxRealtimeVideoView video,
        bool mirrored
    )
    {
        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(video, 160, 80);
        using var reader = DataReader.FromBuffer(await bitmap.GetPixelsAsync());
        byte[] bytes = new byte[reader.UnconsumedBufferLength];
        reader.ReadBytes(bytes);
        int left = (bitmap.PixelHeight / 2 * bitmap.PixelWidth + bitmap.PixelWidth / 8) * 4;
        int right = (bitmap.PixelHeight / 2 * bitmap.PixelWidth + bitmap.PixelWidth * 7 / 8) * 4;
        Check(
            bytes[left + (mirrored ? 0 : 2)] > 200 && bytes[right + (mirrored ? 2 : 0)] > 200,
            "WinUI displayed pixels or mirror metadata differ from the input."
        );
    }

    private sealed class VideoVerificationSource : IRealtimeExternalVideoSource
    {
        public VideoFormat VideoFormat => new(16, 8);

        public IRealtimeExternalFrameSink? Sink { get; private set; }

        public Task StartAsync(
            IRealtimeExternalFrameSink sink,
            CancellationToken cancellationToken
        )
        {
            Sink = sink;
            return Task.CompletedTask;
        }

        public Task StopAsync()
        {
            Sink = null;
            return Task.CompletedTask;
        }
    }
}
