//
//  RemoteCameraPump.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using System.Buffers;
using System.Runtime.InteropServices;
using System.Diagnostics;
using FaceNow.Core.VirtualCamera;
using FaceNow.Core.Media;
using FaceNow.Windows.Media;
using FaceNow.Windows.VirtualMicrophone;
using Xmax.SDK;

namespace FaceNow.Windows.VirtualCamera;

/// <summary>Writes SDK-processed result frames to branded virtual-camera output.</summary>
internal sealed class RemoteCameraPump : IAsyncDisposable
{
    private readonly IVirtualCameraOutput? output;
    private readonly Guid sessionId = Guid.NewGuid();
    private readonly Action<Exception> faulted;
    private readonly CancellationTokenSource lifetime = new();
    private readonly FrameCompositor compositor;
    private readonly OutputFormat format;
    private readonly RemoteMicrophonePump? microphone;
    private SdkBeautyBinding? beauty;
    private readonly object ingress = new();
    private readonly MeetingOutputTiming timing;
    private readonly MeetingOutputQueue<RealtimeVideoFrame> frames;
    private readonly Task worker;
    private int stopped, outputEnabled;

    internal bool IsStopped => Volatile.Read(ref stopped) != 0;

    internal Guid SessionId => sessionId;

    private RemoteCameraPump(
        IVirtualCameraOutput? output,
        RealtimeVideoFormat videoFormat,
        Action<Exception> faulted,
        Action<Exception>? microphoneFaulted,
        int audioSyncOffset
    )
    {
        this.output = output;
        this.faulted = faulted;
        format = new(checked((int)videoFormat.Width), checked((int)videoFormat.Height), 30, sessionId);
        compositor = new(format.Width, format.Height);
        timing = new(audioSyncOffset);
        frames = new(timing, audio: false);
        if (microphoneFaulted is not null)
            microphone = new(timing, microphoneFaulted);
        worker = Task.Run(ConsumeAsync);
    }

    internal static async Task<RemoteCameraPump> StartAsync(
        IXmaxRealtimeManaging realtime,
        IVirtualCameraOutput? output,
        RealtimeVideoFormat videoFormat,
        Action<Exception> faulted,
        GenerationEffectsController? effects = null,
        Action<Exception>? beautyFailed = null,
        bool enableOutput = true,
        Action<Exception>? microphoneFaulted = null,
        int audioSyncOffset = 0
    )
    {
        var pump = new RemoteCameraPump(output, videoFormat, faulted, microphoneFaulted, audioSyncOffset);
        try
        {
            if (effects is not null)
                pump.beauty = await SdkBeautyBinding.StartAsync(
                    realtime,
                    effects,
                    beautyFailed ?? (_ => { })
                );
            await realtime.SetRemoteMediaFrameListenerAsync(pump.Receive);
            if (enableOutput)
                await pump.EnableOutputAsync();
            return pump;
        }
        catch
        {
            await pump.DisposeAsync();
            throw;
        }
    }

    internal async Task EnableOutputAsync()
    {
        if (output is null || Volatile.Read(ref outputEnabled) != 0 || IsStopped)
            return;
        await output.StartAsync(format, lifetime.Token);
        if (IsStopped)
        {
            await output.StopAsync();
            return;
        }
        Volatile.Write(ref outputEnabled, 1);
    }

    internal async Task DisableOutputAsync()
    {
        lock (ingress)
        {
            Volatile.Write(ref outputEnabled, 0);
            frames.Reset();
        }
        if (output is not null)
            await output.StopAsync();
    }

    internal void SetAudioSyncOffset(
        int value
    )
    {
        timing.SetOffset(value);
        frames.OffsetChanged();
        microphone?.OffsetChanged();
    }

    private void Receive(
        RealtimeMediaFrame packet
    )
    {
        lock (ingress)
        {
            if (!IsStopped)
            {
                var (presentation, reset) = timing.Map(
                    packet.StreamId,
                    packet.PresentationTime.Seconds,
                    Stopwatch.GetTimestamp()
                );
                if (reset)
                {
                    frames.Reset();
                    microphone?.ResetTiming();
                }
                if (packet is RealtimeVideoFrame video && Volatile.Read(ref outputEnabled) != 0 &&
                    video.Width is > 0 and <= 4096 && video.Height is > 0 and <= 2160 &&
                    frames.TryWrite(
                        video,
                        presentation,
                        (int)(video.Width * video.Height * 4),
                        video.IsDiscontinuous
                    ))
                    return;
                if (packet is RealtimeAudioFrame audio && microphone?.TrySubmit(audio, presentation) == true)
                    return;
            }
        }
        packet.Dispose();
    }

    private async Task ConsumeAsync()
    {
        bool loggedInvalidFrame = false;
        try
        {
            while (await frames.ReadAsync(lifetime.Token) is { } frame)
            {
                using var packet = frame.Packet;
                if (IsStopped || Volatile.Read(ref outputEnabled) == 0 || output is null)
                    continue;
                int width = checked((int)packet.Width), height = checked((int)packet.Height);
                double microseconds = (packet.PresentationTime.Seconds ?? 0) * 1_000_000;
                long timestamp = microseconds is >= long.MinValue and < (double)long.MaxValue ? (long)microseconds : 0;
                using var result = new ResultFrame(width, height, timestamp, sessionId);
                try
                {
                    packet.ReadBgra((pointer, stride, size) => CopyPixels(result, pointer, stride, size));
                }
                catch (Exception failure) when (failure is InvalidDataException or NotSupportedException or OverflowException or XmaxException)
                {
                    if (!loggedInvalidFrame)
                    {
                        CameraDiagnostics.Error("Dropped an unreadable virtual camera frame", failure);
                        loggedInvalidFrame = true;
                    }
                    continue;
                }
                if (IsStopped)
                    continue;
                if (Volatile.Read(ref outputEnabled) != 0 && output is not null)
                {
                    try
                    {
                        using var canvas = compositor.Compose(result);
                        if (frames.IsCurrent(frame.Epoch))
                            output.TrySubmit(new(
                                canvas.Pixels,
                                canvas.Width,
                                canvas.Height,
                                canvas.Stride,
                                canvas.TimestampMicroseconds,
                                sessionId
                            ));
                    }
                    catch (Exception failure)
                    {
                        await DisableOutputAsync();
                        if (!IsStopped)
                            faulted(failure);
                    }
                }
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
        catch (Exception failure)
        {
            if (!IsStopped)
                faulted(failure);
        }
        finally
        {
            frames.Complete();
        }
    }

    private static unsafe void CopyPixels(
        ResultFrame frame,
        nint pointer,
        int stride,
        int size
    )
    {
        if (pointer == 0 || stride < frame.Stride || stride > 32768 || size < (long)stride * frame.Height)
            throw new InvalidDataException("Invalid SDK result pixels.");
        var target = frame.Pixels.Span;
        for (int y = 0; y < frame.Height; ++y)
            new ReadOnlySpan<byte>(
                (byte*)pointer + y * stride,
                frame.Stride
            ).CopyTo(target.Slice(
                y * frame.Stride,
                frame.Stride
            ));
    }
    // The same adapter is used by the no-cloud end-to-end verification.
    internal static bool SubmitBgra(
        IVirtualCameraOutput output,
        nint pointer,
        int size,
        int width,
        int height,
        int stride,
        long timestamp,
        Guid sessionId
    )
    {
        if (width is < 1 or > 4096 || height is < 1 or > 2160 || stride < width * 4 || stride > 32768 ||
            (long)stride * height > 64 * 1024 * 1024 || size < (long)stride * height || pointer == 0)
            throw new InvalidDataException("The SDK video frame has an invalid BGRA layout.");
        int length = stride * height;
        byte[] pixels = ArrayPool<byte>.Shared.Rent(length);
        try
        {
            Marshal.Copy(pointer, pixels, 0, length);
            return output.TrySubmit(new(
                pixels.AsMemory(
                0,
                length
            ),
                width,
                height,
                stride,
                timestamp,
                sessionId
            ));
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(pixels);
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref stopped, 1) != 0)
        {
            await worker;
            return;
        }
        lifetime.Cancel();
        frames.Complete();
        Task? microphoneStop = microphone?.DisposeAsync().AsTask();
        try
        {
            await DisableOutputAsync();
        }
        finally
        {
            try
            {
                if (beauty is not null)
                    await beauty.DisposeAsync();
            }
            finally
            {
                await worker;
                lifetime.Dispose();
                if (microphoneStop is not null)
                    await microphoneStop;
            }
        }
    }
}
