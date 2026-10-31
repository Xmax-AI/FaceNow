using FaceNow.Core.User;
using FaceNow.Windows.VirtualCamera;
using Xmax.SDK;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private (int Revision, RealtimeEvent State, string VisibleMessage, TaskCompletionSource Completion)? pendingFailureDetails;
    private Task? terminalDetailDelivery;
    // Capture the lifecycle when binding the SDK, rather than trusting events queued before a stop.
    internal Action<RealtimeEvent> CreateSessionEventHandler()
    {
        int current = revision;
        return item =>
        {
            if (current == revision) Receive(item);
            else CompleteTerminalFailureDetails(current, item);
        };
    }

    private static XmaxException EventFailure(RealtimeEvent item) => new(item.Code,
        string.IsNullOrWhiteSpace(item.Message) ? "The generation session ended unexpectedly. Please try again." : item.Message,
        item.ApiCode, item.HttpStatus);

    private static bool IsCreditFailure(Exception failure) => failure switch
    {
        // XMAX_API_ERROR and XMAX_SESSION_ERROR are the platform failures recognized by macOS.
        XmaxException sdk when sdk.Result is -4 or -15 => GenerationFailure.IsInsufficientCredits(sdk.ApiCode, sdk.Message),
        AccountException account => account.Code == CreditPolicy.InsufficientCode,
        _ => false
    };

    private void HandleGenerationFailure(Exception failure, bool endsSession = false, bool notifyAuthentication = true)
    {
        if (IsClosing) return; // Cleanup failures and duplicate SDK reports must not replace the initiating error.
        bool insufficient = IsCreditFailure(failure);
        Error = insufficient ? CreditPolicy.InsufficientMessage : failure.Message;
        if (endsSession || insufficient) _ = StopAsync();
        // Credit failures are not authentication failures, even if the service returns HTTP 403.
        if (notifyAuthentication) NotifyAuthenticationFailure(failure, insufficient);
    }

    private void NotifyAuthenticationFailure(Exception failure, bool insufficient)
    {
        if (!insufficient && generationAccess is not null && failure is XmaxException sdk
            && (sdk.HttpStatus is 401 or 403 || sdk.ApiCode == 46002)) AuthenticationRejected?.Invoke();
    }

    private void ReceiveTerminalFailure(RealtimeEvent item)
    {
        int current = revision;
        bool needsDetails = item.Type == RealtimeEventType.State && string.IsNullOrWhiteSpace(item.Message);
        var details = needsDetails ? new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously) : null;
        terminalDetailDelivery = details?.Task;
        HandleGenerationFailure(EventFailure(item), endsSession: true, notifyAuthentication: !needsDetails);
        // SDK 1.1 emits the reason/code on State, then the full message on Error. Permit only
        // that same failure to finish its notice after cleanup invalidates the event receiver.
        if (details is not null) pendingFailureDetails = (current, item, Error, details);
    }

    private void CompleteTerminalFailureDetails(int current, RealtimeEvent item)
    {
        if (pendingFailureDetails is not { } pending || current != pending.Revision || revision != current + 1
            || item.Type != RealtimeEventType.Error || item.Code != pending.State.Code
            || item.ApiCode != pending.State.ApiCode || item.HttpStatus != pending.State.HttpStatus
            || item.SessionId != pending.State.SessionId) return;
        pendingFailureDetails = null;
        pending.Completion.TrySetResult();
        if (Error != pending.VisibleMessage) return; // A dismissal or newer notice is authoritative.
        var failure = EventFailure(item);
        bool insufficient = IsCreditFailure(failure);
        Error = insufficient ? CreditPolicy.InsufficientMessage : failure.Message;
        NotifyAuthenticationFailure(failure, insufficient);
    }

    /// <summary>Returns home immediately; all callers join one cleanup task before another session can start.</summary>
    public Task StopAsync()
    {
        if (IsClosing) return cleanup;
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        cleanup = completion.Task;
        closingSession = true;
        pendingFailureDetails = null;
        ++revision;
        pendingConditions = null;
        ++intent;
        var previous = session; session = null;
        var previousPump = cameraPump; cameraPump = null;
        var previousOutputStartup = outputStartup; outputStartup = null;
        var cancellation = operationCancellation; operationCancellation = null;
        var details = terminalDetailDelivery; terminalDetailDelivery = null;
        Active = false;
        RemoteReady = false;
        elapsedTimer.Stop();
        startedAt = null; Changed(nameof(Elapsed));
        foreach (var upload in uploadCancellations.Values.ToArray())
        {
            try { upload.Cancel(); }
            catch (Exception failure) { ReportCleanupFailure(failure); }
        }
        foreach (var reference in AllReferences) reference.IsSelected = false;
        Status = "正在关闭会话…";
        RefreshBusy();
        _ = CompleteStopAsync(previous, previousPump, previousOutputStartup, cancellation, details, completion);
        return completion.Task;
    }

    private async Task CompleteStopAsync(XmaxRealtime? previous, RemoteCameraPump? previousPump,
        Task? previousOutputStartup, CancellationTokenSource? cancellation, Task? details, TaskCompletionSource completion)
    {
        async Task StopOutputAsync()
        {
            try
            {
                if (previousPump is not null) await previousPump.DisposeAsync();
                else if (cameraOutput is not null) await cameraOutput.StopAsync();
            }
            catch (Exception failure) { ReportCleanupFailure(failure); }
            if (previousOutputStartup is not null)
            {
                // A late startup observes the invalidated revision and disposes its pump.
                // Join it before allowing a new session to reuse the output transport.
                try { await previousOutputStartup; }
                catch (Exception failure) { ReportCleanupFailure(failure); }
                try { if (cameraOutput is not null) await cameraOutput.StopAsync(); }
                catch (Exception failure) { ReportCleanupFailure(failure); }
            }
        }
        async Task StopMediaAsync()
        {
            try { if (cancellation is not null) await cancellation.CancelAsync(); }
            catch (Exception failure) { ReportCleanupFailure(failure); }
            // SDK polling runs every 25 ms. Give the correlated Error a bounded delivery
            // window before DisposeAsync cancels that poller; absent details never block teardown.
            if (details is not null)
            {
                try { await details.WaitAsync(TimeSpan.FromMilliseconds(100)); }
                catch (TimeoutException) { }
            }
            try { if (previous is not null) await previous.DisposeAsync(); }
            catch (Exception failure) { ReportCleanupFailure(failure); }
        }
        try
        {
            // A blocked virtual-camera pipe must not delay releasing physical capture and the cloud session.
            await Task.WhenAll(StopOutputAsync(), StopMediaAsync());
        }
        finally
        {
            cancellation?.Dispose();
            LocalVideo = RemoteVideo = null;
            sessionKey = sessionCamera = "";
            State = RealtimeState.Idle;
            foreach (var row in TimingRows.Concat(UplinkRows).Concat(UplinkNetworkRows).Concat(DownlinkRows).Concat(DownlinkNetworkRows)) row.Value = "—";
            Metrics = "等待视频统计";
            Status = "会话已关闭";
            closingSession = false;
            completion.TrySetResult();
            RefreshBusy();
        }
    }

    private void ReportCleanupFailure(Exception failure)
    {
        CameraDiagnostics.Error("Session cleanup failed", failure);
        if (Error.Length == 0) Error = failure.Message;
    }
}
