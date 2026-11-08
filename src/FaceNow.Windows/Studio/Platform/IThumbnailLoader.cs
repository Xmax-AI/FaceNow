//
//  IThumbnailLoader.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
namespace FaceNow.Windows.Studio.Platform;

internal interface IThumbnailLoader
{
    Task<object> LoadAsync(
        string source
    );
}
