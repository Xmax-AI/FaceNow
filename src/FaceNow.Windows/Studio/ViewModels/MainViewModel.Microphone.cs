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
using FaceNow.Windows.Media;
using FaceNow.Core.Product;
using FaceNow.Windows.Studio.Services;
using Microsoft.Win32;
using System.Security;

namespace FaceNow.Windows.Studio.ViewModels;

internal enum VirtualMicrophoneState { Checking, NotInstalled, Pending, Disabled, Enabled, Failed }

internal sealed partial class MainViewModel
{
    public RealtimeMicrophone Microphone { get; private set; } = RealtimeMicrophone.Disabled;
    internal event Action<float?>? MicrophoneLevelChanged;
    private IReadOnlyList<MicrophoneDevice> microphoneDevices = [];
    internal string? SelectedMicrophoneName => microphoneDevices.FirstOrDefault(device =>
        string.Equals(device.Id, Microphone.DeviceId, StringComparison.OrdinalIgnoreCase))?.Name;
    private const string VirtualMicrophonePreference = "VirtualMicrophoneEnabled";
    private const string AudioSyncOffsetPreference = "AudioSyncOffsetMilliseconds";
    private bool virtualMicrophoneEnabled, virtualMicrophoneFailed;
    private VbCableDeviceState? virtualMicrophoneDevice;
    private Task? virtualMicrophoneRefresh;
    internal string VirtualMicrophoneOutputName { get; private set; } = VbCablePlayback.OutputEndpointLabel;
    internal int AudioSyncOffsetMilliseconds { get; private set; }

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

    private void LoadAudioOutputPreferences()
    {
        try
        {
            using var settings = Registry.CurrentUser.OpenSubKey(ProductProfile.Current.RegistryPath);
            virtualMicrophoneEnabled = settings?.GetValue(VirtualMicrophonePreference) is 1;
            if (settings?.GetValue(AudioSyncOffsetPreference) is int offset)
                AudioSyncOffsetMilliseconds = Math.Clamp(offset, -MeetingOutputTiming.OffsetLimit, MeetingOutputTiming.OffsetLimit);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException)
        { CameraDiagnostics.Error("Could not read audio output preferences", error); }
    }

    internal void SetAudioSyncOffsetMilliseconds(int offset)
    {
        offset = Math.Clamp(offset, -MeetingOutputTiming.OffsetLimit, MeetingOutputTiming.OffsetLimit);
        if (AudioSyncOffsetMilliseconds == offset) return;
        AudioSyncOffsetMilliseconds = offset;
        if (IsPreview) return;

        cameraPump?.SetAudioSyncOffset(offset);
        try
        {
            using var settings = Registry.CurrentUser.CreateSubKey(ProductProfile.Current.RegistryPath);
            settings.SetValue(AudioSyncOffsetPreference, offset, RegistryValueKind.DWord);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException)
        { CameraDiagnostics.Error("Could not save the audio sync offset", error); }
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

    private async Task RestoreMicrophoneSelectionAsync()
    {
        var saved = CaptureDeviceSelectionStore.LoadMicrophone();
        if (!saved.IsEnabled) return;

        try
        {
            var (devices, showSystemDefault) = await ListMicrophonesAsync();
            if (saved.DeviceId is { } id)
            {
                var device = devices.FirstOrDefault(item => string.Equals(item.Id, id, StringComparison.OrdinalIgnoreCase));
                if (device is null) return;
                saved = RealtimeMicrophone.Device(device.Id);
            }
            else if (!showSystemDefault || devices.Count == 0) return;

            Microphone = saved;
            Changed(nameof(Microphone));
        }
        catch (Exception error) { CameraDiagnostics.Error("Could not restore the saved microphone", error); }
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
        microphoneDevices = devices.Where(device => !string.Equals(device.Id, cableOutputId, StringComparison.OrdinalIgnoreCase)).ToArray();
        bool showSystemDefault = !devices.Any(device => device.IsDefault && string.Equals(device.Id, cableOutputId, StringComparison.OrdinalIgnoreCase));
        return (microphoneDevices, showSystemDefault);
    }

    internal Action<float?> CreateMicrophoneLevelHandler()
    {
        int current = revision;
        return level => dispatcher.InvokeAsync(() =>
        {
            if (current == revision && Active && Microphone.IsEnabled) MicrophoneLevelChanged?.Invoke(level);
        });
    }

    internal Task SelectMicrophoneAsync(RealtimeMicrophone selection) => GuardAsync(async () =>
    {
        bool changed = selection != Microphone;
        int currentRevision = revision;
        if (changed && !IsPreview && session is { } current)
        {
            if (selection.IsEnabled && (!Microphone.IsEnabled || Microphone.DeviceId != selection.DeviceId))
                await current.SwitchMicrophoneAsync(selection.DeviceId);
            if (Microphone.IsEnabled != selection.IsEnabled)
                await current.SetMicrophoneEnabledAsync(selection.IsEnabled);
            if (currentRevision != revision) return;
        }
        if (!IsPreview) CaptureDeviceSelectionStore.SaveMicrophone(selection);
        if (!changed) return;
        Microphone = selection;
        MicrophoneLevelChanged?.Invoke(null);
        Changed(nameof(Microphone));
    });
}
