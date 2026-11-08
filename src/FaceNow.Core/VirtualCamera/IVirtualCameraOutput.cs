//
//  IVirtualCameraOutput.cs
//  FaceNow
//

namespace FaceNow.Core.VirtualCamera;

/// <summary>
/// Describes whether the virtual camera is producing frames.
/// </summary>
public enum CameraOutputState
{
    /// <summary>The camera output is unavailable.</summary>
    Unavailable,

    /// <summary>The camera output has no fresh frame to publish.</summary>
    Stopped,

    /// <summary>The camera output has a fresh frame available.</summary>
    Running,

    /// <summary>A camera operation or the frame publisher reported an error.</summary>
    Faulted
}

/// <summary>
/// Describes the current virtual camera registration.
/// </summary>
public enum CameraRegistrationState
{
    /// <summary>The registration has not been confirmed.</summary>
    Unknown,

    /// <summary>The Windows version does not support this camera backend.</summary>
    Unsupported,

    /// <summary>The camera component is missing from the app distribution.</summary>
    ComponentMissing,

    /// <summary>Windows has not registered the device for this user.</summary>
    NotRegistered,

    /// <summary>Windows has registered the device for this user.</summary>
    Registered
}

/// <summary>
/// Reports virtual camera registration and frame production independently of the AI session.
/// </summary>
/// <param name="State">The frame production state.</param>
/// <param name="Message">A description of the current state or failure.</param>
/// <param name="Registration">The system registration state.</param>
public sealed record CameraOutputStatus(
    CameraOutputState State,
    string Message,
    CameraRegistrationState Registration = CameraRegistrationState.Unknown
);

/// <summary>
/// Describes the format and identity of one virtual camera output session.
/// </summary>
/// <param name="Width">The frame width in pixels.</param>
/// <param name="Height">The frame height in pixels.</param>
/// <param name="FramesPerSecond">The nominal output rate in frames per second.</param>
/// <param name="SessionId">The identity used to reject frames from other sessions.</param>
public readonly record struct OutputFormat(
    int Width,
    int Height,
    int FramesPerSecond,
    Guid SessionId = default
);

/// <summary>
/// Describes a borrowed BGRA frame for virtual camera output.
/// </summary>
/// <param name="Bgra">The bytes, borrowed for the duration of <see cref="IVirtualCameraOutput.TrySubmit"/>.</param>
/// <param name="Width">The frame width in pixels.</param>
/// <param name="Height">The frame height in pixels.</param>
/// <param name="Stride">The distance in bytes between the starts of successive rows.</param>
/// <param name="TimestampMicroseconds">The source presentation timestamp in microseconds.</param>
/// <param name="SessionId">The output session to which this frame belongs.</param>
public readonly record struct OutputFrame(
    ReadOnlyMemory<byte> Bgra,
    int Width,
    int Height,
    int Stride,
    long TimestampMicroseconds,
    Guid SessionId
);

/// <summary>
/// Publishes frames to a system virtual camera.
/// </summary>
public interface IVirtualCameraOutput : IAsyncDisposable
{
    /// <summary>
    /// Gets the most recently observed registration and output state.
    /// </summary>
    CameraOutputStatus Status { get; }

    /// <summary>
    /// Starts publishing for the supplied session and format.
    /// </summary>
    /// <param name="format">The format and session identifier used to validate submissions.</param>
    /// <param name="cancellationToken">Cancels startup while the output is being prepared.</param>
    Task StartAsync(
        OutputFormat format,
        CancellationToken cancellationToken = default
    );

    /// <summary>
    /// Attempts to publish a frame without blocking the producer.
    /// </summary>
    /// <param name="frame">The borrowed frame. An implementation copies accepted bytes before returning.</param>
    /// <returns>True if the output accepted the frame.</returns>
    bool TrySubmit(
        OutputFrame frame
    );

    /// <summary>
    /// Stops the frame publisher and releases the output session.
    /// </summary>
    Task StopAsync();
}
