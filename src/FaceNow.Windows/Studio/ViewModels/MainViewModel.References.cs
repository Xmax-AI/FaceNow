//
//  MainViewModel.References.cs
//  FaceNow
//

using System.Collections.ObjectModel;
using Xmax.SDK;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private string selectedMode = "charx";
    private long intent;
    private (GenerationContext Context, bool FaceRestoration, long Intent, int Revision)? pendingConditions;
    private Task? updateTask;
    private readonly Dictionary<ReferenceItem, CancellationTokenSource> uploadCancellations = [];

    public string SelectedMode
    {
        get => selectedMode;
        set
        {
            if (selectedMode == value)
                return;
            selectedMode = value;
            ++intent;
            pendingConditions = null;
            ClearError();
            Changed();
        }
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
            if (freeReference is not null)
                freeReference.PropertyChanged -= FreeReferenceChanged;
            freeReference = value;
            if (value is not null)
                value.PropertyChanged += FreeReferenceChanged;
            Changed();
            Changed(nameof(HasFreeReference));
            SubmitPromptCommand?.Refresh();
        }
    }

    public bool HasFreeReference => FreeReference is not null;

    private void FreeReferenceChanged(
        object? sender,
        System.ComponentModel.PropertyChangedEventArgs e
    )
    {
        Changed(nameof(FreeReference));
        SubmitPromptCommand.Refresh();
    }

    internal Task WaitForConditionsAsync() => updateTask ?? Task.CompletedTask;

    private ObservableCollection<ReferenceItem> References(
        string mode
    ) => mode switch
    {
        "charx" => CharacterReferences,
        "clothx" => ClothingReferences,
        "vibex" => StyleReferences,
        "dimx" => SummonReferences,
        _ => throw new ArgumentOutOfRangeException(
            nameof(mode),
            mode,
            "This mode does not have a reference list."
        )
    };

    private IEnumerable<ReferenceItem> AllReferences => CharacterReferences.Concat(ClothingReferences).Concat(StyleReferences).Concat(SummonReferences).Concat(FreeReference is { } reference ? new[] { reference } : []);

    private void MarkSelected(
        ReferenceItem selected
    )
    {
        foreach (var item in AllReferences)
            item.IsSelected = item == selected;
    }

    private static string ModePrompt(
        string mode
    ) => FaceNow.Core.Product.GenerationPrompts.ForMode(mode);

    internal GenerationContext ReferenceContext(
        ReferenceItem item
    ) => new(
        item.Prompt ?? (item.Mode == "free" ? Prompt : ModePrompt(item.Mode)),
        item.ReferenceUrl);

    public async Task SelectReferenceAsync(
        ReferenceItem item
    )
    {
        if (item.IsUpload || item.IsUploading || !Active)
            return;
        ClearError();
        MarkSelected(item);
        if (item.Mode == "free" && item.Prompt is { } freePrompt)
        {
            Prompt = freePrompt;
            Changed(nameof(Prompt));
        }
        if (IsPreview)
            return;
        if (string.IsNullOrWhiteSpace(ApiKey))
        {
            RequireKey();
            return;
        }
        await QueueConditionsAsync(ReferenceContext(item), faceRestoration: item.Mode == "clothx");
    }

    public async Task SubmitPromptAsync()
    {
        if (!FreeReferenceReady)
            return;
        if (IsPreview)
            return;
        if (string.IsNullOrWhiteSpace(ApiKey))
        {
            RequireKey();
            return;
        }
        if (string.IsNullOrWhiteSpace(Prompt))
            throw new InvalidOperationException("Describe what you want to see first.");
        await QueueConditionsAsync(new(Prompt, FreeReference?.ReferenceUrl));
    }

    private bool FreeReferenceReady => FreeReference is null || !FreeReference.IsUploading && !FreeReference.HasError && FreeReference.ReferenceUrl.Length > 0;

    private bool CanSubmitPrompt() => !Busy && FreeReferenceReady;

    private Task QueueConditionsAsync(
        GenerationContext context,
        bool faceRestoration = false
    )
    {
        pendingConditions = (context, faceRestoration, ++intent, revision);
        if (updateTask is null || updateTask.IsCompleted)
            updateTask = ApplyConditionsAsync();
        return updateTask;
    }

    private async Task ApplyConditionsAsync()
    {
        while (pendingConditions is { } pending)
        {
            pendingConditions = null;
            var current = session;
            if (current is null || pending.Revision != revision)
                continue;
            try
            {
                await GenerateOnStreamAsync(
                    current,
                    pending.Context,
                    pending.FaceRestoration,
                    pending.Revision
                );
            }
            catch (Exception failure) when (pending.Revision == revision)
            {
                if (pending.Intent == intent || IsCreditFailure(failure))
                    HandleGenerationFailure(failure);
            }
            catch (Exception) when (pending.Revision != revision || pending.Intent != intent) { }
        }
    }

    public async Task UploadReferenceAsync(
        string path,
        ReferenceItem? existing = null
    )
    {
        if (existing?.IsUploading == true)
            return;
        string mode = existing?.Mode ?? SelectedMode;
        if (IsPreview)
        {
            Error = "Reference uploads require a live session.";
            return;
        }
        if (string.IsNullOrWhiteSpace(ApiKey))
        {
            RequireKey();
            return;
        }
        var item = existing ?? ReferenceItem.FromUpload(path, mode, Prompt);
        long uploadIntent = ++intent;
        pendingConditions = null;
        item.UploadProgress = null;
        item.IsUploading = true;
        item.HasError = false;
        if (existing is null)
        {
            if (mode == "free")
                FreeReference = item;
            else
                References(mode).Insert(1, item);
        }
        var cancellation = new CancellationTokenSource();
        uploadCancellations.Add(item, cancellation);
        int current = revision;
        try
        {
            item.ReferenceUrl = await UploadApprovedReferenceAsync(
                item,
                path,
                sessionKey,
                cancellation.Token
            );
            item.UploadProgress = 1;
            item.IsUploading = false;
            if (current == revision && uploadIntent == intent && mode == SelectedMode && (mode != "free" || FreeReference == item))
                await SelectReferenceAsync(item);
        }
        catch (OperationCanceledException)
        {
            item.IsUploading = false;
            item.HasError = true;
            item.Error = "Upload canceled — click to retry.";
        }
        catch (Exception failure)
        {
            item.IsUploading = false;
            item.HasError = true;
            item.Error = failure.Message;
            if (current == revision && uploadIntent == intent)
                ReportError(failure);
        }
        finally
        {
            uploadCancellations.Remove(item);
            cancellation.Dispose();
        }
    }

    private async Task<string> UploadApprovedReferenceAsync(
        ReferenceItem item,
        string path,
        string key,
        CancellationToken cancellation
    )
    {
        try
        {
            item.Thumbnail = await thumbnails.LoadAsync(path);
        }
        catch (Exception) { /* uploads can still accept encoded WebP without a local codec */ }
        cancellation.ThrowIfCancellationRequested();
        using var client = new XmaxClient(new()
        {
            ApiKey = key,
            Environment = ServiceEnvironment
        });
        await using var storage = client.CreateStorageManager();
        var progress = new Progress<TransferProgress>(value =>
        {
            if (item.IsUploading && !cancellation.IsCancellationRequested && value.Total > 0)
                item.UploadProgress = Math.Clamp((double)value.Completed / value.Total, 0, 1);
        });
        var uploaded = await storage.UploadImageWithSafetyCheckAsync(
            path,
            progress: progress,
            cancellationToken: cancellation
        );
        return uploaded.Url;
    }

    public void RemoveFreeReference()
    {
        if (FreeReference is { } item && uploadCancellations.TryGetValue(item, out var cancellation))
            cancellation.Cancel();
        FreeReference = null;
        ++intent;
        pendingConditions = null;
    }
}
