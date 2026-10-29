using System.Buffers;
using System.Runtime.InteropServices;
using System.Threading.Channels;
using FaceNow.Core.VirtualCamera;
using Xmax.SDK;

namespace FaceNow.Windows.VirtualCamera;

/// <summary>Owns retained SDK packets; never consumes the preview's RemoteVideo mailbox.</summary>
internal sealed class RemoteCameraPump : IAsyncDisposable
{
    private readonly IVirtualCameraOutput output;
    private readonly Guid sessionId;
    private readonly Action<Exception> faulted;
    private readonly Channel<XmaxMediaFrame> frames = Channel.CreateBounded<XmaxMediaFrame>(new BoundedChannelOptions(1)
        { FullMode = BoundedChannelFullMode.DropOldest, SingleReader = true, SingleWriter = false }, frame => frame.Dispose());
    private readonly Task worker;
    private int stopped;
    private long receivedFrames;
    internal bool IsStopped => Volatile.Read(ref stopped) != 0;
    internal Guid SessionId => sessionId;

    private RemoteCameraPump(IVirtualCameraOutput output, Guid sessionId, Action<Exception> faulted)
    { this.output = output; this.sessionId = sessionId; this.faulted = faulted; worker = Task.Run(ConsumeAsync); }

    internal static async Task<RemoteCameraPump> StartAsync(XmaxRealtime realtime, IVirtualCameraOutput output, Action<Exception> faulted)
    {
        var identity = Guid.NewGuid();
        await output.StartAsync(new(1920, 1080, 30, identity));
        var pump = new RemoteCameraPump(output, identity, faulted);
        try { await realtime.SetRemoteMediaListenerAsync(pump.Receive); return pump; }
        catch { await pump.DisposeAsync(); throw; }
    }
    private void Receive(XmaxMediaFrame packet)
    {
        if (packet.Type == MediaType.Video && Interlocked.Increment(ref receivedFrames) == 1)
            CameraDiagnostics.Write($"First SDK result frame received; {packet.VideoWidth}x{packet.VideoHeight}");
        if (packet.Type != MediaType.Video || Volatile.Read(ref stopped) != 0 || !frames.Writer.TryWrite(packet)) packet.Dispose();
    }
    private async Task ConsumeAsync()
    {
        try
        {
            await foreach (var packet in frames.Reader.ReadAllAsync())
            using (packet)
            {
                if (Volatile.Read(ref stopped) != 0) continue;
                int width = checked((int)packet.VideoWidth), height = checked((int)packet.VideoHeight);
                long timestamp = packet.PresentationTime.Seconds is { } seconds && double.IsFinite(seconds)
                    ? checked((long)(seconds * 1_000_000)) : 0;
                packet.ReadBgra((pointer, stride, size) => SubmitBgra(output, pointer, size, width, height, stride, timestamp, sessionId));
            }
        }
        catch (Exception error)
        {
            CameraDiagnostics.Error("SDK result adapter failed", error);
            Interlocked.Exchange(ref stopped, 1); frames.Writer.TryComplete();
            await output.StopAsync();
            faulted(error);
        }
        finally { while (frames.Reader.TryRead(out var remaining)) remaining.Dispose(); }
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
        Interlocked.Exchange(ref stopped, 1);
        frames.Writer.TryComplete();
        // Clear IPC immediately, then let a packet already being read finish and be rejected.
        await output.StopAsync();
        await worker;
        // Native session disposal releases the listener. Late callbacks still own/dispose packets.
    }
}
