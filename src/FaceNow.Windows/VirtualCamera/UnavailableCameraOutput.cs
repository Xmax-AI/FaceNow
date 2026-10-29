using FaceNow.Core.VirtualCamera;

namespace FaceNow.Windows.VirtualCamera;

/// <summary>Explicit capability result until a real MF backend is installed.</summary>
public sealed class UnavailableCameraOutput : IVirtualCameraOutput
{
    public CameraOutputStatus Status => OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000)
        ? new(CameraOutputState.Unavailable,
            "The FaceNow camera component is not included in this build. Video is currently available only inside FaceNow.",
            CameraRegistrationState.ComponentMissing)
        : new(CameraOutputState.Unavailable,
            "This virtual camera requires Windows 11. Video is currently available only inside FaceNow.",
            CameraRegistrationState.Unsupported);
    public Task StartAsync(OutputFormat format, CancellationToken cancellationToken = default) =>
        Task.FromException(new NotSupportedException(Status.Message));
    public bool TrySubmit(OutputFrame frame) => false;
    public Task StopAsync() => Task.CompletedTask;
    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
