using FaceNow.Core.Media;

namespace FaceNow.Windows.Media;

/// <summary>A recoverable effect stage shared by every result consumer; failures restore the original frame.</summary>
internal sealed class ResultEffectsProcessor(GenerationEffectsController? settings, Action<Exception>? failed,
    Func<IResultBeautyProcessor>? factory = null) : IAsyncDisposable
{
    private IResultBeautyProcessor? processor;
    public async ValueTask<ResultFrame?> ProcessAsync(ResultFrame frame, CancellationToken token)
    {
        var desired = settings?.Settings;
        if (desired?.Enabled != true)
        {
            await ReleaseAsync();
            return frame.Retain();
        }
        try
        {
            processor ??= factory?.Invoke() ?? new BeautyWorkerClient();
            var result = await processor.ProcessAsync(frame, desired, token);
            if (desired != settings!.Settings || token.IsCancellationRequested) { result.Dispose(); return null; }
            settings.MarkApplied(desired); return result;
        }
        catch (Exception) when (token.IsCancellationRequested) { return null; }
        catch (Exception failure)
        {
            await ReleaseAsync();
            if (desired == settings!.Settings) { settings.Update(desired with { Enabled = false }); failed?.Invoke(failure); }
            return frame.Retain();
        }
    }
    private async ValueTask ReleaseAsync()
    {
        var previous = processor; processor = null;
        if (previous is null) return;
        try { await previous.DisposeAsync(); }
        catch (Exception error) { System.Diagnostics.Debug.WriteLine("Beauty cleanup: " + error.GetType().Name); }
    }
    public ValueTask DisposeAsync() => ReleaseAsync();
}
