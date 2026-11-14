//
//  ResultFrame.cs
//  FaceNow
//

using System.Buffers;

namespace FaceNow.Core.Media;

/// <summary>
/// Owns a pooled BGRA frame while composing virtual camera output.
/// </summary>
public sealed class ResultFrame : IDisposable
{
    private byte[]? pixels;

    /// <summary>
    /// Gets the frame width in pixels.
    /// </summary>
    public int Width { get; }

    /// <summary>
    /// Gets the frame height in pixels.
    /// </summary>
    public int Height { get; }

    /// <summary>
    /// Gets the row stride in bytes. Rows are tightly packed.
    /// </summary>
    public int Stride => Width * 4;

    /// <summary>
    /// Gets the number of bytes that belong to the frame.
    /// </summary>
    public int Length => checked(Stride * Height);

    /// <summary>
    /// Gets the source presentation timestamp in microseconds.
    /// </summary>
    public long TimestampMicroseconds { get; }

    /// <summary>
    /// Gets the virtual camera output session identifier.
    /// </summary>
    public Guid SessionId { get; }

    /// <summary>
    /// Gets the writable frame bytes. The memory is valid until this frame is disposed.
    /// </summary>
    public Memory<byte> Pixels => (pixels ?? throw new ObjectDisposedException(nameof(ResultFrame))).AsMemory(
        0,
        Length
    );

    /// <summary>
    /// Rents a buffer for a tightly packed BGRA frame.
    /// </summary>
    /// <param name="width">The frame width in pixels, from 1 through 4096.</param>
    /// <param name="height">The frame height in pixels, from 1 through 2160.</param>
    /// <param name="timestamp">The source presentation timestamp in microseconds.</param>
    /// <param name="sessionId">The virtual camera output session identifier.</param>
    public ResultFrame(
        int width,
        int height,
        long timestamp,
        Guid sessionId
    )
    {
        if (width < 1 || height < 1 || width > 4096 || height > 2160)
            throw new ArgumentOutOfRangeException(nameof(width));
        Width = width;
        Height = height;
        TimestampMicroseconds = timestamp;
        SessionId = sessionId;
        pixels = ArrayPool<byte>.Shared.Rent(Length);
    }

    /// <summary>
    /// Returns the frame buffer to the pool.
    /// </summary>
    public void Dispose()
    {
        if (Interlocked.Exchange(ref pixels, null) is { } owned)
            ArrayPool<byte>.Shared.Return(owned);
    }
}
