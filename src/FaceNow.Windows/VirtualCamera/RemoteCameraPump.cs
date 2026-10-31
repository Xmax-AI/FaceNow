using System.Buffers;
using System.Runtime.InteropServices;
using System.Threading.Channels;
using FaceNow.Core.VirtualCamera;
using FaceNow.Core.Media;
using FaceNow.Windows.Media;
using Xmax.SDK;

namespace FaceNow.Windows.VirtualCamera;

/// <summary>One bounded result pipeline processes beauty once and fans out owned frames to independent consumers.</summary>
internal sealed class RemoteCameraPump : IAsyncDisposable
{
    private readonly IVirtualCameraOutput? output;
    private readonly Guid sessionId = Guid.NewGuid();
    private readonly Action<Exception> faulted;
    private readonly CancellationTokenSource lifetime = new();
    private readonly FrameCompositor compositor = new();
    private readonly ResultEffectsProcessor processor;
    private readonly Channel<XmaxMediaFrame> frames = Channel.CreateBounded<XmaxMediaFrame>(new BoundedChannelOptions(1)
        { FullMode = BoundedChannelFullMode.DropOldest, SingleReader = true, SingleWriter = false }, frame => frame.Dispose());
    private readonly Task worker;
    private int stopped, outputEnabled;
    internal ResultFrameSource Preview { get; } = new();
    internal bool IsStopped => Volatile.Read(ref stopped) != 0;
    internal Guid SessionId => sessionId;
    private RemoteCameraPump(IVirtualCameraOutput? output, Action<Exception> faulted, GenerationEffectsController? effects, Action<Exception>? beautyFailed)
    { this.output = output; this.faulted = faulted; processor = new(effects, beautyFailed); worker = Task.Run(ConsumeAsync); }
    internal static async Task<RemoteCameraPump> StartAsync(XmaxRealtime realtime, IVirtualCameraOutput? output, Action<Exception> faulted,
        GenerationEffectsController? effects = null, Action<Exception>? beautyFailed = null, bool enableOutput = true)
    {
        var pump = new RemoteCameraPump(output, faulted, effects, beautyFailed);
        try { await realtime.SetRemoteMediaListenerAsync(pump.Receive); if (enableOutput) await pump.EnableOutputAsync(); return pump; }
        catch { await pump.DisposeAsync(); throw; }
    }
    internal async Task EnableOutputAsync()
    {
        if (output is null || Volatile.Read(ref outputEnabled) != 0 || IsStopped) return;
        await output.StartAsync(new(1920, 1080, 30, sessionId), lifetime.Token);
        if (IsStopped) { await output.StopAsync(); return; }
        Volatile.Write(ref outputEnabled, 1);
    }
    internal async Task DisableOutputAsync()
    { Interlocked.Exchange(ref outputEnabled, 0); if (output is not null) await output.StopAsync(); }
    private void Receive(XmaxMediaFrame packet)
    { if (packet.Type != MediaType.Video || IsStopped || !frames.Writer.TryWrite(packet)) packet.Dispose(); }
    private async Task ConsumeAsync()
    {
        try
        {
            await foreach (var packet in frames.Reader.ReadAllAsync(lifetime.Token))
            using (packet)
            {
                if (IsStopped) continue;
                int width = checked((int)packet.VideoWidth), height = checked((int)packet.VideoHeight);
                long timestamp = packet.PresentationTime.Seconds is { } seconds && double.IsFinite(seconds) ? checked((long)(seconds * 1_000_000)) : 0;
                using var raw = new ResultFrame(width, height, timestamp, sessionId);
                packet.ReadBgra((pointer, stride, size) => CopyPixels(raw, pointer, stride, size));
                using var result = await processor.ProcessAsync(raw, lifetime.Token);
                if (result is null || IsStopped) continue;
                Preview.Publish(result);
                if (Volatile.Read(ref outputEnabled) != 0 && output is not null)
                {
                    try
                    {
                        using var canvas = compositor.Compose(result);
                        output.TrySubmit(new(canvas.Pixels, canvas.Width, canvas.Height, canvas.Stride, canvas.TimestampMicroseconds, sessionId));
                    }
                    catch (Exception failure) { await DisableOutputAsync(); if (!IsStopped) faulted(failure); }
                }
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
        catch (Exception failure) { if (!IsStopped) faulted(failure); }
        finally
        {
            while (frames.Reader.TryRead(out var remaining)) remaining.Dispose();
            await processor.DisposeAsync();
        }
    }
    private static unsafe void CopyPixels(ResultFrame frame, nint pointer, int stride, int size)
    {
        if (pointer == 0 || stride < frame.Stride || stride > 32768 || size < (long)stride * frame.Height) throw new InvalidDataException("Invalid SDK result pixels.");
        var target = frame.Pixels.Span;
        for (int y = 0; y < frame.Height; ++y) new ReadOnlySpan<byte>((byte*)pointer + y * stride, frame.Stride).CopyTo(target.Slice(y * frame.Stride, frame.Stride));
    }
    // The same adapter is used by the no-cloud end-to-end verification.
    internal static bool SubmitBgra(IVirtualCameraOutput output, nint pointer, int size, int width, int height, int stride, long timestamp, Guid sessionId)
    {
        if (width is < 1 or > 4096 || height is < 1 or > 2160 || stride < width * 4 || stride > 32768 ||
            (long)stride * height > 64 * 1024 * 1024 || size < (long)stride * height || pointer == 0)
            throw new InvalidDataException("The SDK video frame has an invalid BGRA layout.");
        int length = stride * height;
        byte[] pixels = ArrayPool<byte>.Shared.Rent(length);
        try { Marshal.Copy(pointer, pixels, 0, length); return output.TrySubmit(new(pixels.AsMemory(0, length), width, height, stride, timestamp, sessionId)); }
        finally { ArrayPool<byte>.Shared.Return(pixels); }
    }
    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref stopped, 1) != 0) { await worker; return; }
        lifetime.Cancel(); frames.Writer.TryComplete();
        try { await DisableOutputAsync(); }
        finally { await worker; Preview.Dispose(); lifetime.Dispose(); }
    }
}
