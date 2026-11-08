//
//  CameraDiagnostics.cs
//  FaceNow
//

using System.Globalization;
using System.Runtime.InteropServices;
using System.Xml.Linq;

namespace FaceNow.Windows.VirtualCamera;

// Local, bounded diagnostics for a remote user's output failure. Never record pixels,
// prompts, API keys, device identifiers or exception messages from the SDK.
internal static class CameraDiagnostics
{
    private static readonly object Gate = new();
    private static readonly string SourceSince = DateTime.UtcNow.AddSeconds(-5).ToString(
        "yyyy-MM-ddTHH:mm:ss.fffZ",
        CultureInfo.InvariantCulture
    );
    private static long lastSourceRecord;
    private static bool sourceReadFailureReported;

    [DllImport("wevtapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint EvtQuery(
        nint session,
        string path,
        string query,
        int flags
    );

    [DllImport("wevtapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EvtNext(
        nint query,
        int count,
        [Out] nint[] events,
        int timeout,
        int flags,
        out int returned
    );

    [DllImport("wevtapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EvtRender(
        nint context,
        nint value,
        int flags,
        int bytes,
        nint buffer,
        out int used,
        out int properties
    );

    [DllImport("wevtapi.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EvtClose(
        nint handle
    );

    internal static void ReadSourceEvents()
    {
        lock (Gate)
        {
            try
            {
                nint query = EvtQuery(
                    0,
                    "Application",
                    $"*[System[Provider[@Name='FaceNow.CameraSource'] and TimeCreated[@SystemTime>='{SourceSince}']]]",
                    0x201
                );
                if (query == 0)
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                try
                {
                    var events = new nint[32];
                    if (!EvtNext(query, events.Length, events, 0, 0, out int count))
                        return;
                    long newest = lastSourceRecord;
                    try
                    {
                        for (int i = 0; i < count; ++i)
                        {
                            EvtRender(0, events[i], 1, 0, 0, out int bytes, out _);
                            if (bytes <= 0 || bytes > 65536)
                                continue;
                            nint buffer = Marshal.AllocHGlobal(bytes);
                            try
                            {
                                if (!EvtRender(0, events[i], 1, bytes, buffer, out _, out _))
                                    continue;
                                var xml = XDocument.Parse(Marshal.PtrToStringUni(buffer)!);
                                XNamespace ns = "http://schemas.microsoft.com/win/2004/08/events/event";
                                long record = (long?)xml.Root?.Element(ns + "System")?.Element(ns + "EventRecordID") ?? 0;
                                if (record <= lastSourceRecord)
                                    continue;
                                newest = Math.Max(newest, record);
                                string? message = xml.Root?.Element(ns + "EventData")?.Element(ns + "Data")?.Value;
                                if (message is not null && message.Length <= 512 &&
                                    System.Text.RegularExpressions.Regex.IsMatch(
                                        message,
                                        @"^FaceNow source build=[0-9.]+ pid=[0-9]+ stage=[a-z-]+ code=0x[0-9A-F]+ pitch=-?[0-9]+ size=[0-9]+x[0-9]+ endpoint=(none|[0-9a-f]{16})$"
                                    ))
                                    Write(message);
                            }
                            finally
                            {
                                Marshal.FreeHGlobal(buffer);
                            }
                        }
                    }
                    finally
                    {
                        for (int i = 0; i < count; ++i)
                            if (events[i] != 0)
                                EvtClose(events[i]);
                    }
                    lastSourceRecord = newest;
                }
                finally
                {
                    EvtClose(query);
                }
            }
            catch (Exception failure)
            {
                if (!sourceReadFailureReported)
                {
                    sourceReadFailureReported = true;
                    Error("Native diagnostics read failed", failure);
                }
            }
        }
    }

    internal static void Write(
        string message
    )
    {
        try
        {
            lock (Gate)
            {
                string directory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "XMAX.AI",
                    FaceNow.Core.Product.ProductProfile.Current.Id,
                    "Logs"
                );
                Directory.CreateDirectory(directory);
                string path = Path.Combine(directory, "virtual-camera.log");
                if (File.Exists(path) && new FileInfo(path).Length > 1024 * 1024)
                    File.Move(path, path + ".previous", true);
                File.AppendAllText(
                    path,
                    DateTime.UtcNow.ToString(
                    "O",
                    CultureInfo.InvariantCulture
                ) + " " + message + Environment.NewLine
                );
            }
        }
        catch { /* Diagnostics must never interrupt playback. */ }
    }

    internal static void Error(
        string stage,
        Exception failure
    ) =>
        Write($"{stage}: {failure.GetType().Name} HRESULT=0x{failure.HResult:X8}");
}
