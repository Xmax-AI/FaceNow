//
//  Program.cs
//  FaceNow
//

using FaceNow.Core.Media;
using FaceNow.Core.Product;
using FaceNow.Core.Localization;
using FaceNow.Windows.Media;
using FaceNow.Windows.VirtualCamera;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Xmax.SDK;

int passed = 0;
void Check(bool value, string label) { if (!value) throw new Exception(label); ++passed; Console.WriteLine("PASS " + label); }
var domestic = new ProductProfile(ProductEdition.Domestic); var overseas = new ProductProfile(ProductEdition.Overseas);
Check(domestic.ApiOrigin.Host == "cloud.xmax.22duck.cn" && overseas.ApiOrigin.Host == "api.xmax.cloud", "Regional API endpoints");
Check(domestic.CredentialPrefix != overseas.CredentialPrefix && domestic.DataDirectory != overseas.DataDirectory && domestic.RegistryPath != overseas.RegistryPath, "Credentials, settings and caches isolated");
Check(AppText.GetFor("Start Camera", domestic) == "启动摄像头" && AppText.GetFor("Start Camera", overseas) == "Start Camera", "Explicit Chinese and English resources");
Check(overseas.ResolveLink("https://platform.xmaxsi.com/credits") == "https://platform.xmax.ai/credits" && domestic.ResolveLink("https://platform.xmax.ai/usage") == "https://platform.xmaxai.com/usage", "All browser links follow edition");
Check(overseas.ResolveAsset("https://cdn.22duck.cn/test.jpg") == "https://cdn.xmax.ai/test.jpg", "Regional preset assets");
Check(GenerationPrompts.ForMode("charx", overseas) == "Become the character in the reference image" && GenerationPrompts.ForMode("vibex", domestic).StartsWith("参考图角色"), "Generation modes have regional default prompts");
var defaultBeauty = new BeautySettings();
defaultBeauty.Validate();
Check(defaultBeauty == new BeautySettings(false, 0, 0, 0, 0), "Beauty is off with zero default strengths");
try { new BeautySettings(true, float.NaN).Validate(); throw new Exception("NaN accepted"); } catch (ArgumentOutOfRangeException) { Check(true, "Invalid beauty strengths rejected"); }

var timing = new MeetingOutputTiming(0);
long arrival = Stopwatch.GetTimestamp();
var (videoTime, startsStream) = timing.Map(1, 900d, arrival);
var (audioTime, _) = timing.Map(1, 900.025, arrival + MeetingOutputTiming.Ticks(70));
Check(startsStream && audioTime - videoTime == MeetingOutputTiming.Ticks(25) && timing.Delay(true) == timing.Delay(false),
    "Audio and video share SDK presentation time even when callbacks arrive at different times");
var (newTime, newStream) = timing.Map(2, 12d, arrival);
Check(newStream && newTime == videoTime, "A replacement stream starts a new output timeline");
timing.SetOffset(200);
Check(timing.Delay(true) == MeetingOutputTiming.Ticks(200) && timing.Delay(false) == 0, "Positive offset delays audio alone");
timing.SetOffset(-5000);
Check(timing.Delay(false) == MeetingOutputTiming.Ticks(5000) && timing.Delay(true) == 0, "Negative offset delays video alone");

var delayedVideo = new MeetingOutputQueue<TestPacket>(timing, audio: false);
var retained = new List<TestPacket>();
for (int i = 0; i <= 150; i++)
{
    var packet = new TestPacket();
    if (delayedVideo.TryWrite(packet, arrival + MeetingOutputTiming.Ticks(i * 33), 1920 * 1080 * 4, i == 0)) retained.Add(packet);
    else packet.Dispose();
}
Check(retained.Count is > 1 and <= 32 && retained.All(packet => !packet.Disposed),
    "A five-second video delay retains a bounded set without evicting the earliest frame before it is due");
delayedVideo.Reset();
Check(retained.All(packet => packet.Disposed), "Clearing delayed output releases every retained frame");
delayedVideo.Complete();

timing.SetOffset(5000);
var delayedAudio = new MeetingOutputQueue<TestPacket>(timing, audio: true);
using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
using var scheduledAudio = new TestPacket();
long due = Stopwatch.GetTimestamp() + MeetingOutputTiming.Ticks(100);
Check(delayedAudio.TryWrite(scheduledAudio, due, 0, false), "Audio is admitted during a live offset");
var reading = delayedAudio.ReadAsync(timeout.Token).AsTask();
Check(!reading.IsCompleted, "Audio waits for its scheduled time");
timing.SetOffset(0);
delayedAudio.OffsetChanged();
var played = await reading;
Check(played?.Packet == scheduledAudio && Stopwatch.GetTimestamp() >= due, "Reset reschedules pending audio and wakes its worker");
delayedAudio.Complete();

if (args.Length > 0)
{
    if (args.Length > 1) Check(ProductProfile.Current.Edition.ToString() == args[1], "Compiled edition matches requested artifact");
    NativeLibrary.Load(Path.Combine(args[0], "FaceNow.FrameEffects.dll"));
    using (var raw = new ResultFrame(320, 180, 321, Guid.NewGuid()))
    {
        raw.Pixels.Span.Fill(80);
        using var canvas = new FrameCompositor(640, 360).Compose(raw);
        Check(canvas.Width == 640 && canvas.Height == 360 && canvas.Pixels.Span[(180 * 640 + 320) * 4] == 80, "Output canvas fills without stretching or changing center pixels");
        byte[] cn = WatermarkRasterizer.Create(640, 360, "AI 生成"), en = WatermarkRasterizer.Create(640, 360, "AI Generation");
        Check(cn.Where((v, i) => i % 4 == 3).Any(v => v > 0) && !cn.SequenceEqual(en), "Chinese and English artwork rasterized into output pixels");
        Check(canvas.Pixels.Span[..(640 * 70 * 4)].ToArray().Any(v => v != 80), "Readable watermark survives final canvas composition");
        Check(raw.Pixels.Span.ToArray().All(v => v == 80), "Watermark composition does not mutate the result source");
    }
    foreach (var (width, height) in new[] { (90, 160), (100, 100), (90, 120), (120, 90) })
    {
        using var raw = new ResultFrame(width, height, 321, Guid.NewGuid());
        raw.Pixels.Span.Fill(80);
        raw.Pixels.Span[..raw.Stride].Fill(50);
        raw.Pixels.Span[^raw.Stride..].Fill(90);
        using var canvas = new FrameCompositor(width * 4, height * 4).Compose(raw);
        var centerRow = canvas.Pixels.Span.Slice(canvas.Height / 2 * canvas.Stride, canvas.Stride);
        int center = canvas.Width / 2 * 4;
        Check(canvas.Width == width * 4 && canvas.Height == height * 4 &&
            centerRow[0] == 80 && centerRow[^4] == 80 &&
            canvas.Pixels.Span[center] == 50 &&
            canvas.Pixels.Span[(canvas.Height - 1) * canvas.Stride + center] == 90,
            $"{width}×{height} fills the selected output aspect with all edges intact");
    }
    using (var raw = new ResultFrame(160, 90, 321, Guid.NewGuid()))
    {
        raw.Pixels.Span.Fill(80);
        using var canvas = new FrameCompositor(180, 320).Compose(raw);
        var row = canvas.Pixels.Span.Slice(canvas.Height / 2 * canvas.Stride, canvas.Stride);
        Check(row[0] == 80 && row[^4] == 80, "A differently shaped result fills the portrait canvas without bars");
    }
    string settingsPath = Path.Combine(Path.GetTempPath(), "FaceNow-effects-" + Guid.NewGuid().ToString("N"), "beauty.json");
    var settings = new GenerationEffectsController(settingsPath); int failures = 0;
    var configured = new System.Collections.Concurrent.ConcurrentQueue<RealtimeVideoBeautyOptions?>();
    await using (var binding = new SdkBeautyBinding(settings, options => {
        configured.Enqueue(options); return Task.CompletedTask;
    }, _ => failures++)) {
        await binding.Ready.WaitAsync(TimeSpan.FromSeconds(5));
        Check(configured.TryPeek(out var defaults) && defaults is null, "A fresh session starts with SDK beauty disabled");
        for (int i = 1; i <= 20; i++) settings.Update(new(true, i / 20f, .3f));
        await WaitUntil(() => !settings.IsApplying);
        Check(configured.Last() == new RealtimeVideoBeautyOptions(1, .3f) && configured.Count <= 3, "Slider changes coalesce into SDK configuration");
        settings.Update(new(false, 1, .3f)); await WaitUntil(() => configured.Last() is null);
        Check(configured.Last() is null, "Disabling beauty passes null to the SDK");
    }
    int calls = 0; settings.Update(new(true));
    await using (var binding = new SdkBeautyBinding(settings, options => {
        Interlocked.Increment(ref calls);
        return options is null ? Task.CompletedTask : Task.FromException(new IOException("Synthetic SDK configuration failure"));
    }, _ => Interlocked.Increment(ref failures))) {
        await WaitUntil(() => !settings.Settings.Enabled && failures == 1);
        await Task.Delay(250);
        Check(failures == 1 && calls <= 3, "SDK configuration failure disables only beauty without repeated retries");
    }
    settings.Update(new(true, .7f, .2f));
    int stopFailures = 0;
    await using (var binding = new SdkBeautyBinding(settings, options => {
        return Task.FromException(new ObjectDisposedException("Closed SDK session"));
    }, _ => stopFailures++)) {
        await binding.Ready.WaitAsync(TimeSpan.FromSeconds(5));
    }
    Check(settings.Settings.Enabled && settings.Settings.Smoothness == .7f && stopFailures == 0,
        "Closing a session preserves saved beauty preferences without a failure notice");
    await settings.FlushAsync();
    Check(new GenerationEffectsController(settingsPath).Settings == settings.Settings, "Only the latest beauty settings survive persistence");
    Directory.Delete(Path.GetDirectoryName(settingsPath)!, true);
    string leasePath = Path.Combine(Path.GetTempPath(), "FaceNow-producer-" + Guid.NewGuid().ToString("N"));
    using (var lease = CameraProducerLease.Acquire(leasePath))
    {
        try { using var competing = CameraProducerLease.Acquire(leasePath); throw new Exception("Concurrent producer allowed"); }
        catch (InvalidOperationException) { Check(true, "Regional apps cannot concurrently publish to their shared camera"); }
    }
    using (var recovered = CameraProducerLease.Acquire(leasePath)) Check(true, "Producer lease recovers after its owner exits");
    Directory.Delete(leasePath, true);

}
Console.WriteLine($"{passed} media/edition checks passed; no account, camera or cloud session used.");

static async Task WaitUntil(Func<bool> ready) {
    var deadline = DateTime.UtcNow.AddSeconds(5);
    while (!ready()) { if (DateTime.UtcNow >= deadline) throw new TimeoutException("SDK preference binding timed out"); await Task.Delay(10); }
}

sealed class TestPacket : IDisposable
{
    internal bool Disposed { get; private set; }
    public void Dispose() => Disposed = true;
}
