//
//  MainViewModel.HomeReference.cs
//  FaceNow
//

using Xmax.SDK;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private CancellationTokenSource? homeReferenceUpload;
    private ReferenceItem? importedHomeReference;
    private ReferenceItem? pendingHomeReference;
    private readonly HashSet<ReferenceItem> homeSessionReferences = [];

    internal IReadOnlyList<ReferenceItem> HomeReferencePresets { get; private set; } = [];

    internal IReadOnlyList<ReferenceItem> HomeReferences { get; private set; } = [];

    internal ReferenceItem HomeSelectedReference { get; private set; } = null!;

    internal ReferenceItem? HomeCustomReference => pendingHomeReference ?? importedHomeReference;

    internal bool CanChooseHomeReference => !Active && !Busy && homeReferenceUpload is null;

    internal void SelectHomeReference(
        ReferenceItem item
    )
    {
        if (!CanChooseHomeReference || HomeSelectedReference == item || !HomeReferences.Contains(item))
            return;
        HomeSelectedReference = item;
        ClearError();
        HomeReferenceChanged();
    }

    internal void SelectHomeCatalogReference(
        ReferenceItem item
    )
    {
        if (!CanChooseHomeReference || item.IsUpload || item.LocalPath is not null || !AllReferences.Contains(item))
            return;
        if (!HomeReferences.Contains(item))
            HomeReferences = [item, ..HomeReferences];
        SelectHomeReference(item);
    }

    internal async Task UploadHomeReferenceAsync(
        string path
    )
    {
        if (!CanChooseHomeReference || IsPreview)
            return;
        if (string.IsNullOrWhiteSpace(ApiKey))
        {
            RequireKey();
            return;
        }
        string key = generationAccess?.GetVerifiedGenerationKey() ?? ApiKey;
        var item = ReferenceItem.FromUpload(path, "charx", "");
        using var cancellation = new CancellationTokenSource();
        homeReferenceUpload = cancellation;
        pendingHomeReference = item;
        var previousReferences = HomeReferences;
        HomeReferences = [item, ..previousReferences.Where(reference => reference != importedHomeReference)];
        item.IsUploading = true;
        ClearError();
        HomeReferenceChanged();
        try
        {
            item.ReferenceUrl = await UploadApprovedReferenceAsync(item, path, key, cancellation.Token);
            cancellation.Token.ThrowIfCancellationRequested();
            item.UploadProgress = 1;
            importedHomeReference = HomeSelectedReference = item;
        }
        catch (Exception failure)
        {
            if (!cancellation.IsCancellationRequested)
                ReportError(failure);
        }
        finally
        {
            item.IsUploading = false;
            if (homeReferenceUpload == cancellation)
            {
                homeReferenceUpload = null;
                pendingHomeReference = null;
                if (importedHomeReference != item)
                    HomeReferences = previousReferences;
                HomeReferenceChanged();
            }
        }
    }

    internal void ResetHomeReferences()
    {
        var original = HomeReferencePresets[0];
        if (HomeReferences == HomeReferencePresets &&
            homeSessionReferences.Count == 0 && HomeSelectedReference == original)
            return;

        var cancellation = homeReferenceUpload;
        homeReferenceUpload = null;
        pendingHomeReference = importedHomeReference = null;
        HomeReferences = HomeReferencePresets;
        HomeSelectedReference = original;
        cancellation?.Cancel();
        foreach (var item in homeSessionReferences)
            CharacterReferences.Remove(item);
        homeSessionReferences.Clear();
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
        if (item.LocalPath is not null && homeSessionReferences.Add(item))
            CharacterReferences.Insert(1, item);
        SelectedMode = item.Mode;
        MarkSelected(item);
    }
}
