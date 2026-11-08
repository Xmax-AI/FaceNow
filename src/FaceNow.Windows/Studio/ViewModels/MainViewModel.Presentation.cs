//
//  MainViewModel.Presentation.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.Diagnostics;
using FaceNow.Core.User;
using FaceNow.Windows.Studio.Platform;
using FaceNow.Windows.Studio.Services;
using Xmax.SDK;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private bool active, statisticsVisible, preview;
    private DateTimeOffset? startedAt;
    private readonly IUiTimer elapsedTimer;

    public bool Active
    {
        get => active;
        private set
        {
            if (active == value)
                return;
            active = value;
            Changed();
            Changed(nameof(StartLabel));
        }
    }

    public bool IsPreview
    {
        get => preview;
        private set
        {
            preview = value;
            Changed();
            Changed(nameof(StartLabel));
            Changed(nameof(StopLabel));
            Changed(nameof(Elapsed));
            Changed(nameof(LocalPlaceholder));
        }
    }

    public bool CanEdit => !Busy;

    public string LocalPlaceholder => IsPreview ? AppText.Get("UI Preview\nCamera is disabled") : "";

    public string ResultPlaceholder => AppText.Get(IsPreview ? "UI Preview\nGeneration is disabled" :
        RemoteReady && RemoteVideo is not null ? "" :
        State is RealtimeConnectionState.Connected or RealtimeConnectionState.Generating ? "Generating…" : "Waiting for connection…");

    public string LocalTitle => IsPreview || string.IsNullOrEmpty(SelectedCamera?.Name) ? AppText.Get("Local") : AppText.Get("Local · ") + SelectedCamera.Name;

    public string KeyLabel => ApiKey.Length == 0 ? "" : "****************";

    public string StartLabel => IsClosing ? "Stopping…" : Busy ? "Starting…" : IsPreview ? "Preview UI" : "Start Camera";

    public string StopLabel => IsPreview ? "Exit Preview" : "Stop Session";

    public string Elapsed => IsPreview ? "Preview" : startedAt is { } start ? (DateTimeOffset.UtcNow - start).ToString(@"mm\:ss") : "00:00";

    public bool StatisticsVisible
    {
        get => statisticsVisible;
        set
        {
            statisticsVisible = value;
            Changed();
        }
    }

    public MetricRow[] TimingRows { get; } = [new("Create session"), new("RTC join"), new("Publish local stream"), new("First frame"), new("Total startup")];

    public MetricRow[] UplinkRows { get; } = [new("Uplink resolution"), new("Uplink frame rate"), new("Uplink bitrate")];

    public MetricRow[] UplinkNetworkRows { get; } = [new("Uplink packet loss"), new("Uplink network quality"), new("Uplink RTT")];

    public MetricRow[] DownlinkRows { get; } = [new("Downlink resolution"), new("Downlink frame rate"), new("Downlink bitrate")];

    public MetricRow[] DownlinkNetworkRows { get; } = [new("Playback buffer delay"), new("Downlink packet loss"), new("Downlink network quality"), new("RTT (cloud)"), new("E2E (RTC estimate)")];

    public AsyncCommand StartCommand { get; private set; } = null!;

    public AsyncCommand SubmitPromptCommand { get; private set; } = null!;

    public event Action? ApiKeyRequired;

    public event Action? CameraRequired;

    public event Action? CreditsRequired;

    private void InitializePresentation()
    {
        foreach (string mode in new[] { "charx", "clothx", "vibex", "dimx" })
            References(mode).Add(new()
            {
                IsUpload = true,
                Mode = mode,
                Name = AppText.Get("Upload")
            });
        foreach (var item in ReferenceCatalog.Load())
            References(item.Mode).Add(item);
        HomeReferencePresets = CharacterReferences.Where(item => !item.IsUpload).ToArray();
        HomeSelectedReference = HomeReferencePresets[0];
        StartCommand = new(() => GuardAsync(StartLandingAsync), () => CanChooseHomeReference);
        SubmitPromptCommand = new(() => GuardAsync(SubmitPromptAsync), CanSubmitPrompt);
        elapsedTimer.Tick += (_, _) => Changed(nameof(Elapsed));
    }

    public void ConfigurePreview(
        bool sessionPage
    )
    {
        IsPreview = true;
        Active = sessionPage;
        if (sessionPage)
            ApplyHomeReference(HomeSelectedReference);
        Changed(nameof(LocalTitle));
    }

    public async Task StartLandingAsync()
    {
        if (IsClosing || Active || homeReferenceUpload is not null)
            return;
        var selected = HomeSelectedReference;
        if (IsPreview)
        {
            ApplyHomeReference(selected);
            Active = true;
            return;
        }
        if (string.IsNullOrWhiteSpace(ApiKey))
        {
            RequireKey();
            return;
        }
        if (SelectedCamera is null)
        {
            RequireCamera();
            return;
        }
        EnsureCreditsForStart();
        ApplyHomeReference(selected);
        string freePrompt = Prompt;
        var context = ReferenceContext(selected);
        Prompt = context.Prompt;
        ReferenceImage = context.ReferencePath ?? "";
        FaceRestoration = false;
        try
        {
            await GenerateAsync();
        }
        finally
        {
            Prompt = freePrompt;
            Changed(nameof(Prompt));
        }
    }

    private void EnsureCreditsForStart()
    {
        try
        {
            generationAccess?.EnsureSufficientCredits();
        }
        catch (AccountException error) when (error.Code == CreditPolicy.InsufficientCode)
        {
            CreditsRequired?.Invoke();
            throw;
        }
    }

    private void RequireKey()
    {
        Error = generationAccess is not null ? "Choose or create an API key in your account menu before starting."
        : "API Key is required — click the key button in the top-right corner to enter it.";
        ApiKeyRequired?.Invoke();
    }

    private void RequireCamera()
    {
        Error = Cameras.Count == 0 ? "No camera is available. Connect a camera and try again." : "Select a camera before starting. Choose your physical camera for live video.";
        CameraRequired?.Invoke();
    }

    private void BeginElapsed()
    {
        if (State != RealtimeConnectionState.Generating || elapsedTimer.IsEnabled)
            return;
        startedAt = DateTimeOffset.UtcNow;
        elapsedTimer.Start();
        Changed(nameof(Elapsed));
    }

    public void ClearError() => Error = "";
}
