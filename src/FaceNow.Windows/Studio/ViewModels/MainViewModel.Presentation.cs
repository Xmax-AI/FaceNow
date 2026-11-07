//
//  MainViewModel.Presentation.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.Collections.ObjectModel;
using System.Diagnostics;
using FaceNow.Core.User;
using FaceNow.Windows.Studio.Platform;
using FaceNow.Windows.Studio.Services;
using Xmax.SDK;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private bool active, statisticsVisible, preview;
    private string selectedMode = "charx";
    private long intent;
    private DateTimeOffset? startedAt;
    private readonly IUiTimer elapsedTimer;
    private (GenerationContext Context, bool FaceRestoration, long Intent, int Revision)? pendingConditions;
    private Task? updateTask;
    internal Task WaitForConditionsAsync() => updateTask ?? Task.CompletedTask;
    private readonly Dictionary<ReferenceItem, CancellationTokenSource> uploadCancellations = [];
    public bool Active { get => active; private set { if (active == value) return; active = value; Changed(); Changed(nameof(StartLabel)); } }
    public bool IsPreview { get => preview; private set { preview = value; Changed(); Changed(nameof(StartLabel)); Changed(nameof(StopLabel)); Changed(nameof(Elapsed)); Changed(nameof(LocalPlaceholder)); } }
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
    public bool StatisticsVisible { get => statisticsVisible; set { statisticsVisible = value; Changed(); } }
    public string SelectedMode
    {
        get => selectedMode;
        set { if (selectedMode == value) return; selectedMode = value; ++intent; pendingConditions = null; ClearError(); Changed(); }
    }
    public ObservableCollection<ReferenceItem> CharacterReferences { get; } = [];
    public ObservableCollection<ReferenceItem> ClothingReferences { get; } = [];
    public ObservableCollection<ReferenceItem> StyleReferences { get; } = [];
    public ObservableCollection<ReferenceItem> SummonReferences { get; } = [];
    private ReferenceItem? freeReference;
    public ReferenceItem? FreeReference
    {
        get => freeReference;
        private set
        {
            if (freeReference is not null) freeReference.PropertyChanged -= FreeReferenceChanged;
            freeReference = value;
            if (value is not null) value.PropertyChanged += FreeReferenceChanged;
            Changed(); Changed(nameof(HasFreeReference)); SubmitPromptCommand?.Refresh();
        }
    }
    public bool HasFreeReference => FreeReference is not null;
    private void FreeReferenceChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    { Changed(nameof(FreeReference)); SubmitPromptCommand.Refresh(); }
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
        foreach (string mode in new[] { "charx", "clothx", "vibex", "dimx" }) References(mode).Add(new() { IsUpload = true, Mode = mode, Name = AppText.Get("Upload") });
        foreach (var item in ReferenceCatalog.Load()) References(item.Mode).Add(item);
        StartCommand = new(() => GuardAsync(StartLandingAsync), () => !Busy);
        SubmitPromptCommand = new(() => GuardAsync(SubmitPromptAsync), CanSubmitPrompt);
        elapsedTimer.Tick += (_, _) => Changed(nameof(Elapsed));
    }
    public void ConfigurePreview(bool sessionPage)
    {
        IsPreview = true;
        Active = sessionPage;
        if (sessionPage) MarkSelected(CharacterReferences.First(item => !item.IsUpload));
        Changed(nameof(LocalTitle));
    }
    public async Task StartLandingAsync()
    {
        if (IsClosing) return;
        if (IsPreview) { Active = true; MarkSelected(CharacterReferences.First(item => !item.IsUpload)); return; }
        if (string.IsNullOrWhiteSpace(ApiKey)) { RequireKey(); return; }
        if (SelectedCamera is null) { RequireCamera(); return; }
        EnsureCreditsForStart();
        var first = CharacterReferences.First(item => !item.IsUpload);
        SelectedMode = "charx";
        MarkSelected(first);
        string freePrompt = Prompt;
        var context = ReferenceContext(first);
        Prompt = context.Prompt; ReferenceImage = context.ReferencePath ?? ""; FaceRestoration = first.Mode == "clothx";
        try { await GenerateAsync(); }
        finally { Prompt = freePrompt; Changed(nameof(Prompt)); }
    }
    private void EnsureCreditsForStart()
    {
        try { generationAccess?.EnsureSufficientCredits(); }
        catch (AccountException error) when (error.Code == CreditPolicy.InsufficientCode)
        {
            CreditsRequired?.Invoke();
            throw;
        }
    }
    private void RequireKey()
    { Error = generationAccess is not null ? "Choose or create an API key in your account menu before starting."
        : "API Key is required — click the key button in the top-right corner to enter it."; ApiKeyRequired?.Invoke(); }
    private void RequireCamera()
    {
        Error = Cameras.Count == 0 ? "No camera is available. Connect a camera and try again." : "Select a camera before starting. Choose your physical camera for live video.";
        CameraRequired?.Invoke();
    }
    private void BeginElapsed()
    {
        if (State != RealtimeConnectionState.Generating || elapsedTimer.IsEnabled) return;
        startedAt = DateTimeOffset.UtcNow;
        elapsedTimer.Start();
        Changed(nameof(Elapsed));
    }
    public void ClearError() => Error = "";
    private ObservableCollection<ReferenceItem> References(string mode) => mode switch
    {
        "charx" => CharacterReferences, "clothx" => ClothingReferences, "vibex" => StyleReferences, "dimx" => SummonReferences,
        _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, "This mode does not have a reference list.")
    };
    private IEnumerable<ReferenceItem> AllReferences => CharacterReferences.Concat(ClothingReferences).Concat(StyleReferences).Concat(SummonReferences).Concat(FreeReference is { } reference ? new[] { reference } : []);
    private void MarkSelected(ReferenceItem selected)
    { foreach (var item in AllReferences) item.IsSelected = item == selected; }
    private static string ModePrompt(string mode) => FaceNow.Core.Product.GenerationPrompts.ForMode(mode);
    internal GenerationContext ReferenceContext(ReferenceItem item) => new(
        item.Prompt ?? (item.Mode == "free" ? Prompt : ModePrompt(item.Mode)),
        item.ReferenceUrl);
    public async Task SelectReferenceAsync(ReferenceItem item)
    {
        if (item.IsUpload || item.IsUploading || !Active) return;
        ClearError();
        MarkSelected(item);
        if (item.Mode == "free" && item.Prompt is { } freePrompt) { Prompt = freePrompt; Changed(nameof(Prompt)); }
        if (IsPreview) return;
        if (string.IsNullOrWhiteSpace(ApiKey)) { RequireKey(); return; }
        await QueueConditionsAsync(ReferenceContext(item), faceRestoration: item.Mode == "clothx");
    }
    public async Task SubmitPromptAsync()
    {
        if (!FreeReferenceReady) return;
        if (IsPreview) return;
        if (string.IsNullOrWhiteSpace(ApiKey)) { RequireKey(); return; }
        if (string.IsNullOrWhiteSpace(Prompt)) throw new InvalidOperationException("Describe what you want to see first.");
        await QueueConditionsAsync(new(Prompt, FreeReference?.ReferenceUrl));
    }
    private bool FreeReferenceReady => FreeReference is null || !FreeReference.IsUploading && !FreeReference.HasError && FreeReference.ReferenceUrl.Length > 0;
    private bool CanSubmitPrompt() => !Busy && FreeReferenceReady;
    private Task QueueConditionsAsync(GenerationContext context, bool faceRestoration = false)
    {
        pendingConditions = (context, faceRestoration, ++intent, revision);
        if (updateTask is null || updateTask.IsCompleted) updateTask = ApplyConditionsAsync();
        return updateTask;
    }
    private async Task ApplyConditionsAsync()
    {
        while (pendingConditions is { } pending)
        {
            pendingConditions = null;
            var current = session;
            if (current is null || pending.Revision != revision) continue;
            try
            {
                await GenerateOnStreamAsync(current, pending.Context, pending.FaceRestoration, pending.Revision);
            }
            catch (Exception failure) when (pending.Revision == revision)
            {
                if (pending.Intent == intent || IsCreditFailure(failure)) HandleGenerationFailure(failure);
            }
            catch (Exception) when (pending.Revision != revision || pending.Intent != intent) { }
        }
    }
    public async Task UploadReferenceAsync(string path, ReferenceItem? existing = null)
    {
        if (existing?.IsUploading == true) return;
        string mode = existing?.Mode ?? SelectedMode;
        if (IsPreview) { Error = "Reference uploads require a live session."; return; }
        if (string.IsNullOrWhiteSpace(ApiKey)) { RequireKey(); return; }
        var item = existing ?? ReferenceItem.FromUpload(path, mode, Prompt);
        long uploadIntent = ++intent;
        pendingConditions = null;
        item.UploadProgress = null; item.IsUploading = true; item.HasError = false;
        if (existing is null)
        {
            if (mode == "free") FreeReference = item;
            else References(mode).Insert(1, item);
        }
        var cancellation = new CancellationTokenSource();
        uploadCancellations.Add(item, cancellation);
        int current = revision;
        try
        {
            try { item.Thumbnail = await thumbnails.LoadAsync(path); } catch (Exception) { /* uploads can still accept encoded WebP without a local codec */ }
            using var client = new XmaxClient(new() { ApiKey = sessionKey, Environment = ServiceEnvironment });
            await using var storage = client.CreateStorage();
            var progress = new Progress<TransferProgress>(value =>
            {
                if (item.IsUploading && !cancellation.IsCancellationRequested && value.Total > 0)
                    item.UploadProgress = Math.Clamp((double)value.Completed / value.Total, 0, 1);
            });
            var uploaded = await storage.UploadImageWithSafetyCheckAsync(
                path, progress: progress, cancellationToken: cancellation.Token);
            item.ReferenceUrl = uploaded.Url; item.UploadProgress = 1; item.IsUploading = false;
            if (current == revision && uploadIntent == intent && mode == SelectedMode && (mode != "free" || FreeReference == item)) await SelectReferenceAsync(item);
        }
        catch (OperationCanceledException) { item.IsUploading = false; item.HasError = true; item.Error = "Upload canceled — click to retry."; }
        catch (Exception failure)
        {
            item.IsUploading = false; item.HasError = true; item.Error = failure.Message;
            if (current == revision && uploadIntent == intent) ReportError(failure);
        }
        finally { uploadCancellations.Remove(item); cancellation.Dispose(); }
    }
    public void RemoveFreeReference()
    {
        if (FreeReference is { } item && uploadCancellations.TryGetValue(item, out var cancellation)) cancellation.Cancel();
        FreeReference = null;
        ++intent; pendingConditions = null;
    }
}
