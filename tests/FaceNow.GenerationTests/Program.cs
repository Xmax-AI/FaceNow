using FaceNow.Core.User;
using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.Studio.Platform;
using FaceNow.Windows.Studio.ViewModels;
using Xmax.SDK;

var tests = new (string Name, Func<Task> Run)[]
{
    ("macOS credit codes and legacy descriptions are recognized without false positives", () =>
    {
        foreach (int code in new[] { 43001, 46017 }) Check(GenerationFailure.IsInsufficientCredits(code, "Billing refused"));
        foreach (string message in new[] { "积分不足，请先充值", "账户余额不足", "积分已用完", "积分已耗尽", "余额已耗尽",
            "INSUFFICIENT_CREDITS", "insufficient_points", "Not enough credits", "Your balance is insufficient",
            "Out of credits", "No credits remaining", "Credits exhausted", "Your credits have run out" })
            Check(GenerationFailure.IsInsufficientCredits(null, message), message);
        foreach (string message in new[] { "Session expired", "Network connection lost", "Request timed out", "Insufficient storage",
            "Invalid API key", "Credit card payment declined", "Too many requests", "安全审核未通过", "网络连接已断开" })
            Check(!GenerationFailure.IsInsufficientCredits(503, message), message);
        return Task.CompletedTask;
    }),
    ("Heartbeat failure returns home immediately and blocks restart until cleanup finishes", async () =>
    {
        var output = new FakeOutput { Gate = new() }; var access = new FakeAccess();
        var model = ActiveModel(output, access); var receive = model.CreateSessionEventHandler();
        receive(Event(RealtimeEventType.State, reason: 2, code: -15, message: "Session heartbeat timed out"));
        Check(!model.Active && model.IsClosing && model.Busy && !model.CanEdit);
        Check(model.Error == "Session heartbeat timed out" && !model.StartCommand.CanExecute(null));
        await model.StartLandingAsync(); await model.GenerateAsync();
        Check(!model.Active && access.KeyReads == 0 && access.CreditChecks == 0);
        receive(Event(RealtimeEventType.State, state: RealtimeState.Generating));
        receive(Event(RealtimeEventType.Error, code: -4, message: "Late unrelated error"));
        Check(!model.Active && model.Error == "Session heartbeat timed out" && output.Stops == 1);
        Task cleanup = model.StopAsync(); output.Gate.SetResult(); await cleanup;
        Check(!model.IsClosing && !model.Busy && model.State == RealtimeState.Idle && model.Session is null);
        Check(model.LocalVideo is null && model.RemoteVideo is null && model.Error == "Session heartbeat timed out");
        Check(model.StartCommand.CanExecute(null));
    }),
    ("Both insufficient-credit business codes close generation without rejecting authentication or refreshing balance", async () =>
    {
        foreach (int apiCode in new[] { 43001, 46017 })
        {
            var output = new FakeOutput(); var access = new FakeAccess(); var model = ActiveModel(output, access);
            int rejected = 0; model.AuthenticationRejected += () => rejected++;
            model.CreateSessionEventHandler()(Event(RealtimeEventType.Error, code: -4, apiCode: apiCode, http: 403, message: "Billing refused"));
            Check(!model.Active && model.Error == CreditPolicy.InsufficientMessage && rejected == 0);
            Check(output.Stops == 1 && access.CreditChecks == 0 && access.KeyReads == 0 && access.HasVerifiedSession);
            await model.StopAsync();
        }
    }),
    ("SDK operation credit failures normalize the notice and end the session", async () =>
    {
        var output = new FakeOutput(); var model = ActiveModel(output);
        model.ReportError(new XmaxException(-15, "INSUFFICIENT_CREDITS"));
        Check(!model.Active && model.Error == CreditPolicy.InsufficientMessage && output.Stops == 1);
        await model.StopAsync();
    }),
    ("Transient and non-platform errors preserve generation", () =>
    {
        var output = new FakeOutput(); var model = ActiveModel(output); var receive = model.CreateSessionEventHandler();
        receive(Event(RealtimeEventType.Error, code: -4, message: "Request timed out"));
        Check(model.Active && output.Stops == 0 && model.Error == "Request timed out");
        model.ReportError(new XmaxException(-1, "Insufficient credits"));
        Check(model.Active && output.Stops == 0 && model.Error == "Insufficient credits");
        return Task.CompletedTask;
    }),
    ("Cleanup faults cannot overwrite the initiating error or leave restart disabled", async () =>
    {
        var output = new FakeOutput { StopFailure = new IOException("Output teardown failed") }; var model = ActiveModel(output);
        model.CreateSessionEventHandler()(Event(RealtimeEventType.State, reason: 2, code: -15, message: "Original session failure"));
        Check(!model.Active && model.Error == "Original session failure" && !model.Busy && !model.IsClosing);
        await model.StopAsync(); Check(model.Error == "Original session failure");
    }),
    ("Concurrent stops join a single cleanup and clear reference selection", async () =>
    {
        var output = new FakeOutput { Gate = new() }; var model = ActiveModel(output);
        Check(model.CharacterReferences.Any(item => item.IsSelected));
        Task first = model.StopAsync(), second = model.StopAsync();
        Check(ReferenceEquals(first, second) && output.Stops == 1);
        Check(!model.Active && model.IsClosing && !model.CharacterReferences.Any(item => item.IsSelected));
        output.Gate.SetResult(); await Task.WhenAll(first, second); Check(!model.Busy);
    }),
    ("An in-flight output startup is drained before restart is allowed", async () =>
    {
        var output = new FakeOutput(); var model = ActiveModel(output);
        var startup = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        // Substitute only the pending SDK operation; no real SDK session is created.
        typeof(MainViewModel).GetField("outputStartup", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!
            .SetValue(model, startup.Task);
        model.CreateSessionEventHandler()(Event(RealtimeEventType.State, reason: 2, code: -15, message: "Session ended"));
        Check(!model.Active && model.IsClosing && output.Stops == 1 && !model.StartCommand.CanExecute(null));
        Task cleanup = model.StopAsync(); startup.SetException(new IOException("Late output startup failed"));
        await cleanup; Check(!model.Busy && output.Stops == 2 && model.Error == "Session ended");
    }),
    ("State failure receives only its correlated follow-up error text", async () =>
    {
        var output = new FakeOutput { Gate = new() }; var model = ActiveModel(output); var receive = model.CreateSessionEventHandler();
        receive(Event(RealtimeEventType.State, reason: 2, code: -15, message: ""));
        Check(!model.Active && model.IsClosing && model.Error.Length > 0);
        receive(Event(RealtimeEventType.Error, code: -15, message: "Unrelated failure", session: "different-session"));
        Check(model.Error != "Unrelated failure");
        receive(Event(RealtimeEventType.Error, code: -15, message: "Heartbeat connection lost"));
        Check(model.Error == "Heartbeat connection lost" && !model.Active && output.Stops == 1);
        output.Gate.SetResult(); await model.StopAsync(); Check(model.Error == "Heartbeat connection lost");
    }),
    ("Legacy credit exhaustion in the follow-up error is normalized after returning home", async () =>
    {
        var output = new FakeOutput { Gate = new() }; var model = ActiveModel(output); var receive = model.CreateSessionEventHandler();
        receive(Event(RealtimeEventType.State, reason: 2, code: -15, message: ""));
        receive(Event(RealtimeEventType.Error, code: -15, message: "No credits remaining"));
        Check(!model.Active && model.Error == CreditPolicy.InsufficientMessage);
        output.Gate.SetResult(); await model.StopAsync();
    }),
    ("Dismissed terminal notices are not resurrected by their delayed detail event", async () =>
    {
        var output = new FakeOutput { Gate = new() }; var model = ActiveModel(output); var receive = model.CreateSessionEventHandler();
        receive(Event(RealtimeEventType.State, reason: 2, code: -15, message: "")); model.ClearError();
        receive(Event(RealtimeEventType.Error, code: -15, message: "Late detail"));
        Check(model.Error == ""); output.Gate.SetResult(); await model.StopAsync();
    }),
    ("A missing follow-up error cannot block teardown indefinitely", async () =>
    {
        var model = ActiveModel(new FakeOutput());
        model.CreateSessionEventHandler()(Event(RealtimeEventType.State, reason: 2, code: -15, message: ""));
        Check(!model.Active && model.IsClosing && model.Error.Length > 0);
        await model.StopAsync().WaitAsync(TimeSpan.FromSeconds(2));
        Check(!model.Busy && !model.IsClosing && model.Error.Length > 0);
    }),
    ("An old lifecycle cannot reactivate or terminate the next workspace", async () =>
    {
        var model = ActiveModel(new FakeOutput()); var old = model.CreateSessionEventHandler(); await model.StopAsync();
        model.ConfigurePreview(true); model.ClearError();
        old(Event(RealtimeEventType.State, reason: 2, code: -15, message: "Stale failure"));
        old(Event(RealtimeEventType.State, state: RealtimeState.Generating));
        Check(model.Active && model.Error == "");
        model.CreateSessionEventHandler()(Event(RealtimeEventType.Error, code: -4, message: "Current notice"));
        Check(model.Active && model.Error == "Current notice");
    }),
    ("Authentication uses the service ApiCode, never the SDK result field", () =>
    {
        var model = ActiveModel(new FakeOutput(), new FakeAccess()); int rejected = 0;
        model.AuthenticationRejected += () => rejected++;
        var receive = model.CreateSessionEventHandler();
        receive(Event(RealtimeEventType.Error, code: 46002, message: "SDK result is not a business code")); Check(rejected == 0);
        receive(Event(RealtimeEventType.Error, code: -4, apiCode: 46002, message: "Session expired")); Check(rejected == 1);
        return Task.CompletedTask;
    }),
};
int failed = 0;
foreach (var test in tests)
{
    try { await test.Run().WaitAsync(TimeSpan.FromSeconds(10)); Console.WriteLine("PASS " + test.Name); }
    catch (Exception error) { ++failed; Console.WriteLine("FAIL " + test.Name + ": " + error); }
}
Console.WriteLine($"{tests.Length - failed}/{tests.Length} generation tests passed; no camera, native SDK, account endpoint or cloud generation was used.");
return failed == 0 ? 0 : 1;

static void Check(bool value, string message = "Assertion failed") { if (!value) throw new Exception(message); }
static MainViewModel ActiveModel(FakeOutput output, IGenerationAccess? access = null)
{
    var model = new MainViewModel(new FakeDispatcher(), new FakeThumbnails(), output, access);
    model.ConfigurePreview(true);
    return model;
}
static RealtimeEvent Event(RealtimeEventType type, RealtimeState state = RealtimeState.Ready, int reason = 0,
    int code = 0, int apiCode = 0, int http = 0, string message = "", string session = "test-session") =>
    new(type, state, code, message, session, "test-task", reason, apiCode, http, 0, 0, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);

sealed class FakeOutput : IVirtualCameraOutput
{
    public TaskCompletionSource? Gate;
    public Exception? StopFailure;
    public int Stops;
    public CameraOutputStatus Status => new(CameraOutputState.Stopped, "Test", CameraRegistrationState.Registered);
    public Task StartAsync(OutputFormat format, CancellationToken cancellationToken = default) => throw new Exception("Tests must not start output.");
    public bool TrySubmit(OutputFrame frame) => throw new Exception("Tests must not submit pixels.");
    public Task StopAsync() { ++Stops; return StopFailure is not null ? Task.FromException(StopFailure) : Gate?.Task ?? Task.CompletedTask; }
    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
sealed class FakeAccess : IGenerationAccess
{
    public int KeyReads, CreditChecks;
    public bool HasVerifiedSession => true;
    public string GetVerifiedGenerationKey() { ++KeyReads; return "uk-isolated-test"; }
    public void EnsureSufficientCredits() { ++CreditChecks; }
}
sealed class FakeThumbnails : IThumbnailLoader
{
    public Task<object> LoadAsync(string source) => throw new Exception("Tests must not load images.");
}
sealed class FakeDispatcher : IUiDispatcher
{
    public void InvokeAsync(Action action) => action();
    public IUiTimer CreateTimer(TimeSpan interval) => new FakeTimer();
}
sealed class FakeTimer : IUiTimer
{
    public bool IsEnabled { get; private set; }
    public event EventHandler? Tick;
    public void Start() => IsEnabled = true;
    public void Stop() => IsEnabled = false;
    public void Pulse() => Tick?.Invoke(this, EventArgs.Empty);
}
