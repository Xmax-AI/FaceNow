using Xmax.SDK;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private CancellationTokenSource? homeReferenceUpload;
    private ReferenceItem? importedHomeReference;
    private ReferenceItem? pendingHomeReference;
    private readonly HashSet<ReferenceItem> homeSessionReferences = [];

    internal IReadOnlyList<ReferenceItem> HomeReferencePresets { get; private set; } = [];
    internal ReferenceItem HomeSelectedReference { get; private set; } = null!;
    internal ReferenceItem? HomeCustomReference => pendingHomeReference ?? importedHomeReference;
    internal bool CanChooseHomeReference => !Active && !Busy && homeReferenceUpload is null;

    internal void SelectHomeReference(ReferenceItem item)
    {
        if (!CanChooseHomeReference || HomeSelectedReference == item ||
            (item != importedHomeReference && !HomeReferencePresets.Contains(item))) return;
        HomeSelectedReference = item;
        ClearError();
        HomeReferenceChanged();
    }

    internal async Task UploadHomeReferenceAsync(string path)
    {
        if (!CanChooseHomeReference || IsPreview) return;
        if (string.IsNullOrWhiteSpace(ApiKey)) { RequireKey(); return; }
        string key = generationAccess?.GetVerifiedGenerationKey() ?? ApiKey;
        var item = ReferenceItem.FromUpload(path, "charx", "");
        using var cancellation = new CancellationTokenSource();
        homeReferenceUpload = cancellation;
        pendingHomeReference = item;
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
            if (!cancellation.IsCancellationRequested) ReportError(failure);
        }
        finally
        {
            item.IsUploading = false;
            if (homeReferenceUpload == cancellation)
            {
                homeReferenceUpload = null;
                pendingHomeReference = null;
                HomeReferenceChanged();
            }
        }
    }

    internal void ResetHomeReferences()
    {
        var original = HomeReferencePresets[0];
        if (homeReferenceUpload is null && importedHomeReference is null &&
            homeSessionReferences.Count == 0 && HomeSelectedReference == original) return;

        var cancellation = homeReferenceUpload;
        homeReferenceUpload = null;
        pendingHomeReference = importedHomeReference = null;
        HomeSelectedReference = original;
        cancellation?.Cancel();
        foreach (var item in homeSessionReferences) CharacterReferences.Remove(item);
        homeSessionReferences.Clear();
        HomeReferenceChanged();
    }

    private void HomeReferenceChanged()
    {
        Changed(nameof(HomeSelectedReference));
        StartCommand.Refresh();
    }

    private void ApplyHomeReference(ReferenceItem item)
    {
        if (item.LocalPath is not null && homeSessionReferences.Add(item)) CharacterReferences.Insert(1, item);
        SelectedMode = "charx";
        MarkSelected(item);
    }
}
