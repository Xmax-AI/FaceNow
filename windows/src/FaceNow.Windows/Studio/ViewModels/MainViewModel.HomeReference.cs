//
//  MainViewModel.HomeReference.cs
//  FaceNow
//

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private CancellationTokenSource? homeReferenceUpload;
    private ReferenceItem? pendingHomeReference;
    private readonly HashSet<ReferenceItem> homeSessionReferences = [];

    internal IReadOnlyList<ReferenceItem> HomeReferencePresets { get; private set; } = [];

    internal IReadOnlyList<ReferenceItem> HomeReferences { get; private set; } = [];

    internal ReferenceItem HomeSelectedReference { get; private set; } = null!;

    internal ReferenceItem? HomeCustomReference => pendingHomeReference;

    internal bool CanChooseHomeReference => !Active && !Busy && homeReferenceUpload is null;

    internal void SelectHomeReference(
        ReferenceItem item
    )
    {
        if (!CanChooseHomeReference || HomeSelectedReference == item || !HomeReferences.Contains(item))
            return;
        HomeSelectedReference = item;
        if (item.Mode == "free")
        {
            Prompt = item.Prompt ?? "";
            FreeReference = item.ReferenceUrl.Length > 0 ? item : null;
            Changed(nameof(Prompt));
        }
        ClearError();
        HomeReferenceChanged();
    }

    internal void SelectHomeCatalogReference(
        ReferenceItem item
    )
    {
        if (!CanChooseHomeReference || item.IsUpload || item.IsUploading ||
            (item.LocalPath is not null && item.ReferenceUrl.Length == 0) || !AllReferences.Contains(item))
            return;
        AddHomeReference(item);
    }

    private void AddHomeReference(
        ReferenceItem item
    )
    {
        if (!HomeReferences.Contains(item))
            HomeReferences = [item, ..HomeReferences];
        SelectHomeReference(item);
    }

    internal bool SelectHomeFreePrompt(
        string prompt
    )
    {
        if (!CanChooseHomeReference || string.IsNullOrWhiteSpace(prompt) || !FreeReferenceReady)
            return false;
        prompt = prompt.Trim();
        string referenceUrl = FreeReference?.ReferenceUrl ?? "";
        var item = HomeReferences.FirstOrDefault(reference =>
            reference.Mode == "free" && reference.Prompt == prompt && reference.ReferenceUrl == referenceUrl
        ) ?? new ReferenceItem
        {
            Id = Guid.NewGuid().ToString("N"),
            Mode = "free",
            Name = AppText.Get("Custom Prompt"),
            Prompt = prompt,
            ReferenceUrl = referenceUrl,
            ThumbnailUrl = FreeReference?.ThumbnailUrl ?? "",
            Thumbnail = FreeReference?.Thumbnail,
            LocalPath = FreeReference?.LocalPath
        };
        AddHomeReference(item);
        return true;
    }

    internal async Task<bool> UploadHomeReferenceAsync(
        string path,
        string mode = "charx",
        string freePrompt = ""
    )
    {
        if (!CanChooseHomeReference || IsPreview)
            return false;
        if (string.IsNullOrWhiteSpace(ApiKey))
        {
            RequireKey();
            return false;
        }
        var references = mode == "free" ? null : References(mode);
        string key = generationAccess?.GetVerifiedGenerationKey() ?? ApiKey;
        var item = ReferenceItem.FromUpload(path, mode, freePrompt);
        var previousFreeReference = FreeReference;
        using var cancellation = new CancellationTokenSource();
        homeReferenceUpload = cancellation;
        pendingHomeReference = item;
        item.IsUploading = true;
        if (mode == "free")
            FreeReference = item;
        else
        {
            homeSessionReferences.Add(item);
            references!.Insert(1, item);
        }
        ClearError();
        HomeReferenceChanged();
        bool uploaded = false;
        try
        {
            item.ReferenceUrl = await UploadApprovedReferenceAsync(item, path, key, cancellation.Token);
            cancellation.Token.ThrowIfCancellationRequested();
            item.UploadProgress = 1;
            uploaded = true;
        }
        catch (Exception failure)
        {
            if (!cancellation.IsCancellationRequested)
                ReportError(failure);
        }
        finally
        {
            item.IsUploading = false;
            if (!uploaded)
            {
                references?.Remove(item);
                homeSessionReferences.Remove(item);
            }
            if (homeReferenceUpload == cancellation)
            {
                homeReferenceUpload = null;
                pendingHomeReference = null;
                if (!uploaded && mode == "free")
                    FreeReference = previousFreeReference;
                if (uploaded && mode != "free")
                    AddHomeReference(item);
                HomeReferenceChanged();
            }
        }
        return uploaded;
    }

    internal void ResetHomeReferences()
    {
        var cancellation = homeReferenceUpload;
        homeReferenceUpload = null;
        pendingHomeReference = null;
        HomeReferences = HomeReferencePresets;
        HomeSelectedReference = HomeReferencePresets[0];
        cancellation?.Cancel();
        foreach (var item in homeSessionReferences)
            References(item.Mode).Remove(item);
        homeSessionReferences.Clear();
        RemoveFreeReference();
        HomeReferenceChanged();
    }

    private void HomeReferenceChanged()
    {
        Changed(nameof(HomeSelectedReference));
        StartCommand.Refresh();
    }

    private void ApplyHomeReference(
        ReferenceItem item
    )
    {
        if (item.Mode == "free")
        {
            FreeReference = item.ReferenceUrl.Length > 0 ? item : null;
            Prompt = item.Prompt ?? "";
            Changed(nameof(Prompt));
        }
        SelectedMode = item.Mode;
        MarkSelected(item);
    }
}
