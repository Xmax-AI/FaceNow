//
//  check-sdk-abi.cs
//  FaceNow
//

using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;

var dll = Path.Combine(Path.GetFullPath(args[0]), "XmaxSDK.dll");
uint abi = uint.Parse(args[1], CultureInfo.InvariantCulture);
try
{
    // Resolve only the DLL in this payload and search its directory for native dependencies.
    nint module = Native.LoadLibraryEx(dll, 0, 0x100 | 0x1000);
    if (module == 0)
        throw new InvalidOperationException($"Cannot load {dll} and its dependencies (Win32 {Marshal.GetLastPInvokeError()}).");
    if (!NativeLibrary.TryGetExport(module, "xmax_realtime_create_local_camera_stream_with_options", out _))
        throw new InvalidOperationException("The SDK runtime does not support camera rotation. Rebuild with the matching released Xmax SDK packages.");
    NativeLibrary.SetDllImportResolver(typeof(Native).Assembly, (name, _, _) => name == "XmaxSDK.dll" ? module : 0);
    var config = new ClientConfig { Size = (uint)Marshal.SizeOf<ClientConfig>(), Abi = abi };
    int result = Native.Create(in config, out nint client);
    if (result != 0)
        throw new InvalidOperationException(Marshal.PtrToStringUTF8(Native.LastError()) ?? $"SDK error {result}.");
    Native.Destroy(client);
    Console.WriteLine($"Verified SDK C ABI {abi} in {dll}.");
    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine($"SDK C ABI {abi} check failed: {error.Message}");
    return 1;
}

[StructLayout(LayoutKind.Sequential, Pack = 8)]
struct ClientConfig
{
    public uint Size;
    public uint Abi;
    public nint ApiKey;
    public nint Model;
    public uint TimeoutMilliseconds;
}

static class Native
{
    [DllImport("kernel32.dll", EntryPoint = "LoadLibraryExW", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern nint LoadLibraryEx(string path, nint file, uint flags);

    [DllImport("XmaxSDK.dll", EntryPoint = "xmax_client_create", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int Create(in ClientConfig config, out nint client);

    [DllImport("XmaxSDK.dll", EntryPoint = "xmax_client_destroy", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void Destroy(nint client);

    [DllImport("XmaxSDK.dll", EntryPoint = "xmax_last_error", CallingConvention = CallingConvention.Cdecl)]
    internal static extern nint LastError();
}
