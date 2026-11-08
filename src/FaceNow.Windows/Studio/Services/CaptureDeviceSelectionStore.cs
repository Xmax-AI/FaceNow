// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.IO;
using System.Security;
using Microsoft.Win32;
using Xmax.SDK;

namespace FaceNow.Windows.Studio.Services;

internal static class CaptureDeviceSelectionStore
{
    private static string KeyPath => FaceNow.Core.Product.ProductProfile.Current.RegistryPath;
    private const string CameraId = "CameraId";
    private const string MicrophoneId = "MicrophoneId";

    internal static string? LoadCamera() => Load(CameraId);
    internal static void SaveCamera(string id) => Save(CameraId, id);

    // An empty value selects the system default. An absent value leaves the microphone off.
    internal static RealtimeMicrophone LoadMicrophone() => Load(MicrophoneId) switch
    {
        "" => RealtimeMicrophone.SystemDefault,
        string id when !string.IsNullOrWhiteSpace(id) => RealtimeMicrophone.Device(id),
        _ => RealtimeMicrophone.Disabled
    };

    internal static void SaveMicrophone(RealtimeMicrophone microphone) =>
        Save(MicrophoneId, microphone.IsEnabled ? microphone.DeviceId ?? "" : null);

    private static string? Load(string name)
    {
        try { using var key = Registry.CurrentUser.OpenSubKey(KeyPath); return key?.GetValue(name) as string; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException) { return null; }
    }
    private static void Save(string name, string? id)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
            if (id is null) key.DeleteValue(name, false);
            else key.SetValue(name, id);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException) { }
    }
}
