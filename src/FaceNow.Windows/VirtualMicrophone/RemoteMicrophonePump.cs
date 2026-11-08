//
//  RemoteMicrophonePump.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using System.Buffers;
using System.Buffers.Binary;
using System.Runtime.InteropServices;
using FaceNow.Windows.Media;
using FaceNow.Windows.VirtualCamera;
using Xmax.SDK;

namespace FaceNow.Windows.VirtualMicrophone;

internal sealed class RemoteMicrophonePump : IAsyncDisposable
{
    private readonly MeetingOutputQueue<XmaxMediaFrame> frames;
    private readonly CancellationTokenSource lifetime = new();
    private readonly Task worker;

    internal RemoteMicrophonePump(MeetingOutputTiming timing, Action<Exception> faulted)
    {
        frames = new(timing, audio: true);
        worker = Task.Run(() => PlayAsync(faulted));
    }

    internal bool TrySubmit(XmaxMediaFrame frame, long presentation) => frames.TryWrite(frame, presentation, 0, frame.IsDiscontinuous);
    internal void OffsetChanged() => frames.OffsetChanged();
    internal void ResetTiming() => frames.Reset();

    private async Task PlayAsync(Action<Exception> faulted)
    {
        VbCablePlayback? playback = null;
        bool audible = false;
        long packets = 0;
        try
        {
            while (await frames.ReadAsync(lifetime.Token) is { } frame)
            {
                using var packet = frame.Packet;
                if (lifetime.IsCancellationRequested) break;
                // The SDK configures the result observer for 48 kHz mono PCM16.
                if (packet.SampleRate != VbCablePlayback.SampleRate || packet.Channels != 1 || packet.SamplesPerChannel is 0 or > 4800)
                    throw new InvalidDataException("Unexpected SDK audio format.");
                int count = (int)packet.SamplesPerChannel * 2;
                byte[] pcm = ArrayPool<byte>.Shared.Rent(count);
                try
                {
                    packet.ReadPcm16((pointer, size) =>
                    {
                        if (pointer == 0 || size != count) throw new InvalidDataException("Invalid SDK audio frame.");
                        Marshal.Copy(pointer, pcm, 0, count);
                    });
                    if (!frames.IsCurrent(frame.Epoch)) continue;
                    playback ??= new(error => frames.Complete(error));
                    playback.Write(pcm, count, frame.Discontinuous);
                    packets++;
                    if (!audible && IsAudible(pcm.AsSpan(0, count)))
                    {
                        audible = true;
                        CameraDiagnostics.Write("Virtual microphone: generated PCM reached VB-CABLE.");
                    }
                }
                finally { ArrayPool<byte>.Shared.Return(pcm); }
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
        catch (Exception error) { if (!lifetime.IsCancellationRequested) faulted(error); }
        finally
        {
            frames.Complete();
            playback?.Dispose();
            if (packets > 0) CameraDiagnostics.Write($"Virtual microphone stopped; packets={packets}; audible={audible}.");
        }
    }

    private static bool IsAudible(ReadOnlySpan<byte> pcm)
    {
        for (int index = 0; index < pcm.Length; index += 2)
            if (Math.Abs((int)BinaryPrimitives.ReadInt16LittleEndian(pcm[index..])) >= 64) return true;
        return false;
    }

    public async ValueTask DisposeAsync()
    {
        lifetime.Cancel();
        frames.Complete();
        try { await worker; }
        finally { lifetime.Dispose(); }
    }
}
