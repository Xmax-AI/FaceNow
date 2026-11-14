//
//  MainViewModel.Lifecycle.cs
//  FaceNow
//

using FaceNow.Core.User;
using FaceNow.Windows.VirtualCamera;
using Xmax.SDK;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private RealtimeConnectionState connectionState;

    public RealtimeConnectionState State
    {
        get => connectionState;
        private set
        {
            if (connectionState == value)
                return;
            connectionState = value;
            Changed();
            Changed(nameof(RemoteReady));
            Changed(nameof(ResultPlaceholder));
        }
    }

    public bool RemoteReady => State == RealtimeConnectionState.Generating;

    // Each subscription belongs to one lifecycle, including work already queued on the UI thread.
    internal Action<RealtimeState> CreateSessionStateHandler()
    {
        int current = revision;
        return state =>
        {
            if (current == revision)
                ReceiveState(state);
        };
    }

    private void ReceiveState(
        RealtimeState snapshot
    )
    {
        State = snapshot.ConnectionState;
        if (snapshot.Reason is RealtimeReason.Failure failure)
        {
            var error = failure.Error;
            CameraDiagnostics.Write($"RTC terminal error code={error.Result} API={error.ApiCode} HTTP={error.HttpStatus}");
            HandleGenerationFailure(error, endsSession: true);
            return;
        }

        if (State == RealtimeConnectionState.Idle)
        {
            localStream = null;
            LocalVideo = null;
        }
        if (State is RealtimeConnectionState.Idle or RealtimeConnectionState.Disconnecting)
            RemoteVideo = null;
        CameraDiagnostics.Write($"RTC state={State}");
        if (!Active && State is RealtimeConnectionState.Connected or RealtimeConnectionState.Generating)
            Active = true;
        if (State == RealtimeConnectionState.Generating)
            BeginElapsed();
        Status = State switch
        {
            RealtimeConnectionState.Preparing => "正在准备摄像头…",
            RealtimeConnectionState.Ready => "摄像头已就绪 · 本地预览中",
            RealtimeConnectionState.Connecting => "正在连接服务…",
            RealtimeConnectionState.Connected => "正在等待首张结果帧…",
            RealtimeConnectionState.Generating => "实时生成中",
            _ => AppText.Format("Status: {0}", AppText.Get(State.ToString()))
        };
    }

    private static bool IsCreditFailure(
        Exception failure
    ) => failure switch
    {
        // Read billing error details from platform API and session failures.
        XmaxException sdk when sdk.Code is XmaxErrorCode.ApiError or XmaxErrorCode.SessionError => GenerationFailure.IsInsufficientCredits(
            sdk.ApiCode,
            sdk.Message
        ),
        AccountException account => account.Code == CreditPolicy.InsufficientCode,
        _ => false
    };

    private void HandleGenerationFailure(
        Exception failure,
        bool endsSession = false
    )
    {
        if (IsClosing)
            return; // Cleanup failures and duplicate SDK reports must not replace the initiating error.
        bool insufficient = IsCreditFailure(failure);
        Error = insufficient ? CreditPolicy.InsufficientMessage : GenerationErrorMessage(failure);
        if (endsSession || insufficient)
            _ = StopAsync();
        // Credit failures are not authentication failures, even if the service returns HTTP 403.
        NotifyAuthenticationFailure(failure, insufficient);
    }

    private static string GenerationErrorMessage(
        Exception failure
    ) => failure is XmaxException { Code: XmaxErrorCode.UnsafeImage }
        ? "This reference image did not pass the safety check. Choose a different image."
        : failure.Message;

    private void NotifyAuthenticationFailure(
        Exception failure,
        bool insufficient
    )
    {
        if (!insufficient && generationAccess is not null && failure is XmaxException sdk
            && (sdk.HttpStatus is 401 or 403 || sdk.ApiCode == 46002))
            AuthenticationRejected?.Invoke();
    }

    /// <summary>Returns home immediately; all callers join one cleanup task before another session can start.</summary>
    public Task StopAsync()
    {
        if (IsClosing)
            return cleanup;
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        cleanup = completion.Task;
        closingSession = true;
        ++revision;
        pendingConditions = null;
        ++intent;
        var previous = session;
        session = null;
        localStream = null;
        var previousPump = cameraPump;
        cameraPump = null;
        var previousOutputStartup = outputStartup;
        outputStartup = null;
        var cancellation = operationCancellation;
        operationCancellation = null;
        Active = false;
        elapsedTimer.Stop();
        startedAt = null;
        Changed(nameof(Elapsed));
        foreach (var upload in uploadCancellations.Values.ToArray())
        {
            try
            {
                upload.Cancel();
            }
            catch (Exception failure)
            {
                ReportCleanupFailure(failure);
            }
        }
        foreach (var reference in AllReferences)
            reference.IsSelected = false;
        Status = "正在关闭会话…";
        RefreshBusy();
        _ = CompleteStopAsync(previous, previousPump, previousOutputStartup, cancellation, completion);
        return completion.Task;
    }

    private async Task CompleteStopAsync(
        IXmaxRealtimeManaging? previous,
        RemoteCameraPump? previousPump,
        Task? previousOutputStartup,
        CancellationTokenSource? cancellation,
        TaskCompletionSource completion
    )
    {
        async Task StopOutputAsync()
        {
            try
            {
                if (previousPump is not null)
                    await previousPump.DisposeAsync();
                else if (cameraOutput is not null)
                    await cameraOutput.StopAsync();
            }
            catch (Exception failure)
            {
                ReportCleanupFailure(failure);
            }
            if (previousOutputStartup is not null)
            {
                // A late startup observes the invalidated revision and disposes its pump.
                // Join it before allowing a new session to reuse the output transport.
                try
                {
                    await previousOutputStartup;
                }
                catch (Exception failure)
                {
                    ReportCleanupFailure(failure);
                }
                try
                {
                    if (cameraOutput is not null)
                        await cameraOutput.StopAsync();
                }
                catch (Exception failure)
                {
                    ReportCleanupFailure(failure);
                }
            }
        }
        async Task StopMediaAsync()
        {
            try
            {
                if (cancellation is not null)
                    await cancellation.CancelAsync();
            }
            catch (Exception failure)
            {
                ReportCleanupFailure(failure);
            }
            try
            {
                if (previous is not null)
                    await CloseRealtimeAsync(previous);
            }
            catch (Exception failure)
            {
                ReportCleanupFailure(failure);
            }
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
            foreach (var row in TimingRows.Concat(UplinkRows).Concat(UplinkNetworkRows).Concat(DownlinkRows).Concat(DownlinkNetworkRows))
                row.Value = "—";
            Metrics = "等待视频统计";
            Status = "会话已关闭";
            closingSession = false;
            completion.TrySetResult();
            RefreshBusy();
        }
    }

    private async Task CloseRealtimeAsync(
        IXmaxRealtimeManaging previous
    )
    {
        var idle = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        int closingRevision = revision;
        try
        {
            await previous.SetMicrophoneLevelListenerAsync(null);
            await previous.SetStateListenerAsync(snapshot =>
            {
                if (revision != closingRevision || idle.Task.IsCompleted)
                    return;
                if (snapshot.ConnectionState == RealtimeConnectionState.Disconnecting)
                    State = snapshot.ConnectionState;
                if (snapshot.ConnectionState == RealtimeConnectionState.Idle)
                {
                    State = snapshot.ConnectionState;
                    idle.TrySetResult();
                }
            });
            await previous.CloseAsync();
            await idle.Task.WaitAsync(TimeSpan.FromSeconds(5));
        }
        finally
        {
            await previous.DisposeAsync();
        }
    }

    private void ReportCleanupFailure(
        Exception failure
    )
    {
        CameraDiagnostics.Error("Session cleanup failed", failure);
        if (Error.Length == 0)
            Error = failure.Message;
    }
}
