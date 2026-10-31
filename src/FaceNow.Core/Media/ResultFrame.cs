using System.Buffers;

namespace FaceNow.Core.Media;

/// <summary>An independent lease on immutable, tightly packed BGRA pixels. Writers finish before publishing.</summary>
public sealed class ResultFrame : IDisposable
{
    private sealed class Storage(int length)
    {
        internal readonly byte[] Bytes = ArrayPool<byte>.Shared.Rent(length);
        internal int References = 1;
    }
    private readonly Storage storage;
    private int disposed;
    public int Width { get; }
    public int Height { get; }
    public int Stride => Width * 4;
    public int Length => checked(Stride * Height);
    public long TimestampMicroseconds { get; }
    public Guid SessionId { get; }
    public Memory<byte> Pixels { get { ObjectDisposedException.ThrowIf(disposed != 0, this); return storage.Bytes.AsMemory(0, Length); } }
    public ResultFrame(int width, int height, long timestamp, Guid sessionId)
    {
        if (width < 1 || height < 1 || width > 4096 || height > 2160) throw new ArgumentOutOfRangeException(nameof(width));
        Width = width; Height = height; TimestampMicroseconds = timestamp; SessionId = sessionId;
        storage = new(Length);
    }
    private ResultFrame(ResultFrame frame)
    {
        ObjectDisposedException.ThrowIf(frame.disposed != 0, frame);
        Width = frame.Width; Height = frame.Height; TimestampMicroseconds = frame.TimestampMicroseconds; SessionId = frame.SessionId;
        storage = frame.storage; Interlocked.Increment(ref storage.References);
    }
    public ResultFrame Retain() => new(this);
    public void Dispose() { if (Interlocked.Exchange(ref disposed, 1) == 0 && Interlocked.Decrement(ref storage.References) == 0) ArrayPool<byte>.Shared.Return(storage.Bytes); }
}

/// <summary>One bounded mailbox per consumer; ownership transfers on acquisition.</summary>
public sealed class ResultFrameSource : IDisposable
{
    private readonly object gate = new();
    private ResultFrame? latest;
    private bool disposed;
    public void Publish(ResultFrame frame)
    {
        lock (gate) { if (disposed) return; var previous = latest; latest = frame.Retain(); previous?.Dispose(); }
    }
    public ResultFrame? TryAcquireFrame() { lock (gate) { var value = latest; latest = null; return value; } }
    public void Dispose() { lock (gate) { disposed = true; latest?.Dispose(); latest = null; } }
}
