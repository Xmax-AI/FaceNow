using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using FaceNow.Core.VirtualCamera;

namespace FaceNow.Windows.VirtualCamera;

/// <summary>Manages the native device and an independent, bounded AI video publisher.</summary>
public sealed class WindowsVirtualCamera : IVirtualCameraOutput
{
    private readonly SemaphoreSlim operations = new(1, 1);
    private readonly string helper;
    private readonly string source;
    private CameraOutputStatus status = new(CameraOutputState.Unavailable, "Checking virtual camera components…");
    private bool disposed;
    private FramePublisher? publisher;
    private FileStream? producerLease;
    private Timer? freshnessTimer;
    internal long SubmittedFrames => Volatile.Read(ref publisher)?.SubmittedFrames ?? 0;
    internal long DeliveredFrames => Interlocked.Read(ref deliveredBeforeStop) + (Volatile.Read(ref publisher)?.DeliveredFrames ?? 0);
    private long deliveredBeforeStop;
    public bool IsBusy { get; private set; }
    public CameraOutputStatus Status => status;
    private string symbolicLink = "";
    private bool componentCurrent;
    public bool IsOwnCamera(string id) => symbolicLink.Length > 0 && string.Equals(id, symbolicLink, StringComparison.OrdinalIgnoreCase);
    public bool CanInstall => !disposed && !IsBusy && Volatile.Read(ref publisher) is null && Supported && File.Exists(helper) && File.Exists(source);
    private static bool Supported => OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000);
    public event Action? StatusChanged;

    public WindowsVirtualCamera()
    {
        string architecture = RuntimeInformation.OSArchitecture == Architecture.Arm64 ? "arm64" : "x64";
        string directory = Path.Combine(AppContext.BaseDirectory, "Camera", architecture);
        helper = Path.Combine(directory, "FaceNow.CameraControl.exe");
        source = Path.Combine(directory, "FaceNow.CameraSource.dll");
        if (!Supported) status = new(CameraOutputState.Unavailable, "The current camera backend requires Windows 11.", CameraRegistrationState.Unsupported);
        else if (!File.Exists(helper) || !File.Exists(source)) status = new(CameraOutputState.Unavailable, "Camera components are missing. Install a FaceNow build that includes the virtual camera component.", CameraRegistrationState.ComponentMissing);
    }
    private void Notify() => StatusChanged?.Invoke();
    public async Task RefreshAsync()
    {
        if (disposed || !Supported || !File.Exists(helper) || !File.Exists(source)) { Notify(); return; }
        await operations.WaitAsync();
        try { await QueryAsync(); }
        catch (Exception error) { status = new(CameraOutputState.Faulted, error.Message); Notify(); }
        finally { operations.Release(); }
    }
    private async Task QueryAsync()
    {
        using var document = JsonDocument.Parse(await RunAsync("--status"));
        bool installed = document.RootElement.GetProperty("installed").GetBoolean();
        componentCurrent = document.RootElement.TryGetProperty("current", out var current) && current.GetBoolean();
        bool registered = document.RootElement.GetProperty("registered").GetBoolean();
        symbolicLink = document.RootElement.GetProperty("symbolicLink").GetString() ?? "";
        status = registered
            ? new(CameraOutputState.Stopped, "FaceNow is registered. Start generation to send AI video; otherwise the camera shows a placeholder.", CameraRegistrationState.Registered)
            : new(CameraOutputState.Stopped, installed ? "The camera component is installed. Click Install & Enable to register your FaceNow camera." : "Click Install & Enable to install the camera component and register FaceNow. Windows will request administrator approval.", CameraRegistrationState.NotRegistered);
        if (registered && !componentCurrent)
        {
            await StopPublisherAsync();
            status = new(CameraOutputState.Faulted, "The camera component needs an update. Stop generation, then click Install & Enable.", CameraRegistrationState.Registered);
        }
        else if (registered) UpdateOutputStatus();
        else await StopPublisherAsync();
        Notify();
    }
    public async Task InstallAndEnableAsync()
    {
        if (!CanInstall) throw new InvalidOperationException("Camera installation is currently unavailable.");
        await operations.WaitAsync();
        IsBusy = true; Notify();
        try
        {
            // Elevation is limited to installing the fixed, architecture-matched component.
            using var installer = Process.Start(new ProcessStartInfo(helper, "--install")
            { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden, WorkingDirectory = Path.GetDirectoryName(helper)! })
                ?? throw new InvalidOperationException("Could not start the camera installer.");
            await installer.WaitForExitAsync();
            if (installer.ExitCode != 0) throw new InvalidOperationException("Camera component installation failed. No device was enabled.");
            // Device scope belongs to this signed-in user, not to the elevated installer account.
            await RunAsync("--enable");
            await QueryAsync();
        }
        catch (Win32Exception error) when (error.NativeErrorCode == 1223)
        { await QueryAsync(); throw new InvalidOperationException("Camera installation was canceled."); }
        catch (Exception error) { status = new(CameraOutputState.Faulted, error.Message); throw; }
        finally { IsBusy = false; Notify(); operations.Release(); }
    }
    public async Task RemoveAsync()
    {
        await operations.WaitAsync(); IsBusy = true; Notify();
        try { await StopPublisherAsync(); await RunAsync("--remove"); await QueryAsync(); }
        catch (Exception error) { status = new(CameraOutputState.Faulted, error.Message); throw; }
        finally { IsBusy = false; Notify(); operations.Release(); }
    }
    internal async Task<string> CaptureDiagnosticFrameAsync()
    {
        await operations.WaitAsync(); IsBusy = true; Notify();
        try
        {
            string directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XMAX.AI", "FaceNow", "CameraPreview");
            Directory.CreateDirectory(directory);
            string path = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".bmp");
            await RunAsync("--verify", path);
            return path;
        }
        catch (Exception error) { status = new(CameraOutputState.Faulted, error.Message, status.Registration); throw; }
        finally { IsBusy = false; Notify(); operations.Release(); }
    }
    private async Task<string> RunAsync(string command, string? argument = null)
    {
        var start = new ProcessStartInfo(helper) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = Path.GetDirectoryName(helper)! };
        start.ArgumentList.Add(command); if (argument is not null) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start the native camera helper.");
        Task<string> output = process.StandardOutput.ReadToEndAsync(), error = process.StandardError.ReadToEndAsync();
        try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(45)); }
        catch (TimeoutException) { if (!process.HasExited) process.Kill(); throw new TimeoutException("The virtual camera operation timed out."); }
        string result = await output, diagnostics = await error;
        if (process.ExitCode != 0) throw new InvalidOperationException("Virtual camera: " + diagnostics.Trim());
        return result;
    }
    public async Task StartAsync(OutputFormat format, CancellationToken cancellationToken = default)
    {
        if (format.Width != 1920 || format.Height != 1080 || format.FramesPerSecond != 30 || format.SessionId == Guid.Empty)
            throw new ArgumentException("Virtual camera output requires 1920 × 1080 at 30 fps and a session identity.", nameof(format));
        await operations.WaitAsync(cancellationToken);
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            await StopPublisherAsync();
            await QueryAsync();
            if (status.Registration != CameraRegistrationState.Registered) throw new InvalidOperationException("Install and enable the FaceNow camera first.");
            if (!componentCurrent) throw new InvalidOperationException("Update the camera component with Install & Enable first.");
            cancellationToken.ThrowIfCancellationRequested();
            producerLease = CameraProducerLease.Acquire();
            publisher = new FramePublisher(symbolicLink, format.SessionId);
            freshnessTimer = new Timer(_ => UpdateOutputStatus(), null, 0, 500);
        }
        catch (Exception error) { if (publisher is null) { producerLease?.Dispose(); producerLease = null; } status = new(CameraOutputState.Faulted, error.Message, status.Registration); Notify(); throw; }
        finally { operations.Release(); }
    }
    public bool TrySubmit(OutputFrame frame) => Volatile.Read(ref publisher)?.TrySubmit(frame) ?? false;
    private void UpdateOutputStatus()
    {
        if (status.Registration != CameraRegistrationState.Registered || !componentCurrent) return;
        var current = Volatile.Read(ref publisher);
        if (current?.Failure is { } failure) { status = new(CameraOutputState.Faulted, failure.Message, status.Registration); Notify(); return; }
        bool active = current?.HasFreshFrame == true;
        var next = new CameraOutputStatus(active ? CameraOutputState.Running : CameraOutputState.Stopped,
            active ? "AI frames are available to Windows. This does not confirm a meeting participant has received them."
                : "FaceNow is registered. Waiting for AI video; the camera shows a placeholder.", CameraRegistrationState.Registered);
        if (next != status) { status = next; Notify(); }
    }
    private async Task StopPublisherAsync()
    {
        var timer = freshnessTimer; freshnessTimer = null;
        if (timer is not null) await timer.DisposeAsync();
        var previous = Interlocked.Exchange(ref publisher, null);
        try { if (previous is not null) { await previous.DisposeAsync(); Interlocked.Add(ref deliveredBeforeStop, previous.DeliveredFrames); } }
        finally { producerLease?.Dispose(); producerLease = null; }
        UpdateOutputStatus();
    }
    public async Task StopAsync()
    {
        await operations.WaitAsync();
        try { await StopPublisherAsync(); }
        finally { operations.Release(); }
    }
    public async ValueTask DisposeAsync()
    {
        disposed = true;
        await StopAsync();
        // System-lifetime camera registration survives closing the UI; Remove is an explicit action.
    }
}
