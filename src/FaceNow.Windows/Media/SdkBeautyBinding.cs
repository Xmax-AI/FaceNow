//
//  SdkBeautyBinding.cs
//  FaceNow
//

using System.Threading.Channels;
using FaceNow.Core.Media;
using Xmax.SDK;

namespace FaceNow.Windows.Media;

/// <summary>Maps saved UI preferences to SDK configuration; all pixel processing belongs to XmaxSDK.</summary>
internal sealed class SdkBeautyBinding : IAsyncDisposable
{
    private readonly GenerationEffectsController settings;
    private readonly Func<RealtimeVideoBeautyOptions?, Task> configure;
    private readonly Action<Exception> failed;
    private readonly CancellationTokenSource lifetime = new();
    private readonly Channel<BeautySettings> changes = Channel.CreateBounded<BeautySettings>(new BoundedChannelOptions(1)
    {
        FullMode = BoundedChannelFullMode.DropOldest,
        SingleReader = true,
        SingleWriter = false
    });
    private readonly Task worker;
    private readonly TaskCompletionSource initialApplication = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private BeautySettings? requested;
    private int closed, sourceDisposed;

    internal Task Ready => initialApplication.Task;

    internal SdkBeautyBinding(
        GenerationEffectsController settings,
        Func<RealtimeVideoBeautyOptions?, Task> configure,
        Action<Exception> failed
    )
    {
        this.settings = settings;
        this.configure = configure;
        this.failed = failed;
        settings.Changed += Changed;
        worker = Task.Run(ApplyChangesAsync);
        Changed();
    }

    internal static async Task<SdkBeautyBinding> StartAsync(
        IXmaxRealtimeManaging realtime,
        GenerationEffectsController settings,
        Action<Exception> failed
    )
    {
        var binding = new SdkBeautyBinding(settings, realtime.SetRemoteVideoBeautyAsync, failed);
        try
        {
            await realtime.SetRemoteVideoBeautyErrorListenerAsync(error => binding.Fallback(error));
            await binding.Ready;
            return binding;
        }
        catch
        {
            await binding.DisposeAsync();
            throw;
        }
    }

    private void Changed()
    {
        var desired = settings.Settings;
        if (Volatile.Read(ref closed) != 0 || desired == Volatile.Read(ref requested))
            return;
        Volatile.Write(ref requested, desired);
        changes.Writer.TryWrite(desired);
    }

    private async Task ApplyChangesAsync()
    {
        try
        {
            await foreach (var initial in changes.Reader.ReadAllAsync(lifetime.Token))
            {
                // Slider changes coalesce; never initialize several native graphs while dragging.
                await Task.Delay(120, lifetime.Token);
                var desired = initial;
                while (changes.Reader.TryRead(out var latest))
                    desired = latest;
                desired = settings.Settings;
                if (Volatile.Read(ref closed) != 0)
                    return;
                try
                {
                    await configure(desired.Enabled ? new(
                        desired.Smoothness,
                        desired.Lightening,
                        desired.Sharpness,
                        desired.Redness
                    ) : null);
                    if (Volatile.Read(ref closed) == 0 && desired == settings.Settings)
                        settings.MarkApplied(desired);
                }
                catch (Exception error)
                {
                    if (Volatile.Read(ref closed) != 0 || desired != settings.Settings)
                        continue;
                    // Closing/replacing a session cancels SDK admission; it is not an effect failure.
                    if (error is ObjectDisposedException or OperationCanceledException or XmaxException { Code: XmaxErrorCode.InvalidState or XmaxErrorCode.Cancelled })
                        continue;
                    // A configuration failure is recoverable just like a later SDK frame failure.
                    try
                    {
                        await configure(null);
                    }
                    catch { }
                    Fallback(error);
                }
                finally
                {
                    initialApplication.TrySetResult();
                }
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
    }

    private void Fallback(
        Exception error
    )
    {
        if (Volatile.Read(ref closed) != 0)
            return;
        var current = settings.Settings;
        if (!current.Enabled)
            return;
        settings.Update(current with
        {
            Enabled = false
        });
        failed(error);
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref closed, 1) == 0)
        {
            settings.Changed -= Changed;
            lifetime.Cancel();
            changes.Writer.TryComplete();
        }
        await worker;
        initialApplication.TrySetCanceled();
        if (Interlocked.Exchange(ref sourceDisposed, 1) == 0)
            lifetime.Dispose();
    }
}
