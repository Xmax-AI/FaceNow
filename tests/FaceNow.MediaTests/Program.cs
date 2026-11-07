//
//  Program.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using FaceNow.Core.Media;
using FaceNow.Core.Product;
using FaceNow.Core.Localization;
using FaceNow.Windows.Media;
using FaceNow.Windows.VirtualCamera;
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
new BeautySettings().Validate();
Check(new BeautySettings().Enabled && new BeautySettings().Smoothness == 0 && new BeautySettings().Lightening == 0 && new BeautySettings().Sharpness == 0, "Beauty is enabled with zero default strengths");
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
        Check(canvas.Pixels.Span[..(640 * 70 * 4)].ToArray().Any(v => v != 80), "Readable watermark survives final canvas composition");
        Check(raw.Pixels.Span.ToArray().All(v => v == 80), "Watermark composition does not mutate the result source");
    }
    foreach (var (width, height, fittedWidth) in new[] { (90, 160, 203), (100, 100, 360), (90, 120, 270), (120, 90, 480) })
    {
        using var raw = new ResultFrame(width, height, 321, Guid.NewGuid());
        raw.Pixels.Span.Fill(80);
        raw.Pixels.Span[..raw.Stride].Fill(50);
        raw.Pixels.Span[^raw.Stride..].Fill(90);
        using var canvas = new FrameCompositor(640, 360).Compose(raw);
        int left = (640 - fittedWidth) / 2;
        var centerRow = canvas.Pixels.Span.Slice(180 * canvas.Stride, canvas.Stride);
        Check(centerRow.Slice((left - 1) * 4, 4).SequenceEqual(new byte[] { 0, 0, 0, 255 }) &&
            centerRow[left * 4] == 80 && centerRow[(left + fittedWidth - 1) * 4] == 80 &&
            centerRow.Slice((left + fittedWidth) * 4, 4).SequenceEqual(new byte[] { 0, 0, 0, 255 }) &&
            canvas.Pixels.Span[320 * 4] == 50 && canvas.Pixels.Span[359 * canvas.Stride + 320 * 4] == 90,
            $"{width}×{height} fits the widescreen output with opaque black bars and both frame edges intact");
    }
    string settingsPath = Path.Combine(Path.GetTempPath(), "FaceNow-effects-" + Guid.NewGuid().ToString("N"), "beauty.json");
    var settings = new GenerationEffectsController(settingsPath); int failures = 0;
    var configured = new System.Collections.Concurrent.ConcurrentQueue<RealtimeVideoBeautyOptions?>();
    await using (var binding = new SdkBeautyBinding(settings, options => {
        configured.Enqueue(options); return Task.CompletedTask;
    }, _ => failures++)) {
        await WaitUntil(() => !settings.IsApplying);
        Check(configured.TryPeek(out var defaults) && defaults == new RealtimeVideoBeautyOptions(), "UI defaults map to the default SDK options");
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
