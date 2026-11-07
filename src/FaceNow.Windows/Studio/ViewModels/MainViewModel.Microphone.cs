//
//  MainViewModel.Microphone.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using Xmax.SDK;
using FaceNow.Windows.VirtualCamera;
using FaceNow.Windows.VirtualMicrophone;
using FaceNow.Core.Product;
using Microsoft.Win32;
using System.Security;

namespace FaceNow.Windows.Studio.ViewModels;

internal enum VirtualMicrophoneState { Checking, NotInstalled, Pending, Disabled, Enabled, Failed }

internal sealed partial class MainViewModel
{
    public RealtimeMicrophone Microphone { get; private set; } = RealtimeMicrophone.Disabled;
    internal event Action<float?>? MicrophoneLevelChanged;
    private const string VirtualMicrophonePreference = "VirtualMicrophoneEnabled";
    private bool virtualMicrophoneEnabled, virtualMicrophoneFailed;
    private VbCableDeviceState? virtualMicrophoneDevice;
    private Task? virtualMicrophoneRefresh;
    internal string VirtualMicrophoneOutputName { get; private set; } = VbCablePlayback.OutputEndpointLabel;

    internal VirtualMicrophoneState VirtualMicrophoneStatus => virtualMicrophoneFailed ? VirtualMicrophoneState.Failed : virtualMicrophoneDevice switch
    {
        null => VirtualMicrophoneState.Checking,
        VbCableDeviceState.NotInstalled => VirtualMicrophoneState.NotInstalled,
        VbCableDeviceState.Pending => VirtualMicrophoneState.Pending,
        _ => virtualMicrophoneEnabled ? VirtualMicrophoneState.Enabled : VirtualMicrophoneState.Disabled
    };

    internal Task RefreshVirtualMicrophoneAsync(bool retry = false)
    {
        if (IsPreview) return Task.CompletedTask;
        if (retry) virtualMicrophoneFailed = false;
        return virtualMicrophoneRefresh is { IsCompleted: false } ? virtualMicrophoneRefresh
            : virtualMicrophoneRefresh = ReadVirtualMicrophoneAsync();
    }

    private async Task ReadVirtualMicrophoneAsync()
    {
        try
        {
            var (state, outputName) = await Task.Run(VbCablePlayback.GetDeviceStatus);
            virtualMicrophoneDevice = state;
            VirtualMicrophoneOutputName = outputName ?? VbCablePlayback.OutputEndpointLabel;
        }
        catch (Exception error)
        {
            CameraDiagnostics.Error("Could not check the virtual microphone device", error);
            virtualMicrophoneFailed = true;
        }
        Changed(nameof(VirtualMicrophoneStatus));
    }

    private void LoadVirtualMicrophonePreference()
    {
        try
        {
            using var settings = Registry.CurrentUser.OpenSubKey(ProductProfile.Current.RegistryPath);
            virtualMicrophoneEnabled = settings?.GetValue(VirtualMicrophonePreference) is 1;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException)
        { CameraDiagnostics.Error("Could not read the virtual microphone preference", error); }
    }

    internal void SetVirtualMicrophoneEnabled(bool enabled)
    {
        if (IsPreview || (enabled && virtualMicrophoneDevice != VbCableDeviceState.Ready)) return;
        virtualMicrophoneEnabled = enabled;
        try
        {
            using var settings = Registry.CurrentUser.CreateSubKey(ProductProfile.Current.RegistryPath);
            settings.SetValue(VirtualMicrophonePreference, enabled ? 1 : 0, RegistryValueKind.DWord);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException)
        { CameraDiagnostics.Error("Could not save the virtual microphone preference", error); }
        Changed(nameof(VirtualMicrophoneStatus));
    }

    private void ReportVirtualMicrophoneError(Exception error)
    {
        CameraDiagnostics.Error("Virtual microphone output failed", error);
        virtualMicrophoneFailed = true;
        SetVirtualMicrophoneEnabled(false);
        Error = AppText.Get("Virtual microphone output failed. Check that VB-CABLE is available.");
    }

    internal async Task<(IReadOnlyList<MicrophoneDevice> Devices, bool ShowSystemDefault)> ListMicrophonesAsync()
    {
        if (IsPreview) return ([], false);
        IReadOnlyList<MicrophoneDevice> devices;
        if (session is { } current)
            devices = await current.ListMicrophoneDevicesAsync();
        else
        {
            using var client = new XmaxClient();
            await using var probe = client.CreateRealtime(new() { Model = ServiceModel });
            devices = await probe.ListMicrophoneDevicesAsync();
        }

        // The meeting app consumes our cable output. Exclude it from FaceNow's own capture choices.
        string? cableOutputId = await Task.Run(VbCablePlayback.GetOutputEndpointId);
        var inputs = devices.Where(device => device.Id != cableOutputId).ToArray();
        bool showSystemDefault = !devices.Any(device => device.IsDefault && device.Id == cableOutputId);
        return (inputs, showSystemDefault);
    }

    internal Task SelectMicrophoneAsync(RealtimeMicrophone selection) => GuardAsync(async () =>
    {
        if (IsPreview || selection == Microphone) return;
        int currentRevision = revision;
        if (session is { } current)
        {
            if (selection.IsEnabled && (!Microphone.IsEnabled || Microphone.DeviceId != selection.DeviceId))
                await current.SwitchMicrophoneAsync(selection.DeviceId);
            if (Microphone.IsEnabled != selection.IsEnabled)
                await current.SetMicrophoneEnabledAsync(selection.IsEnabled);
            if (currentRevision != revision) return;
        }
        Microphone = selection;
        MicrophoneLevelChanged?.Invoke(null);
        Changed(nameof(Microphone));
    });
}
