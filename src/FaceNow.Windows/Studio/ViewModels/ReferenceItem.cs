// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.ComponentModel;
using System.Runtime.CompilerServices;
using FaceNow.Core.Product;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed class ReferenceItem : INotifyPropertyChanged
{
    public string Id { get; init; } = "";
    public string Mode { get; init; } = "charx";
    public string Name { get; init; } = "";
    public string ThumbnailUrl { get; init; } = "";
    public string ReferenceUrl { get; set; } = "";
    public string? Prompt { get; init; }
    public bool IsPromptOnly => !IsUpload && LocalPath is null && ThumbnailUrl.Length == 0 && ReferenceUrl.Length == 0 && !string.IsNullOrWhiteSpace(Prompt);
    public string? LocalPath { get; init; }
    public bool IsUpload { get; init; }
    internal static ReferenceItem FromUpload(string path, string mode, string freePrompt, ProductProfile? profile = null) => new()
    {
        Id = Guid.NewGuid().ToString("N"), Name = Path.GetFileName(path), Mode = mode, ThumbnailUrl = path, LocalPath = path,
        Prompt = mode == "free" ? freePrompt : GenerationPrompts.ForMode(mode, profile)
    };
    private bool selected, loading, failed, uploading;
    private object? thumbnail;
    private double? uploadProgress;
    private string error = "";
    public bool IsSelected { get => selected; set { if (selected == value) return; selected = value; Changed(); } }
    public bool IsLoading { get => loading; set { loading = value; Changed(); } }
    public bool HasError { get => failed; set { failed = value; Changed(); } }
    public bool IsUploading { get => uploading; set { uploading = value; Changed(); } }
    public double? UploadProgress { get => uploadProgress; set { if (uploadProgress == value) return; uploadProgress = value; Changed(); } }
    public string Error { get => error; set { error = value; Changed(); } }
    public object? Thumbnail { get => thumbnail; set { thumbnail = value; Changed(); } }
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Changed([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
