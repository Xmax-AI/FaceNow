//
//  ReferenceCatalog.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.Text.Json;
using System.Reflection;
using FaceNow.Windows.Studio.ViewModels;
using FaceNow.Core.Product;

namespace FaceNow.Windows.Studio.Services;

internal static class ReferenceCatalog
{
    internal static IReadOnlyList<ReferenceItem> Load(
        ProductProfile? profile = null
    )
    {
        profile ??= ProductProfile.Current;
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("FaceNow.presets.json")!;
        using var document = JsonDocument.Parse(stream);
        string Asset(
            string path
        ) => path.Length == 0 ? "" : new Uri(profile.AssetOrigin, path).AbsoluteUri;
        return document.RootElement.EnumerateArray().Select(item =>
        {
            string reference = Asset(item.GetProperty("reference").GetString()!);
            return new ReferenceItem
            {
                Id = item.TryGetProperty("id", out var id) ? id.GetString()! : reference,
                Mode = item.GetProperty("mode").GetString()!,
                Name = item.GetProperty(profile.IsOverseas ? "name" : "nameZh").GetString()!,
                ThumbnailUrl = Asset(item.GetProperty("thumbnail").GetString()!),
                ReferenceUrl = reference,
                Prompt = item.GetProperty(profile.IsOverseas ? "promptEn" : "prompt").GetString()!
            };
        }).ToList();
    }
}
