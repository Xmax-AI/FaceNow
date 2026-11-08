//
//  CameraProducerLease.cs
//  FaceNow
//

namespace FaceNow.Windows.VirtualCamera;

/// <summary>The two regional applications share one device and must not compete for its producer pipe.</summary>
internal static class CameraProducerLease
{
    internal static FileStream Acquire(
        string? directory = null
    )
    {
        directory ??= Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "XMAX.AI",
            "FaceNow",
            "Shared"
        );
        Directory.CreateDirectory(directory);
        try
        {
            return new(
                Path.Combine(
                directory,
                "producer.lock"
            ),
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.None
            );
        }
        catch (IOException error)
        {
            throw new InvalidOperationException(
                AppText.Get("Another FaceNow edition is using the virtual camera. Stop its session first."),
                error
            );
        }
    }
}
