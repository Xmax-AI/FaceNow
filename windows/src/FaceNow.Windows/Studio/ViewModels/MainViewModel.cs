//
//  MainViewModel.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using FaceNow.Windows.Studio.Platform;
using Xmax.SDK;
using FaceNow.Windows.Studio.Services;
using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.VirtualCamera;
using FaceNow.Core.User;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel : INotifyPropertyChanged, IAsyncDisposable
{
    private readonly IUiDispatcher dispatcher;
    private readonly IThumbnailLoader thumbnails;
    private IXmaxRealtimeManaging? session;
    private RealtimeMediaStream? localStream;
    private readonly IVirtualCameraOutput? cameraOutput;
    private readonly IGenerationAccess? generationAccess;
    private RemoteCameraPump? cameraPump;
    private Task? outputStartup;

    internal IXmaxRealtimeManaging? Session => session;

    private CancellationTokenSource? operationCancellation;
    private int revision;
    private int foregroundOperations;
    private bool closingSession;
    private Task cleanup = Task.CompletedTask;
    private string status = AppText.Get("Ready · camera preview does not require an API key"), error = "", metrics = AppText.Get("Waiting for video statistics");
    private CameraDevice? camera;
    private string? preferredCameraId;

    internal static IReadOnlyList<(string Ratio, RealtimeVideoFormat Format)> CameraPresets { get; } =
    [
        ("16:9", new(1920, 1080)),
        ("9:16", new(1080, 1920)),
        ("1:1", new(1408, 1408)),
        ("3:4", new(1152, 1536)),
        ("4:3", new(1536, 1152)),
    ];

    private RealtimeVideoFormat format = CameraPresets[0].Format;
    private CameraRotation rotation;
    private string sessionKey = "", sessionCamera = "";

    private static XmaxEnvironment ServiceEnvironment => FaceNow.Core.Product.ProductProfile.Current.IsOverseas ? XmaxEnvironment.Global : XmaxEnvironment.China;

    private const RealtimeModel ServiceModel = RealtimeModel.X2_1;
    private RealtimeVideoFormat sessionFormat;
    private CameraRotation sessionRotation;
    private RealtimeVideoTrack? local, remote;

    public ObservableCollection<CameraDevice> Cameras { get; } = [];

    public Func<CameraDevice, bool>? CameraFilter { get; set; }

    private string apiKey = "";

    public string ApiKey
    {
        get => apiKey;
        set
        {
            apiKey = value;
            Changed();
            Changed(nameof(KeyLabel));
        }
    }

    public string Prompt { get; set; } = "";

    public string ReferenceImage { get; set; } = "";

    public bool FaceRestoration { get; set; }

    public CameraDevice? SelectedCamera
    {
        get => camera;
        private set
        {
            if (camera == value)
                return;
            camera = value;
            Changed();
            Changed(nameof(LocalTitle));
        }
    }

    public RealtimeVideoFormat SelectedFormat
    {
        get => format;
        set
        {
            if (format == value)
                return;
            format = value;
            Changed();
        }
    }

    public CameraRotation SelectedRotation
    {
        get => rotation;
        set
        {
            if (!Enum.IsDefined(value))
                throw new ArgumentOutOfRangeException(nameof(value));
            if (rotation == value)
                return;
            rotation = value;
            Changed();
        }
    }

    public bool Busy => foregroundOperations > 0 || IsClosing;

    public bool IsClosing => closingSession;

    private void RefreshBusy()
    {
        Changed(nameof(Busy));
        Changed(nameof(IsClosing));
        Changed(nameof(CanEdit));
        Changed(nameof(StartLabel));
        RefreshCommands();
    }

    public string Status
    {
        get => status;
        private set
        {
            status = AppText.Get(value);
            Changed();
        }
    }

    public string Error
    {
        get => error;
        private set
        {
            error = AppText.Get(value);
            Changed();
        }
    }

    public string Metrics
    {
        get => metrics;
        private set
        {
            metrics = AppText.Get(value);
            Changed();
        }
    }

    public RealtimeVideoTrack? LocalVideo
    {
        get => local;
        private set
        {
            local = value;
            Changed();
        }
    }

    public RealtimeVideoTrack? RemoteVideo
    {
        get => remote;
        private set
        {
            if (remote == value)
                return;
            remote = value;
            Changed();
        }
    }

    public AsyncCommand RefreshCommand { get; }

    public AsyncCommand PreviewCommand { get; }

    public AsyncCommand GenerateCommand { get; }

    public AsyncCommand StopCommand { get; }

    public event PropertyChangedEventHandler? PropertyChanged;

    public event Action? AuthenticationRejected;

    public MainViewModel(
        IUiDispatcher dispatcher,
        IThumbnailLoader thumbnails,
        IVirtualCameraOutput? cameraOutput = null,
        IGenerationAccess? generationAccess = null
    )
    {
        this.dispatcher = dispatcher;
        this.thumbnails = thumbnails;
        this.cameraOutput = cameraOutput;
        this.generationAccess = generationAccess;
        effects.Changed += EffectsChanged;
        elapsedTimer = dispatcher.CreateTimer(TimeSpan.FromSeconds(1));
        RefreshCommand = new(() => GuardAsync(RefreshCamerasAsync), () => !Busy);
        PreviewCommand = new(() => GuardAsync(PreviewAsync), () => !Busy && Cameras.Count > 0);
        GenerateCommand = new(() => GuardAsync(GenerateAsync), () => !Busy && Cameras.Count > 0);
        StopCommand = new(() => GuardAsync(StopAsync), () => session is not null && !IsClosing);
        InitializePresentation();
    }

    public async Task InitializeAsync()
    {
        try
        {
            if (IsPreview)
                return;
            LoadAudioOutputPreferences();
            _ = RefreshVirtualMicrophoneAsync();
            await GuardAsync(async () =>
            {
                await RefreshCamerasAsync();
                await RestoreMicrophoneSelectionAsync();
            });
        }
        catch (Exception failure)
        {
            ReportError(failure);
        }
    }

    public async Task RefreshCamerasAsync()
    {
        var devices = await MediaDevices.ListCameraDevicesAsync();
        if (!IsPreview)
            preferredCameraId ??= CaptureDeviceSelectionStore.LoadCamera();
        Cameras.Clear();
        foreach (var item in devices.Where(item => CameraFilter?.Invoke(item) ?? true))
            Cameras.Add(item);
        SelectedCamera = Cameras.FirstOrDefault(item => string.Equals(
            item.Id,
            preferredCameraId,
            StringComparison.OrdinalIgnoreCase
        ))
            ?? Cameras.FirstOrDefault(item => string.Equals(
                item.Id,
                SelectedCamera?.Id,
                StringComparison.OrdinalIgnoreCase
            ))
            ?? Cameras.FirstOrDefault(item => item.IsDefault)
            ?? Cameras.FirstOrDefault();
        Status = Cameras.Count == 0 ? AppText.Get("No cameras found. Check your device and Windows camera permissions.") : AppText.Format(
            "Found {0} cameras",
            Cameras.Count
        );
        RefreshCommands();
    }

    internal void SelectCamera(
        CameraDevice device
    )
    {
        preferredCameraId = device.Id;
        SelectedCamera = device;
        if (!IsPreview)
            CaptureDeviceSelectionStore.SaveCamera(device.Id);
    }

    public async Task PreviewAsync()
    {
        await EnsureSessionAsync();
        Active = true;
    }

    private async Task EnsureSessionAsync()
    {
        if (IsClosing)
            throw new OperationCanceledException("Session cleanup is in progress.");
        if (generationAccess is not null)
            ApiKey = generationAccess.GetVerifiedGenerationKey();
        if (SelectedCamera is null)
        {
            RequireCamera();
            throw new InvalidOperationException("Select a camera before starting. Choose your physical camera for live video.");
        }
        var requestedFormat = SelectedFormat;
        var requestedCamera = SelectedCamera;
        var requestedMicrophone = Microphone;
        var requestedRotation = SelectedRotation;
        if (session is not null && localStream is not null && sessionKey == ApiKey &&
            sessionCamera == requestedCamera.Id && sessionFormat == requestedFormat &&
            sessionRotation == requestedRotation)
            return;
        await StopAsync();
        int current = ++revision;
        var receiveMicrophoneLevel = CreateMicrophoneLevelHandler();
        using var client = new XmaxClient(new()
        {
            ApiKey = ApiKey,
            Environment = ServiceEnvironment
        });
        var next = client.CreateRealtimeManager(new()
        {
            Model = ServiceModel,
            AdaptiveQualityEnabled = true
        });
        session = next;
        sessionKey = ApiKey;
        sessionCamera = requestedCamera.Id;
        sessionFormat = requestedFormat;
        sessionRotation = requestedRotation;
        LocalVideo = RemoteVideo = null;
        foreach (var row in TimingRows.Concat(UplinkRows).Concat(UplinkNetworkRows).Concat(DownlinkRows).Concat(DownlinkNetworkRows))
            row.Value = "—";
        await next.SetStateListenerAsync(CreateSessionStateHandler());
        await next.SetUplinkVideoStatisticsListenerAsync(stats => { if (current == revision) ReceiveUplinkStatistics(stats); });
        await next.SetDownlinkVideoStatisticsListenerAsync(stats => { if (current == revision) ReceiveDownlinkStatistics(stats); });
        await next.SetLaunchTimingListenerAsync(timing => { if (current == revision) ReceiveLaunchTiming(timing); });
        await next.SetNetworkQualityListenerAsync(quality => { if (current == revision) ReceiveNetworkQuality(quality); });
        await next.SetMicrophoneLevelListenerAsync(receiveMicrophoneLevel);
        RefreshCommands();
        Status = "正在准备摄像头…";
        var preparation = new CancellationTokenSource();
        operationCancellation = preparation;
        var preparationToken = preparation.Token;
        try
        {
            effects.BeginSession();
            var pipeline = await RemoteCameraPump.StartAsync(next, cameraOutput, requestedFormat,
                failure => dispatcher.InvokeAsync(() => { if (current == revision) ReportCameraOutputError(failure); }), effects,
                failure => dispatcher.InvokeAsync(() => { if (current == revision) ReportError(new InvalidOperationException("Beauty unavailable. Original video has been restored.")); }),
                enableOutput: false, microphoneFaulted: VirtualMicrophoneStatus == VirtualMicrophoneState.Enabled ? failure => dispatcher.InvokeAsync(() =>
                {
                    if (current == revision)
                        ReportVirtualMicrophoneError(failure);
                }) : null, audioSyncOffset: AudioSyncOffsetMilliseconds);
            if (current != revision)
            {
                await pipeline.DisposeAsync();
                throw new OperationCanceledException();
            }
            cameraPump = pipeline;
            pipeline.SetAudioSyncOffset(AudioSyncOffsetMilliseconds);
            preparationToken.ThrowIfCancellationRequested();
            var cameraStream = await next.CreateLocalCameraStreamAsync(
                videoFormat: requestedFormat,
                camera: RealtimeCamera.Device(requestedCamera.Id),
                microphone: requestedMicrophone,
                mirror: false,
                rotation: requestedRotation
            );
            if (current != revision)
                throw new OperationCanceledException(preparationToken);
            localStream = cameraStream;
            LocalVideo = cameraStream.VideoTrack;
        }
        catch (Exception failure) when (current != revision)
        {
            throw new OperationCanceledException(
                "Camera preparation was stopped.",
                failure,
                preparationToken
            );
        }
        catch
        {
            if (current == revision)
                await StopAsync();
            throw;
        }
        finally
        {
            if (current == revision)
            {
                operationCancellation?.Dispose();
                operationCancellation = null;
            }
        }
    }

    private Task EnsureCameraOutputAsync(
        int current
    )
    {
        if (outputStartup is { IsCompleted: false })
            return outputStartup;
        return outputStartup = StartCameraOutputAsync(current);
    }

    private async Task StartCameraOutputAsync(
        int current
    )
    {
        if (cameraPump is not { IsStopped: false } pipeline || cameraOutput?.Status.Registration != CameraRegistrationState.Registered)
            return;
        try
        {
            await pipeline.EnableOutputAsync();
        }
        catch (Exception failure) when (current == revision)
        {
            CameraDiagnostics.Error("Virtual camera startup failed; RTC remains active", failure);
            ReportCameraOutputError(failure);
            return;
        }
        if (current != revision)
        {
            await pipeline.DisableOutputAsync();
            throw new OperationCanceledException();
        }
    }

    private void ReportCameraOutputError(
        Exception failure
    ) => Error = AppText.Get("Virtual camera output: ") + AppText.Get(failure.Message);

    internal async Task SynchronizeCameraOutputAsync()
    {
        var target = session;
        int current = revision;
        if (cameraOutput?.Status.Registration != CameraRegistrationState.Registered)
        {
            var previous = cameraPump;
            if (previous is not null)
            {
                await previous.DisableOutputAsync();
            }
        }
        else if (target is not null && State == RealtimeConnectionState.Generating && cameraOutput.Status.State != CameraOutputState.Faulted)
            await EnsureCameraOutputAsync(current);
    }

    private async Task GuardAsync(
        Func<Task> operation
    )
    {
        ++foregroundOperations;
        RefreshBusy();
        Error = "";
        try
        {
            await operation();
        }
        catch (OperationCanceledException)
        {
            if (Error.Length == 0 && !IsClosing)
                Status = "操作已取消";
        }
        catch (Exception failure)
        {
            ReportError(failure);
        }
        finally
        {
            --foregroundOperations;
            RefreshBusy();
        }
    }

    public void ReportError(
        Exception failure
    )
    {
        CameraDiagnostics.Error("Playback or generation failed", failure);
        HandleGenerationFailure(failure);
    }

    private void RefreshCommands()
    {
        RefreshCommand.Refresh();
        PreviewCommand.Refresh();
        GenerateCommand.Refresh();
        StopCommand.Refresh();
        StartCommand?.Refresh();
        SubmitPromptCommand?.Refresh();
    }

    private void Changed(
        [CallerMemberName] string? name = null
    ) => PropertyChanged?.Invoke(this, new(name));

    public async ValueTask DisposeAsync()
    {
        ResetHomeReferences();
        await StopAsync();
        await effects.FlushAsync();
        effects.Changed -= EffectsChanged;
    }
}
