namespace FaceNow.Core.VirtualCamera;

public enum CameraOutputState { Unavailable, Stopped, Running, Faulted }
public enum CameraRegistrationState { Unknown, Unsupported, ComponentMissing, NotRegistered, Registered }
/// <summary>Device registration and frame production are independent of the AI session state.</summary>
public sealed record CameraOutputStatus(CameraOutputState State, string Message,
    CameraRegistrationState Registration = CameraRegistrationState.Unknown);
public readonly record struct OutputFormat(int Width, int Height, int FramesPerSecond, Guid SessionId = default);

/// <summary>Borrowed BGRA data is valid only for the duration of TrySubmit.
/// An implementation must copy accepted bytes before returning and must not block its producer.</summary>
public readonly record struct OutputFrame(ReadOnlyMemory<byte> Bgra, int Width, int Height,
    int Stride, long TimestampMicroseconds, Guid SessionId);

public interface IVirtualCameraOutput : IAsyncDisposable
{
    CameraOutputStatus Status { get; }
    Task StartAsync(OutputFormat format, CancellationToken cancellationToken = default);
    bool TrySubmit(OutputFrame frame);
    Task StopAsync();
}
