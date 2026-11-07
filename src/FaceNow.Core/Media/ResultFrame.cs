//
//  ResultFrame.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using System.Buffers;

namespace FaceNow.Core.Media;

/// <summary>Owns a pooled BGRA frame while composing virtual-camera output.</summary>
public sealed class ResultFrame : IDisposable
{
    private byte[]? pixels;

    public int Width { get; }
    public int Height { get; }
    public int Stride => Width * 4;
    public int Length => checked(Stride * Height);
    public long TimestampMicroseconds { get; }
    public Guid SessionId { get; }
    public Memory<byte> Pixels => (pixels ?? throw new ObjectDisposedException(nameof(ResultFrame))).AsMemory(0, Length);

    public ResultFrame(int width, int height, long timestamp, Guid sessionId)
    {
        if (width < 1 || height < 1 || width > 4096 || height > 2160)
            throw new ArgumentOutOfRangeException(nameof(width));
        Width = width;
        Height = height;
        TimestampMicroseconds = timestamp;
        SessionId = sessionId;
        pixels = ArrayPool<byte>.Shared.Rent(Length);
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref pixels, null) is { } owned)
            ArrayPool<byte>.Shared.Return(owned);
    }
}
