//
//  MeetingOutputQueue.cs
//  FaceNow
//

using System.Diagnostics;

namespace FaceNow.Windows.Media;

/// <summary>Owns buffered packets until they are due, discarded, or handed to the output worker.</summary>
internal sealed class MeetingOutputQueue<T>(
    MeetingOutputTiming timing,
    bool audio
) where T : class, IDisposable
{
    private const int VideoByteLimit = 256 * 1024 * 1024;
    private const int VideoFrameLimit = 180;
    private const int AudioFrameLimit = 1024;
    private readonly object gate = new();
    private readonly SemaphoreSlim changed = new(0, 1);
    private readonly Queue<(T Packet, long Presentation, int Bytes, bool Discontinuous)> pending = new();
    private readonly long maxLateness = MeetingOutputTiming.Ticks(audio ? 35 : 120);
    private int bytes, epoch;
    private bool completed, outputGap;
    private Exception? failure;
    private long? lastPresentation;

    /// <summary>
    /// Attempts to enqueue a packet. A successful write transfers disposal responsibility to the queue.
    /// </summary>
    internal bool TryWrite(
        T packet,
        long presentation,
        int packetBytes,
        bool discontinuous
    )
    {
        lock (gate)
        {
            if (completed)
                return false;
            if (lastPresentation is long last && presentation < last && discontinuous)
                ClearPending();
            if (lastPresentation is long previous && presentation <= previous)
                return false;

            if (!audio)
            {
                // Space out retained video at long offsets so the oldest frame can reach its due time.
                int slots = Math.Clamp(VideoByteLimit / Math.Max(1, packetBytes), 1, VideoFrameLimit);
                long interval = (timing.Delay(audio: false) + MeetingOutputTiming.Ticks(MeetingOutputTiming.BufferMilliseconds))
                    / Math.Max(1, slots - 2);
                if (lastPresentation is long latest && presentation - latest < interval)
                    return false;
                while (pending.Count >= VideoFrameLimit || (pending.Count > 0 && bytes + packetBytes > VideoByteLimit))
                    Drop();
            }
            else if (pending.Count >= AudioFrameLimit)
                Drop();

            pending.Enqueue((packet, presentation, packetBytes, discontinuous));
            bytes += packetBytes;
            lastPresentation = presentation;
            Signal();
            return true;
        }
    }

    /// <summary>
    /// Waits for the next due packet and transfers its ownership to the reader.
    /// </summary>
    /// <returns>The due packet and its epoch, or null after normal completion.</returns>
    internal async ValueTask<(T Packet, bool Discontinuous, int Epoch)?> ReadAsync(
        CancellationToken cancellation
    )
    {
        while (true)
        {
            cancellation.ThrowIfCancellationRequested();
            TimeSpan wait = Timeout.InfiniteTimeSpan;
            lock (gate)
            {
                if (failure is not null)
                    throw failure;
                if (completed)
                    return null;
                long now = Stopwatch.GetTimestamp();
                long delay = timing.Delay(audio);
                while (pending.TryPeek(out var item))
                {
                    long remaining = item.Presentation + delay - now;
                    if (remaining > 0)
                    {
                        wait = TimeSpan.FromMilliseconds(Math.Ceiling(remaining * 1000d / Stopwatch.Frequency));
                        break;
                    }
                    if (remaining < -maxLateness)
                    {
                        Drop();
                        continue;
                    }

                    pending.Dequeue();
                    bytes -= item.Bytes;
                    if (!audio && pending.TryPeek(out var next) && next.Presentation + delay <= now)
                    {
                        item.Packet.Dispose();
                        continue;
                    }
                    bool discontinuous = item.Discontinuous || outputGap;
                    outputGap = false;
                    return (item.Packet, discontinuous, epoch);
                }
            }
            await changed.WaitAsync(wait, cancellation).ConfigureAwait(false);
        }
    }

    internal bool IsCurrent(
        int value
    ) => value == Volatile.Read(ref epoch);

    internal void OffsetChanged()
    {
        lock (gate)
            Signal();
    }

    internal void Reset()
    {
        lock (gate)
            ClearPending();
    }

    internal void Complete(
        Exception? error = null
    )
    {
        lock (gate)
        {
            if (completed)
                return;
            completed = true;
            failure = error;
            ClearPending();
        }
    }

    private void ClearPending()
    {
        Interlocked.Increment(ref epoch);
        while (pending.Count > 0)
            Drop();
        outputGap = true;
        lastPresentation = null;
        Signal();
    }

    private void Drop()
    {
        var item = pending.Dequeue();
        bytes -= item.Bytes;
        item.Packet.Dispose();
        outputGap = true;
    }

    private void Signal()
    {
        if (changed.CurrentCount == 0)
            changed.Release();
    }
}
