using System.Diagnostics;

namespace FaceNow.Windows.Media;

/// <summary>Maps the SDK's shared audio and video clock onto a local monotonic timeline.</summary>
internal sealed class MeetingOutputTiming
{
    internal const int OffsetLimit = 5000;
    internal const int BufferMilliseconds = 80;
    private const int ClockJumpMilliseconds = 2000;
    private ulong? streamId;
    private double? sourceOrigin;
    private long localOrigin;
    private int offset;

    internal MeetingOutputTiming(int offset) => SetOffset(offset);

    internal void SetOffset(int value) => Volatile.Write(ref offset, Math.Clamp(value, -OffsetLimit, OffsetLimit));

    internal long Delay(bool audio)
    {
        int value = Volatile.Read(ref offset);
        return Ticks(Math.Max(0, audio ? value : -value));
    }

    // Called by the serialized SDK callback before handing frames to the two output workers.
    internal (long Presentation, bool Reset) Map(ulong stream, double? source, long arrival)
    {
        bool reset = streamId != stream;
        if (reset)
        {
            streamId = stream;
            sourceOrigin = null;
        }
        long bufferedArrival = arrival + Ticks(BufferMilliseconds);
        if (source is not > 0 || !double.IsFinite(source.Value)) return (bufferedArrival, reset);

        if (sourceOrigin is double origin)
        {
            double delta = (source.Value - origin) * Stopwatch.Frequency;
            double fromArrival = delta + (localOrigin - bufferedArrival);
            if (Math.Abs(fromArrival) <= Ticks(ClockJumpMilliseconds)) return (localOrigin + (long)Math.Round(delta), reset);
            reset = true;
        }
        sourceOrigin = source;
        localOrigin = bufferedArrival;
        return (bufferedArrival, reset);
    }

    internal static long Ticks(int milliseconds) => Stopwatch.Frequency * milliseconds / 1000;
}
