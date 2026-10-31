// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.Text.Json;
using System.Reflection;
using FaceNow.Windows.Studio.ViewModels;

namespace FaceNow.Windows.Studio.Services;

internal static class ReferenceCatalog
{
    internal static IReadOnlyList<ReferenceItem> Load()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("FaceNow.presets.json")!;
        using var document = JsonDocument.Parse(stream);
        return document.RootElement.EnumerateArray().Select(item => new ReferenceItem
        {
            Id = item.GetProperty("id").GetString()!, Mode = item.GetProperty("mode").GetString()!,
            Name = AppText.Get(item.GetProperty("name").GetString()!), ThumbnailUrl = FaceNow.Core.Product.ProductProfile.Current.ResolveAsset(item.GetProperty("thumbnail").GetString()!),
            ReferenceUrl = FaceNow.Core.Product.ProductProfile.Current.ResolveAsset(item.GetProperty("reference").GetString()!)
        }).ToList();
    }
}
