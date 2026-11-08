//
//  VbCablePlayback.cs
//  FaceNow
//

using Microsoft.Win32;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace FaceNow.Windows.VirtualMicrophone;

internal enum VbCableDeviceState
{
    NotInstalled, Pending, Ready
}

internal sealed class VbCablePlayback : IDisposable
{
    internal const int SampleRate = 48000;
    internal const string OutputEndpointLabel = "CABLE Output";
    private const string AdapterName = "VB-Audio Virtual Cable";
    private readonly MMDevice device;
    private readonly WasapiOut player;
    private readonly BufferedWaveProvider buffer = new(new WaveFormat(SampleRate, 16, 1))
    {
        BufferDuration = TimeSpan.FromMilliseconds(120),
        ReadFully = true
    };

    internal static (VbCableDeviceState State, string? OutputName) GetDeviceStatus()
    {
        using var enumerator = new MMDeviceEnumerator();
        using var input = FindEndpoint(enumerator, DataFlow.Render, "CABLE Input");
        using var output = FindEndpoint(enumerator, DataFlow.Capture, OutputEndpointLabel);
        if (input is not null && output is not null)
            return (VbCableDeviceState.Ready, output.FriendlyName);
        using var driver = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\VBAudioVACMME");
        return (driver is null ? VbCableDeviceState.NotInstalled : VbCableDeviceState.Pending, null);
    }

    internal static string? GetOutputEndpointId()
    {
        using var enumerator = new MMDeviceEnumerator();
        using var output = FindEndpoint(enumerator, DataFlow.Capture, OutputEndpointLabel);
        return output?.ID;
    }

    private static MMDevice? FindEndpoint(
        MMDeviceEnumerator enumerator,
        DataFlow flow,
        string label
    )
    {
        foreach (var device in enumerator.EnumerateAudioEndPoints(flow, DeviceState.Active))
        {
            // Windows can rename the capture endpoint without changing its adapter or endpoint ID.
            if (flow == DataFlow.Capture && string.Equals(
                device.DeviceFriendlyName,
                AdapterName,
                StringComparison.OrdinalIgnoreCase
            ))
                return device;
            string name = device.FriendlyName;
            if (name.StartsWith(label + " (", StringComparison.OrdinalIgnoreCase) &&
                name.Contains(AdapterName, StringComparison.OrdinalIgnoreCase))
                return device;
            device.Dispose();
        }
        return null;
    }

    internal VbCablePlayback(
        Action<Exception> faulted
    )
    {
        using var enumerator = new MMDeviceEnumerator();
        device = FindEndpoint(
            enumerator,
            DataFlow.Render,
            "CABLE Input"
        ) ?? throw new InvalidOperationException("VB-CABLE is not available.");
        try
        {
            player = new(device, AudioClientShareMode.Shared, true, 40);
        }
        catch
        {
            device.Dispose();
            throw;
        }
        try
        {
            player.PlaybackStopped += (_, args) => { if (args.Exception is { } error) faulted(error); };
            player.Init(buffer);
            player.Play();
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    internal void Write(
        byte[] pcm,
        int count,
        bool discontinuous
    )
    {
        if (discontinuous || buffer.BufferedBytes + count > buffer.BufferLength)
            buffer.ClearBuffer();
        buffer.AddSamples(pcm, 0, count);
    }

    public void Dispose()
    {
        try
        {
            player.Dispose();
        }
        finally
        {
            buffer.ClearBuffer();
            device.Dispose();
        }
    }
}
