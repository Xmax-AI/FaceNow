// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.IO;
using System.Security;
using Microsoft.Win32;

namespace FaceNow.Windows.Studio.Services;

internal static class CameraSelectionStore
{
    private static string KeyPath => FaceNow.Core.Product.ProductProfile.Current.RegistryPath;
    internal static string? Load()
    {
        try { using var key = Registry.CurrentUser.OpenSubKey(KeyPath); return key?.GetValue("CameraId") as string; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException) { return null; }
    }
    internal static void Save(string? id)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
            if (id is null) key.DeleteValue("CameraId", false);
            else key.SetValue("CameraId", id);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException) { }
    }
}
