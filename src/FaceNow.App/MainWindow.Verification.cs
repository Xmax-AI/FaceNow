// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.IO;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
using FaceNow.Windows.Studio.ViewModels;
using Xmax.SDK;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    internal async Task SaveScreenshotAsync(string name, FrameworkElement? element = null, double renderScale = 1)
    {
        string? output = Environment.GetEnvironmentVariable("FACENOW_SMOKE_OUTPUT");
        if (string.IsNullOrEmpty(output)) return;
        Directory.CreateDirectory(output);
        var target = element ?? root;
        await Task.Delay(150);
        var bitmap = new RenderTargetBitmap(); await bitmap.RenderAsync(target, (int)(target.ActualWidth * renderScale), (int)(target.ActualHeight * renderScale));
        using var reader = DataReader.FromBuffer(await bitmap.GetPixelsAsync());
        byte[] pixels = new byte[reader.UnconsumedBufferLength]; reader.ReadBytes(pixels);
        using var stream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, pixels);
        encoder.BitmapTransform.ScaledWidth = (uint)(target.ActualWidth * renderScale);
        encoder.BitmapTransform.ScaledHeight = (uint)(target.ActualHeight * renderScale);
        await encoder.FlushAsync();
        using var encoded = new DataReader(stream.GetInputStreamAt(0)); await encoded.LoadAsync((uint)stream.Size);
        byte[] png = new byte[stream.Size]; encoded.ReadBytes(png); await File.WriteAllBytesAsync(Path.Combine(output, name + ".png"), png);
    }
    private static async Task UntilAsync(Func<bool> condition, int seconds = 20)
    {
        DateTime deadline = DateTime.UtcNow.AddSeconds(seconds);
        while (!condition()) { if (DateTime.UtcNow >= deadline) throw new TimeoutException("WinUI verification did not reach the expected state."); await Task.Delay(30); }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private async Task ClickReferenceAsync(ReferenceItem item)
    {
        Model.SelectedMode = item.Mode; root.UpdateLayout();
        var tile = ReferenceTiles[item]; tile.StartBringIntoView();
        var peer = FrameworkElementAutomationPeer.CreatePeerForElement(tile)!;
        ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
        await UntilAsync(() => item.IsSelected);
        await Model.WaitForConditionsAsync().WaitAsync(TimeSpan.FromSeconds(45));
        Check(Model.Error.Length == 0, Model.Error);
    }
    internal async Task RunSmokeAsync(string mode)
    {
        bool passed = false, referenceUpdatePassed = false;
        string? error = null;
        var transitions = new List<object>();
        var pageEntryStates = new List<RealtimeState>();
        void ObservePageEntry(object? sender, System.ComponentModel.PropertyChangedEventArgs args)
        {
            if (args.PropertyName == nameof(Model.Active) && Model.Active && !Model.IsPreview) pageEntryStates.Add(Model.State);
        }
        Model.PropertyChanged += ObservePageEntry;
        try
        {
            await Task.Delay(650);
            if (mode == "--smoke-test-login-layout") await VerifyLoginLayoutAsync();
            else if (mode == "--smoke-test-account")
            {
                Check(loginView is { IsLoaded: true, Visibility: Visibility.Visible }, "Login page did not appear.");
                Check(scroller.Visibility == Visibility.Collapsed && !StartButton.IsEnabled, "Signed-out account can access the studio.");
                await loginView!.VerifyFormAsync();
                Check(scroller.Visibility == Visibility.Visible && loginView.Visibility == Visibility.Collapsed, "Validated login did not open home.");
                Check(Model.Session is null && Model.Cameras.Count == 0, "Login preview accessed a real camera or generation session.");
                await VerifySignInToastAsync();
                await OpenAccountAsync();
                Check(popups.Any(popup => popup.IsOpen), "Account menu did not open.");
                if (Environment.GetEnvironmentVariable("FACENOW_CAPTURE_ACCOUNT_UI") == "1") await VerifyAccountCardStyleAsync();
                await SignOutAccountAsync();
                Check(loginView.Visibility == Visibility.Visible && scroller.Visibility == Visibility.Collapsed && Model.ApiKey.Length == 0,
                    "Sign-out did not clear studio access and restore login.");
                await loginView.VerifyVideoPlaybackAsync();
                foreach (int method in new[] { 0, 1 })
                {
                    await loginView.VerifyCodeLoginAsync(method);
                    Check(toast.Message == SignedInMessage && toast.NotificationStyle == FaceNow.App.Controls.ToastStyle.Success,
                        "Verification-code login did not show its success notification.");
                    await SignOutAccountAsync();
                    Check(toast.Message is null && loginView.Visibility == Visibility.Visible,
                        "Signing out left a success notification over the login form.");
                }
            }
            else if (mode == "--smoke-test-camera-setup") await VerifyCameraSetupPreviewAsync();
            else if (mode == "--smoke-test-ui")
            {
                Check(homeVirtualCamera.IsLoaded && homeVirtualCamera.Text == CameraUsageLabel, "Home camera usage entry is missing.");
                await SaveScreenshotAsync("aligned-landing");
                await VerifyHomeControlsAsync();
                OpenVirtualCameraSettings(homeVirtualCamera);
                await UntilAsync(() => virtualCameraPopup?.Child is FrameworkElement { IsLoaded: true });
                Check(Model.Session is null, "Opening camera usage created a generation session.");
                await SaveScreenshotAsync("virtual-camera-status", (FrameworkElement)virtualCameraPopup!.Child);
                ClosePopups();
                await VerifyCameraUsageAsync();
                foreach (var (width, height, name) in new[] { (1920,1080,"wide"), (1180,800,"minimum") })
                {
                    ResizeWindow(width,height); await Task.Delay(250); ArrangePage();
                    Check(landingStage.Width <= 940 && Math.Abs(landingStage.Width * 1080 / 1920 - landingStage.Height) < .5, "Landing proportions changed.");
                    await SaveScreenshotAsync("landing-" + name);
                }
                ResizeWindow(1360,890); await Task.Delay(200);
                await Model.StartLandingAsync(); transitions.Add(await VerifyTransitionAsync(true));
                Check(CameraUsageDescendants(sessionControls).OfType<global::Microsoft.UI.Xaml.Controls.TextBlock>().All(label => label.Text != CameraUsageLabel), "Generation toolbar still shows the camera usage entry.");
                await UntilAsync(() => Model.CharacterReferences.All(item => item.IsUpload || item.Thumbnail is not null || item.HasError), 40);
                await ClickReferenceAsync(Model.CharacterReferences.First(item => item.Id == "charx-3"));
                await ClickReferenceAsync(Model.ClothingReferences.First(item => !item.IsUpload));
                await ClickReferenceAsync(Model.StyleReferences.First(item => !item.IsUpload));
                await ClickReferenceAsync(Model.CharacterReferences.First(item => item.Id == "charx-3"));
                await SaveScreenshotAsync("aligned-session");
                foreach (var (width, height, name) in new[] { (1360,1200,"tall"), (1920,1080,"wide"), (1180,800,"minimum") })
                {
                    ResizeWindow(width,height); await Task.Delay(250); ArrangePage();
                    await SaveScreenshotAsync("session-" + name);
                }
                ResizeWindow(1360,890); await Task.Delay(250); ArrangePage();
                await SaveReferenceUploadScreenshotsAsync();
                Model.StatisticsVisible = false; Model.SelectedMode = "free"; await Task.Delay(100); await SaveScreenshotAsync("aligned-free-prompt");
                await Model.SubmitPromptAsync(); Check(Model.Session is null, "UI preview created a native session.");
                Model.StatisticsVisible = true; await Model.StopAsync(); transitions.Add(await VerifyTransitionAsync(false));
                await Model.StartLandingAsync(); await Task.Delay(50); await Model.StopAsync(); await Task.Delay(50); await Model.StartLandingAsync();
                transitions.Add(await VerifyTransitionAsync(true)); await Model.StopAsync(); transitions.Add(await VerifyTransitionAsync(false));
            }
            else if (mode == "--smoke-test-key-gate")
            {
                SetApiKey(""); await Model.StartLandingAsync(); await Task.Delay(200);
                Check(!Model.Active && KeyPopup?.IsOpen == true, "Missing Key did not open the input popup.");
                await SaveScreenshotAsync("api-key-popup", (FrameworkElement)KeyPopup!.Child);
            }
            else if (mode == "--smoke-test-frames") await VerifyFramesAsync();
            else if (mode == "--smoke-test-camera-relay") await VerifyCameraRelayAsync();
            else if (mode == "--smoke-test-virtual-camera")
            {
                Check(virtualCameraOutput.Status.Registration == FaceNow.Core.VirtualCamera.CameraRegistrationState.Registered,
                    "Install and enable the test camera before running this explicit verification.");
                Check(Model.Cameras.All(item => !virtualCameraOutput.IsOwnCamera(item.Id)), "FaceNow was offered as its own physical input.");
                var frame = await CaptureCameraDiagnosticAsync("virtual-camera-capture");
                Check(frame.Width == 1920 && frame.Height == 1080 && frame.Pixels.Length == 1920 * 1080 * 4,
                    "Windows virtual camera did not return a complete 1080p frame.");
                Check(Model.Session is null, "Test camera verification created a cloud session.");
            }
            else if (mode.StartsWith("--smoke-test-key-memory-"))
            {
                const string first = "winui-memory-test-记忆", updated = "winui-memory-test-updated";
                OpenKey();
                await UntilAsync(() => apiKeyInput!.IsLoaded);
                await Task.Delay(80);
                switch (mode["--smoke-test-key-memory-".Length..])
                {
                    case "write": Check(Model.ApiKey.Length == 0, "Test credential was not empty."); apiKeyInput!.Text = first; await UntilAsync(() => Model.ApiKey == first); Check(apiKeyStore!.Load() == first, "Key input was not saved."); SetApiKey("temporary-override"); await Task.Delay(50); Check(apiKeyStore.Load() == first, "Temporary override replaced the saved Key."); break;
                    case "read":
                        Check(Model.ApiKey == first && apiKeyInput!.Text == first, "Key was not restored after restart.");
                        Check(keyButton.Text == "****************", "Header must mask the complete Key.");
                        await SaveScreenshotAsync("api-key-header", homeControls);
                        await SaveScreenshotAsync("api-key-plain", (FrameworkElement)KeyPopup!.Child);
                        apiKeyInput!.Text = updated; await UntilAsync(() => Model.ApiKey == updated); Check(apiKeyStore!.Load() == updated, "Updated Key was not saved."); break;
                    case "clear": Check(Model.ApiKey == updated, "Updated Key was not restored."); apiKeyInput!.Text = ""; await UntilAsync(() => Model.ApiKey.Length == 0); Check(apiKeyStore!.Load().Length == 0, "Clearing input did not delete the saved Key."); break;
                    case "empty": Check(Model.ApiKey.Length == 0 && keyButton.Text.Length == 0, "Deleted Key reappeared after restart."); break;
                }
                ClosePopups();
            }
            else if (mode is "--smoke-test-camera" or "--smoke-test-live")
            {
                string camera = Environment.GetEnvironmentVariable("FACENOW_SMOKE_CAMERA") ?? "MacBook";
                Model.SelectedCamera = Model.Cameras.First(item => item.Name.Contains(camera, StringComparison.OrdinalIgnoreCase));
                if (mode == "--smoke-test-camera") await Model.PreviewAsync();
                else
                {
                    Model.StartCommand.Execute(null);
                    Check(Model.Busy && !Model.Active && Model.StartLabel == "Starting…", "Startup did not stay on the loading landing page.");
                    await SaveScreenshotAsync("startup-landing");
                    await UntilAsync(() => !Model.Busy, 90);
                    Check(Model.Error.Length == 0, Model.Error);
                    Check(pageEntryStates.Count == 1 && pageEntryStates[0] is RealtimeState.Connected or RealtimeState.Generating,
                        "The generation page opened before RTC connected.");
                }
                await UntilAsync(() => LocalView.PresentedFrameCount >= 10);
                if (mode == "--smoke-test-live")
                {
                    await UntilAsync(() => RemoteView.PresentedFrameCount >= 10);
                    if (virtualCameraOutput.Status.Registration == FaceNow.Core.VirtualCamera.CameraRegistrationState.Registered)
                    {
                        VerificationProgress("Live Result playing; opening external virtual camera consumer");
                        long beforeCapture = RemoteView.PresentedFrameCount;
                        long deliveredBefore = virtualCameraOutput.DeliveredFrames;
                        var capture = await CaptureCameraDiagnosticAsync("live-virtual-camera");
                        Check(!IsWaitingCanvas(capture.Pixels), "The external consumer received only the placeholder during AI generation.");
                        Check(virtualCameraOutput.DeliveredFrames >= deliveredBefore + 10, "AI frames were not delivered to the external consumer.");
                        await UntilAsync(() => RemoteView.PresentedFrameCount >= beforeCapture + 10);
                        VerificationProgress("External consumer received AI frames; Result playback continued");
                    }
                    await ClickReferenceAsync(Model.CharacterReferences.First(item => item.Id == "charx-9"));
                    long before = RemoteView.PresentedFrameCount;
                    await UntilAsync(() => RemoteView.PresentedFrameCount >= before + 10);
                    referenceUpdatePassed = true; await Task.Delay(700); await SaveScreenshotAsync("live-reference-update");
                    Model.SelectedMode = "free"; Model.Prompt = "改为柔和的水彩画风格，保持人物和动作一致。";
                    await Model.SubmitPromptAsync().WaitAsync(TimeSpan.FromSeconds(45)); Check(Model.Error.Length == 0, Model.Error);
                }
                Check(Model.Error.Length == 0, Model.Error);
                await SaveScreenshotAsync("local-video", LocalView); if (mode == "--smoke-test-live") await SaveScreenshotAsync("remote-video", RemoteView);
            }
            if (mode is not ("--smoke-test-account" or "--smoke-test-login-layout")) await SaveScreenshotAsync(mode.TrimStart('-'));
            passed = true;
        }
        catch (Exception failure) { error = failure.ToString(); }
        finally
        {
            Model.PropertyChanged -= ObservePageEntry;
            long localFrames = LocalView.PresentedFrameCount, remoteFrames = RemoteView.PresentedFrameCount;
            uint localWidth = LocalView.VideoWidth, localHeight = LocalView.VideoHeight, remoteWidth = RemoteView.VideoWidth, remoteHeight = RemoteView.VideoHeight;
            string startupTiming = Model.TimingRows[^1].Value;
            ClosePopups();
            DisposeAccountUi();
            try { await Model.StopAsync(); await virtualCameraOutput.DisposeAsync(); } catch (Exception failure) { passed = false; error ??= failure.Message; }
            var report = new { mode, passed, referenceUpdatePassed, pageEntryStates = pageEntryStates.Select(state => state.ToString()), camera = Model.SelectedCamera?.Name, localFrames, remoteFrames,
                localWidth, localHeight, remoteWidth, remoteHeight, startupTiming, transitions, error };
            string? output = Environment.GetEnvironmentVariable("FACENOW_SMOKE_OUTPUT");
            if (!string.IsNullOrEmpty(output)) { Directory.CreateDirectory(output); await File.WriteAllTextAsync(Path.Combine(output, mode.TrimStart('-') + ".json"), JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true })); }
            closed = true; Close(); Application.Current.Exit();
        }
    }
    private async Task SaveReferenceUploadScreenshotsAsync()
    {
        void SetFreeReference(ReferenceItem? item) => typeof(MainViewModel).GetProperty(nameof(Model.FreeReference))!.SetValue(Model, item);
        string previousMode = Model.SelectedMode;
        var thumbnail = Model.CharacterReferences.First(item => item.Thumbnail is not null).Thumbnail;
        var upload = new ReferenceItem { Name = "My reference", Mode = "charx", Thumbnail = thumbnail, IsUploading = true };
        try
        {
            Model.SelectedMode = "charx"; Model.CharacterReferences.Insert(1, upload);
            await SaveScreenshotAsync("reference-upload-preparing", ReferenceTiles[upload]);
            upload.UploadProgress = .47;
            await SaveScreenshotAsync("reference-uploading", ReferenceTiles[upload]);
            upload.IsUploading = false;
            await SaveScreenshotAsync("reference-upload-complete", ReferenceTiles[upload]);
            Model.SelectedMode = "free";
            var freeReference = new ReferenceItem { Name = "My reference", Mode = "free", IsUploading = true };
            SetFreeReference(freeReference);
            // Thumbnail decoding completes after the item enters the prompt; capture that update too.
            await Task.Delay(50); freeReference.Thumbnail = thumbnail;
            freeReference.UploadProgress = .72;
            await SaveScreenshotAsync("free-reference-uploading", freePromptBox);
            freeReference.IsUploading = false;
            await SaveScreenshotAsync("free-reference-upload-complete", freePromptBox);
        }
        finally
        {
            Model.CharacterReferences.Remove(upload); SetFreeReference(null); Model.SelectedMode = previousMode;
        }
    }
    private async Task<object> VerifyTransitionAsync(bool active)
    {
        FrameworkElement target = active ? workspace : landing;
        bool animations = new global::Windows.UI.ViewManagement.UISettings().AnimationsEnabled;
        // Sample an actual animated frame; VM scheduling and thumbnail decode can delay the first tick.
        if (animations)
            await UntilAsync(() => target.Opacity > 0 && target.Opacity < 1 &&
                ((TranslateTransform)target.RenderTransform).Y > 0 && ((TranslateTransform)target.RenderTransform).Y < 14, 5);
        double opacity = target.Opacity, offset = ((TranslateTransform)target.RenderTransform).Y;
        await SaveScreenshotAsync(active ? "transition-generation" : "transition-landing");
        if (animations) Check(opacity > 0 && opacity < 1 && offset > 0 && offset < 14, $"Page entry is not fading and moving (opacity={opacity}, offset={offset}).");
        await Task.Delay(500);
        Check(target.Opacity == 1 && ((TranslateTransform)target.RenderTransform).Y == 0, "Page entry did not settle.");
        return new { page = active ? "generation" : "landing", sampledOpacity = opacity, sampledOffset = offset, durationMilliseconds = 450, offsetDip = 14, settled = true };
    }
    private async Task VerifyFramesAsync()
    {
        using var client = new XmaxClient(); await using var realtime = client.CreateRealtime();
        using var sink = await realtime.BindExternalAsync(new(16, 8));
        Model.StatisticsVisible = false;
        LocalView.Width = 160; LocalView.Height = 80; LocalView.VideoSource = realtime.LocalVideo;
        byte[] pixels = new byte[64 * 8];
        for (int y = 0; y < 8; ++y) for (int x = 0; x < 16; ++x) { int i = y * 64 + x * 4; pixels[i + (x < 8 ? 2 : 0)] = 255; pixels[i + 3] = 255; }
        sink.PushBgra(pixels, 64, 1000); await UntilAsync(() => LocalView.PresentedFrameCount >= 1); await Task.Delay(100);
        await VerifyFramePixelsAsync(false); await SaveScreenshotAsync("render-bgra", LocalView);
        await realtime.SetVideoMirrorAsync(new(true, false, false)); sink.PushBgra(pixels, 64, 2000);
        await UntilAsync(() => LocalView.PresentedFrameCount >= 2); await Task.Delay(100); await VerifyFramePixelsAsync(true); await SaveScreenshotAsync("render-mirrored", LocalView);
        await Task.Run(() => { for (int i = 3; i <= 100; ++i) sink.PushBgra(pixels, 64, i * 1000); });
        await UntilAsync(() => LocalView.LastPresentedTimestampMicroseconds == 100000);
        localPanel.Children.Remove(LocalView); await Task.Delay(50); localPanel.Children.Insert(0, LocalView);
        sink.PushBgra(pixels, 64, 101000); await UntilAsync(() => LocalView.LastPresentedTimestampMicroseconds == 101000);
        LocalView.VideoSource = null;
    }
    private async Task VerifyFramePixelsAsync(bool mirrored)
    {
        var bitmap = new RenderTargetBitmap(); await bitmap.RenderAsync(LocalView, 160, 80);
        using var reader = DataReader.FromBuffer(await bitmap.GetPixelsAsync()); byte[] bytes = new byte[reader.UnconsumedBufferLength]; reader.ReadBytes(bytes);
        int left = (bitmap.PixelHeight / 2 * bitmap.PixelWidth + bitmap.PixelWidth / 8) * 4;
        int right = (bitmap.PixelHeight / 2 * bitmap.PixelWidth + bitmap.PixelWidth * 7 / 8) * 4;
        Check(bytes[left + (mirrored ? 0 : 2)] > 200 && bytes[right + (mirrored ? 2 : 0)] > 200, "WinUI displayed pixels or mirror metadata differ from the input.");
    }
}
