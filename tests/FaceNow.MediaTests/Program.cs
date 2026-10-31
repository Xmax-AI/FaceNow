using FaceNow.Core.Media;
using FaceNow.Core.Product;
using FaceNow.Core.Localization;
using FaceNow.Windows.Media;
using FaceNow.Windows.VirtualCamera;
using System.Runtime.InteropServices;

int passed = 0;
void Check(bool value, string label) { if (!value) throw new Exception(label); ++passed; Console.WriteLine("PASS " + label); }
var domestic = new ProductProfile(ProductEdition.Domestic); var overseas = new ProductProfile(ProductEdition.Overseas);
Check(domestic.ApiOrigin.Host == "cloud.xmax.22duck.cn" && overseas.ApiOrigin.Host == "api.xmax.cloud", "Regional API endpoints");
Check(domestic.CredentialPrefix != overseas.CredentialPrefix && domestic.DataDirectory != overseas.DataDirectory && domestic.RegistryPath != overseas.RegistryPath, "Credentials, settings and caches isolated");
Check(AppText.GetFor("Start Camera", domestic) == "启动摄像头" && AppText.GetFor("Start Camera", overseas) == "Start Camera", "Explicit Chinese and English resources");
Check(overseas.ResolveLink("https://platform.xmaxsi.com/credits") == "https://platform.xmax.ai/credits" && domestic.ResolveLink("https://platform.xmax.ai/usage") == "https://platform.xmaxai.com/usage", "All browser links follow edition");
Check(overseas.ResolveAsset("https://cdn.22duck.cn/test.jpg") == "https://cdn.xmax.ai/test.jpg", "Regional preset assets");
Check(GenerationPrompts.ForMode("charx", overseas) == "Become the character in the reference image" && GenerationPrompts.ForMode("vibex", domestic).StartsWith("参考图角色"), "Generation prompts follow the macOS regional defaults");
using (var mailbox = new ResultFrameSource())
{
    using var frame = new ResultFrame(4, 4, 123, Guid.NewGuid()); frame.Pixels.Span.Fill(77);
    mailbox.Publish(frame); using var consumer = mailbox.TryAcquireFrame();
    Check(consumer is not null && consumer.Pixels.Span[0] == 77 && consumer.TimestampMicroseconds == 123, "Independent owned preview lease");
    mailbox.Publish(frame); mailbox.Publish(frame); using var latest = mailbox.TryAcquireFrame(); Check(latest is not null && mailbox.TryAcquireFrame() is null, "Latest-frame bounded mailbox");
}
new BeautySettings().Validate();
Check(!new BeautySettings().Enabled && new BeautySettings().Smoothness == .5f && new BeautySettings().Lightening == .5f && new BeautySettings().Sharpness == 0, "macOS beauty defaults");
try { new BeautySettings(true, float.NaN).Validate(); throw new Exception("NaN accepted"); } catch (ArgumentOutOfRangeException) { Check(true, "Invalid beauty strengths rejected"); }
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
        Check(canvas.Pixels.Span[..(640 * 70 * 4)].ToArray().Any(v => v != 80), "Readable watermark survives final canvas crop");
        Check(raw.Pixels.Span.ToArray().All(v => v == 80), "Watermark composition does not mutate the result source");
    }
    string settingsPath = Path.Combine(Path.GetTempPath(), "FaceNow-effects-" + Guid.NewGuid().ToString("N"), "beauty.json");
    var settings = new GenerationEffectsController(settingsPath); settings.Update(new(true)); int failures = 0;
    await using (var effect = new ResultEffectsProcessor(settings, _ => failures++, () => new FailingProcessor()))
    using (var raw = new ResultFrame(4, 4, 444, Guid.NewGuid()))
    {
        raw.Pixels.Span.Fill(33); using var fallback = await effect.ProcessAsync(raw, default);
        Check(fallback is not null && fallback.Pixels.Span[0] == 33 && !settings.Settings.Enabled && failures == 1, "Beauty failure restores original pixels and disables only the effect");
        using var next = await effect.ProcessAsync(raw, default); Check(next is not null && failures == 1, "Disabled beauty does not repeatedly restart failed worker");
    }
    var controlled = new ControlledProcessor(); settings.Update(new(true));
    await using (var effect = new ResultEffectsProcessor(settings, _ => throw new Exception("Unexpected failure"), () => controlled))
    using (var raw = new ResultFrame(4, 4, 445, Guid.NewGuid()))
    {
        var pending = effect.ProcessAsync(raw, default).AsTask(); await controlled.Started.Task;
        settings.Update(new(false)); controlled.Continue.TrySetResult();
        using var stale = await pending; Check(stale is null, "An in-flight result cannot restore obsolete beauty settings");
        using var restored = await effect.ProcessAsync(raw, default); Check(restored is not null, "Disabling beauty immediately restores raw-frame delivery");
    }
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
    string worker = Path.Combine(args[0], "FaceNow.BeautyWorker.exe");
    bool fullHd = args.Length > 2 && args[2] == "1080";
    using var source = new ResultFrame(fullHd ? 1920 : 320, fullHd ? 1080 : 180, 456, Guid.NewGuid());
    byte[] input = new byte[source.Length];
    for (int i = 0; i < input.Length; i += 4) { int noise = ((i / 4) % 7 - 3) * 5; input[i] = (byte)(90 + noise); input[i + 1] = (byte)(120 + noise); input[i + 2] = (byte)(160 + noise); input[i + 3] = 255; }
    input.AsMemory().CopyTo(source.Pixels);
    await using var beauty = new BeautyWorkerClient(worker);
    using var plain = await beauty.ProcessAsync(source, new(true, 0, 0, 0, 0), default);
    var started = System.Diagnostics.Stopwatch.StartNew();
    using var strong = await beauty.ProcessAsync(source, new(true, 1, 1, 0, 0), default);
    Console.WriteLine($"Beauty {source.Width}x{source.Height} frame: {started.ElapsedMilliseconds} ms");
    Check(strong.Width == source.Width && strong.Height == source.Height && strong.TimestampMicroseconds == 456 && strong.SessionId == source.SessionId, "Actual offline worker preserves frame contract");
    double delta = 0; byte[] a = plain.Pixels.ToArray(), b = strong.Pixels.ToArray();
    for (int i = 0; i < a.Length; ++i) if (i % 4 != 3) delta += Math.Abs(a[i] - b[i]);
    delta /= source.Width * source.Height * 3;
    Console.WriteLine("Beauty mean pixel difference: " + delta);
    Check(delta > 1, "ClearVision actually changes output pixels");
    Check(source.Pixels.Span.SequenceEqual(input), "Camera input and raw result remain unchanged");
}
Console.WriteLine($"{passed} media/edition checks passed; no account, camera or cloud session used.");

sealed class FailingProcessor : IResultBeautyProcessor
{
    public ValueTask<ResultFrame> ProcessAsync(ResultFrame frame, BeautySettings settings, CancellationToken token) => throw new IOException("Synthetic helper failure");
    public ValueTask DisposeAsync() => throw new IOException("Synthetic helper cleanup failure");
}

sealed class ControlledProcessor : IResultBeautyProcessor
{
    internal TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously), Continue = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public async ValueTask<ResultFrame> ProcessAsync(ResultFrame frame, BeautySettings settings, CancellationToken token)
    { Started.TrySetResult(); await Continue.Task.WaitAsync(token); return frame.Retain(); }
    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
