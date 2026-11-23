//
//  Program.cs
//  FaceNow
//

using FaceNow.Core.Localization;
using FaceNow.Core.User;
using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.Studio.Platform;
using FaceNow.Windows.Studio.ViewModels;
using Xmax.SDK;
using FaceNow.Core.Product;
using FaceNow.Windows.Studio.Services;

var tests = new (string Name, Func<Task> Run)[]
{
    ("The selected home appearance becomes the initial generation reference", async () =>
    {
        var model = new MainViewModel(new FakeDispatcher(), new FakeThumbnails());
        model.ConfigurePreview(false);
        Check(model.HomeSelectedReference == model.HomeReferencePresets[0] && model.HomeReferencePresets.All(item => !item.IsUpload));
        var appearance = model.HomeReferencePresets[4];
        model.SelectHomeReference(appearance);
        Check(model.HomeSelectedReference == appearance && !appearance.IsSelected);
        await model.StartLandingAsync();
        Check(model.Active && model.SelectedMode == "charx" && appearance.IsSelected && model.Session is null);
        await model.StopAsync();
        Check(model.HomeSelectedReference == appearance && !appearance.IsSelected);
        model.ResetHomeReferences();
        Check(model.HomeSelectedReference == model.HomeReferencePresets[0]);
    }),
    ("New catalog presets appear first at home and start in their own generation mode", async () =>
    {
        var model = new MainViewModel(new FakeDispatcher(), new FakeThumbnails());
        model.ConfigurePreview(false);
        var clothing = model.ClothingReferences.First(item => !item.IsUpload);
        var style = model.StyleReferences.First(item => !item.IsUpload);
        model.SelectHomeCatalogReference(clothing);
        model.SelectHomeCatalogReference(style);
        Check(model.HomeReferences.SequenceEqual(new[] { style, clothing }.Concat(model.HomeReferencePresets)));
        model.SelectHomeCatalogReference(clothing);
        Check(model.HomeSelectedReference == clothing && model.HomeReferences[1] == clothing &&
            model.HomeReferences.Count == model.HomeReferencePresets.Count + 2);
        await model.StartLandingAsync();
        Check(model.Active && model.SelectedMode == "clothx" && clothing.IsSelected && !style.IsSelected);
        await model.StopAsync();
        Check(model.HomeSelectedReference == clothing && model.HomeReferences[1] == clothing);
        model.ResetHomeReferences();
        Check(model.HomeReferences.SequenceEqual(model.HomeReferencePresets) &&
            model.HomeSelectedReference == model.HomeReferencePresets[0]);
    }),
    ("Reset cancels pending home uploads before SDK approval and unblocks Start", async () =>
    {
        var thumbnails = new PendingThumbnails();
        var model = new MainViewModel(new FakeDispatcher(), thumbnails) { ApiKey = "isolated-test-key" };
        var appearance = model.HomeReferencePresets[4];
        model.SelectHomeReference(appearance);
        var upload = model.UploadHomeReferenceAsync("test-image.png");
        Check(model.HomeCustomReference is { IsUploading: true } && model.HomeSelectedReference == appearance);
        Check(!model.StartCommand.CanExecute(null));
        model.SelectHomeReference(model.HomeReferencePresets[1]);
        await model.StartLandingAsync();
        Check(model.HomeSelectedReference == appearance && !model.Active);
        model.ResetHomeReferences();
        thumbnails.Result.SetResult(new object());
        await upload;
        Check(model.HomeCustomReference is null && model.HomeSelectedReference == model.HomeReferencePresets[0]);
        Check(model.StartCommand.CanExecute(null) && model.Error.Length == 0);
    }),
    ("Home uploads keep their mode and prompt and are canceled by account reset", async () =>
    {
        foreach (string mode in new[] { "charx", "clothx", "vibex", "dimx", "free" })
        {
            var thumbnails = new PendingThumbnails();
            var model = new MainViewModel(new FakeDispatcher(), thumbnails) { ApiKey = "isolated-test-key" };
            const string freePrompt = "Keep my exact instruction / 保留用户输入";
            var upload = model.UploadHomeReferenceAsync("test-image.png", mode, freePrompt);
            var item = model.HomeCustomReference!;
            Check(item.Mode == mode && item.Prompt == (mode == "free" ? freePrompt : GenerationPrompts.ForMode(mode)));
            Check(mode == "free" ? model.FreeReference == item : model.References(mode)[1] == item);
            Check(!model.CanChooseHomeReference && !model.SelectHomeFreePrompt("still uploading"));
            model.ResetHomeReferences();
            thumbnails.Result.SetResult(new object());
            Check(!await upload && model.HomeCustomReference is null && model.FreeReference is null);
            Check(model.HomeReferences.Count == 5 && model.CanChooseHomeReference && model.Error.Length == 0);
            if (mode != "free")
                Check(!model.References(mode).Contains(item));
        }
    }),
    ("A home free prompt preserves its text and optional image through generation and reopening", async () =>
    {
        var model = new MainViewModel(new FakeDispatcher(), new FakeThumbnails());
        model.ConfigurePreview(false);
        Check(!model.SelectHomeFreePrompt("  "));
        const string prompt = "A custom watercolor scene / 自定义水彩场景";
        var image = ReferenceItem.FromUpload("approved-image.png", "free", "an earlier draft");
        image.ReferenceUrl = "https://example.invalid/approved.png";
        typeof(MainViewModel).GetProperty(nameof(MainViewModel.FreeReference))!.SetValue(model, image);
        Check(model.SelectHomeFreePrompt(prompt));
        var saved = model.HomeSelectedReference;
        Check(model.HomeReferences[0] == saved && saved.Mode == "free" &&
            model.ReferenceContext(saved).Prompt == prompt && saved.ReferenceUrl == image.ReferenceUrl);
        model.Prompt = "A later draft";
        await model.StartLandingAsync();
        Check(model.Active && model.SelectedMode == "free" && model.Prompt == prompt &&
            model.FreeReference == saved && saved.IsSelected);
        await model.StopAsync();
        Check(!saved.IsSelected && model.HomeSelectedReference == saved);
        Check(model.SelectHomeFreePrompt(prompt) && model.HomeReferences.Count == 6);
        model.RemoveFreeReference();
        Check(model.SelectHomeFreePrompt("Text without an image"));
        var textOnly = model.HomeSelectedReference;
        Check(textOnly.IsPromptOnly && model.ReferenceContext(textOnly).ReferencePath is null);
        await model.StartLandingAsync();
        Check(model.SelectedMode == "free" && model.FreeReference is null && textOnly.IsSelected);
        await model.StopAsync();
        model.ResetHomeReferences();
    }),
    ("Elapsed time starts at Generating, survives condition updates and resets on stop", async () =>
    {
        var dispatcher = new FakeDispatcher();
        var model = new MainViewModel(dispatcher, new FakeThumbnails(), new FakeOutput());
        var timer = dispatcher.Timers.Single();
        var receive = model.CreateSessionStateHandler();
        receive(new RealtimeState(RealtimeConnectionState.Ready));
        Check(!timer.IsEnabled && model.Elapsed == "00:00");
        receive(new RealtimeState(RealtimeConnectionState.Connected));
        Check(model.Active && !timer.IsEnabled && model.Elapsed == "00:00");
        receive(new RealtimeState(RealtimeConnectionState.Generating));
        Check(timer.IsEnabled && timer.Starts == 1 && model.Elapsed == "00:00");
        await Task.Delay(1100);
        timer.Pulse();
        Check(model.Elapsed != "00:00");
        receive(new RealtimeState(RealtimeConnectionState.Generating));
        Check(timer.Starts == 1 && model.Elapsed != "00:00");
        await model.StopAsync();
        Check(!timer.IsEnabled && model.Elapsed == "00:00");
        receive(new RealtimeState(RealtimeConnectionState.Generating));
        Check(!timer.IsEnabled && !model.Active && model.Elapsed == "00:00");
        var next = model.CreateSessionStateHandler();
        next(new RealtimeState(RealtimeConnectionState.Connected));
        Check(!timer.IsEnabled && model.Elapsed == "00:00");
        next(new RealtimeState(RealtimeConnectionState.Generating));
        Check(timer.IsEnabled && timer.Starts == 2 && model.Elapsed == "00:00");
        await model.StopAsync();
    }),
    ("Presets preserve order, identity, image pairing, and regional hosts", () =>
    {
        var expected = new Dictionary<string, string[]>
        {
            ["charx"] = ["charx_image21.png", "charx_image2.jpeg", "charx_image22.png", "charx_image23.jpeg", "charx_image24.png", "charx_image25.jpeg", "charx_image13.jpeg", "charx_image14.png", "charx_image16.png", "charx_real_image17.jpeg", "charx_image18.png"],
            ["clothx"] = ["clothx_image1.png", "clothx_image2.png", "clothx_real_image3.png", "clothx_real_image4.png", "clothx_image5.png", "clothx_image6.png", "clothx_image7.png", "clothx_image8.png", "clothx_real_image9.png", "clothx_real_image10.png", "clothx_image11.jpeg", "clothx_image12.jpeg"],
            ["vibex"] = Enumerable.Range(1, 8).Select(i => $"vibex_real_image{i}.png").ToArray(),
            ["dimx"] = ["dimx_image3.png", "dimx_image4.png", "dimx_image5.png", "dimx_image7.png", "dimx_image8.png"]
        };
        foreach (var edition in Enum.GetValues<ProductEdition>())
        {
            var profile = new ProductProfile(edition); var presets = ReferenceCatalog.Load(profile);
            Check(presets.Count == 38 && presets.Select(item => item.Id).Distinct().Count() == presets.Count);
            foreach (var (mode, filenames) in expected)
                Check(presets.Where(item => item.Mode == mode && !item.IsPromptOnly).Select(item => new Uri(item.ReferenceUrl).Segments[^1]).SequenceEqual(filenames), mode);
            foreach (var item in presets.Where(item => !item.IsPromptOnly))
            {
                var original = new Uri(item.ReferenceUrl); var thumbnail = new Uri(item.ThumbnailUrl);
                Check(item.Id == item.ReferenceUrl && original.Host == profile.AssetOrigin.Host && original.AbsolutePath == thumbnail.AbsolutePath);
                Check(original.AbsolutePath.StartsWith($"/images/playground/{item.Mode}/") && original.Query == "?v=32&presetVersion=20261030");
                Check(!original.Query.Contains("imageMogr2") && thumbnail.Query.EndsWith("&imageMogr2/crop/256x256/gravity/center/format/webp/quality/90"));
                Check(!string.IsNullOrWhiteSpace(item.Prompt));
            }
            Check(presets[0].Name == (profile.IsOverseas ? "Candy Girl" : "糖果少女"));
        }
        return Task.CompletedTask;
    }),
    ("Each preset keeps its specific instruction instead of falling back to its mode's upload prompt", () =>
    {
        foreach (var edition in Enum.GetValues<ProductEdition>())
        {
            var profile = new ProductProfile(edition); var presets = ReferenceCatalog.Load(profile);
            ReferenceItem Find(string file) => presets.Single(item => item.ReferenceUrl.Contains("/" + file + "?"));
            Check(Find("charx_image21.png").Prompt == (profile.IsOverseas ? "Become the character in the reference image" : "视频中人物替换成参考图中角色"));
            Check(Find("clothx_image11.jpeg").Prompt == (profile.IsOverseas ? "Apply the cap from the reference image to the video character." : "将参考图棒球帽应用到视频角色身上"));
            Check(Find("clothx_image12.jpeg").Prompt == (profile.IsOverseas ? "Apply the glasses from the reference image to the video character." : "将参考图眼镜应用到视频角色身上"));
            Check(Find("clothx_image6.png").Prompt == (profile.IsOverseas ? "Keep the character and background unchanged, only replace the upper-body clothes with the reference‑image outfit." : "将参考图的上衣穿到视频人物身上，其他保持不变"));
            Check(Find("clothx_image8.png").Prompt == (profile.IsOverseas ? "Put the bottoms from the reference image on the video character. Keep everything else unchanged." : "将参考图的下装穿到视频人物身上，其他保持不变"));
            Check(Find("vibex_real_image1.png").Prompt == (profile.IsOverseas ? "The character from the reference image recreates the actions in the video. Preserve all appearance details of the reference character exactly, and keep the original background from the reference image unchanged." : "参考图角色重现视频动作，角色全部外观细节保留，保留并使用参考图的背景。"));
        }
        return Task.CompletedTask;
    }),
    ("Uploaded references capture mode defaults and preserve user-authored free text", () =>
    {
        var model = ActiveModel(new FakeOutput());
        foreach (var edition in Enum.GetValues<ProductEdition>())
        {
            var profile = new ProductProfile(edition);
            foreach (string mode in new[] { "charx", "clothx", "vibex", "dimx", "free" })
            {
                const string free = "My own prompt / 我自己的提示词";
                var item = ReferenceItem.FromUpload("my-reference.png", mode, free, profile);
                item.ReferenceUrl = "https://upload.example/reference.png";
                model.Prompt = "A later draft"; model.SelectedMode = "free";
                var context = model.ReferenceContext(item);
                Check(context.Prompt == (mode == "free" ? free : GenerationPrompts.ForMode(mode, profile)));
                Check(context.ReferencePath == item.ReferenceUrl);
                Check(item.LocalPath == "my-reference.png" && !item.IsPromptOnly);
            }
            Check(GenerationPrompts.ForMode("charx", profile) == (profile.IsOverseas ? "Become the character in the reference image" : "视频中人物替换成参考图中角色"));
            Check(GenerationPrompts.ForMode("vibex", profile) == (profile.IsOverseas ? "The character from the reference image recreates the actions in the video. Preserve all appearance details of the reference character exactly, and keep the original background from the reference image unchanged." : "参考图角色重现视频动作，角色全部外观细节保留，保留并使用参考图的背景"));
            Check(GenerationPrompts.ForMode("dimx", profile) == (profile.IsOverseas
                ? "Summon / Add a Subject: Keep all existing subjects in the original video. Add the subject from the reference image without replacing any existing subject. Summon the reference character onto the shoulder or hand of the person in the video."
                : "召唤新增任务：保留原视频中已有的主体，额外加入参考图中的主体，不替换任何原有主体。把参考图角色召唤到视频人物的肩膀上或者手上"));
        }
        return Task.CompletedTask;
    }),
    ("Virtual Summon supports prompt-only selections, image selections and cross-mode selection cleanup", async () =>
    {
        var model = ActiveModel(new FakeOutput());
        Check(model.SummonReferences.Count == 8 && model.SummonReferences[0].IsUpload);
        var promptOnly = model.SummonReferences.Where(item => item.IsPromptOnly).ToArray();
        Check(promptOnly.Select(item => item.Id).SequenceEqual(new[] { "preset:dimx-little-dog", "preset:dimx-little-mouse" }));
        foreach (var item in promptOnly)
        {
            var context = model.ReferenceContext(item);
            Check(context.ReferencePath is null && context.Prompt == item.Prompt);
            model.SelectedMode = "dimx"; await model.SelectReferenceAsync(item);
            Check(item.IsSelected && model.CharacterReferences.All(reference => !reference.IsSelected) && model.Error.Length == 0);
        }
        await model.StopAsync();
        Check(model.SummonReferences.All(item => !item.IsSelected));
        foreach (var edition in Enum.GetValues<ProductEdition>())
        {
            var profile = new ProductProfile(edition); var summons = ReferenceCatalog.Load(profile).Where(item => item.Mode == "dimx").ToArray();
            Check(summons[0].Prompt == (profile.IsOverseas ? "Summon a small dog onto the person's shoulder." : "召唤一只小狗到人的肩膀上"));
            Check(summons[1].Prompt == (profile.IsOverseas ? "Summon a little mouse onto the person's shoulder." : "召唤一只小老鼠到人物肩膀上"));
            Check(summons[2].Prompt!.Contains(profile.IsOverseas ? "without replacing any existing subject" : "不替换任何原有主体"));
        }
    }),
    ("Credit codes and legacy descriptions are recognized without false positives", () =>
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
        var model = ActiveModel(output, access); var receive = model.CreateSessionStateHandler();
        receive(FailedState(-15, "Session heartbeat timed out"));
        Check(!model.Active && model.IsClosing && model.Busy && !model.CanEdit);
        Check(model.Error == AppText.Get("Session heartbeat timed out") && !model.StartCommand.CanExecute(null));
        await model.StartLandingAsync(); await model.GenerateAsync();
        Check(!model.Active && access.KeyReads == 0 && access.CreditChecks == 0);
        receive(new RealtimeState(RealtimeConnectionState.Generating));
        receive(FailedState(-4, "Late unrelated error"));
        Check(!model.Active && model.Error == AppText.Get("Session heartbeat timed out") && output.Stops == 1);
        Task cleanup = model.StopAsync(); output.Gate.SetResult(); await cleanup;
        Check(!model.IsClosing && !model.Busy && model.State == RealtimeConnectionState.Ready && model.Session is null,
            "Without a native controller, the simulated SDK state remains the last callback value.");
        Check(model.LocalVideo is null && model.RemoteVideo is null && model.Error == AppText.Get("Session heartbeat timed out"));
        Check(model.StartCommand.CanExecute(null));
    }),
    ("Both insufficient-credit business codes close generation without rejecting authentication or refreshing balance", async () =>
    {
        foreach (int apiCode in new[] { 43001, 46017 })
        {
            var output = new FakeOutput(); var access = new FakeAccess(); var model = ActiveModel(output, access);
            int rejected = 0; model.AuthenticationRejected += () => rejected++;
            model.CreateSessionStateHandler()(FailedState(-4, "Billing refused", apiCode, 403));
            Check(!model.Active && model.Error == CreditPolicy.InsufficientMessage && rejected == 0);
            Check(output.Stops == 1 && access.CreditChecks == 0 && access.KeyReads == 0 && access.HasVerifiedSession);
            await model.StopAsync();
        }
    }),
    ("SDK operation credit failures normalize the notice and end the session", async () =>
    {
        var output = new FakeOutput(); var model = ActiveModel(output);
        model.ReportError(new XmaxException(XmaxErrorCode.SessionError, "INSUFFICIENT_CREDITS"));
        Check(!model.Active && model.Error == CreditPolicy.InsufficientMessage && output.Stops == 1);
        await model.StopAsync();
    }),
    ("Transient and non-platform errors preserve generation", () =>
    {
        var output = new FakeOutput(); var model = ActiveModel(output);
        model.ReportError(new XmaxException(XmaxErrorCode.ApiError, "Request timed out"));
        Check(model.Active && output.Stops == 0 && model.Error == AppText.Get("Request timed out"));
        model.ReportError(new XmaxException(XmaxErrorCode.InvalidConfiguration, "Insufficient credits"));
        Check(model.Active && output.Stops == 0 && model.Error == AppText.Get("Insufficient credits"));
        return Task.CompletedTask;
    }),
    ("Cleanup faults cannot overwrite the initiating error or leave restart disabled", async () =>
    {
        var output = new FakeOutput { StopFailure = new IOException("Output teardown failed") }; var model = ActiveModel(output);
        model.CreateSessionStateHandler()(FailedState(-15, "Original session failure"));
        Check(!model.Active && model.Error == AppText.Get("Original session failure") && !model.Busy && !model.IsClosing);
        await model.StopAsync(); Check(model.Error == AppText.Get("Original session failure"));
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
        model.CreateSessionStateHandler()(FailedState(-15, "Session ended"));
        Check(!model.Active && model.IsClosing && output.Stops == 1 && !model.StartCommand.CanExecute(null));
        Task cleanup = model.StopAsync(); startup.SetException(new IOException("Late output startup failed"));
        await cleanup; Check(!model.Busy && output.Stops == 2 && model.Error == AppText.Get("Session ended"));
    }),
    ("Terminal state preserves its full error and ignores later state callbacks", async () =>
    {
        var output = new FakeOutput { Gate = new() }; var model = ActiveModel(output);
        var receive = model.CreateSessionStateHandler();
        receive(FailedState(-15, "Heartbeat connection lost"));
        Check(!model.Active && model.IsClosing && model.Error == AppText.Get("Heartbeat connection lost"));
        receive(FailedState(-15, "Unrelated failure"));
        Check(model.Error == AppText.Get("Heartbeat connection lost") && output.Stops == 1);
        model.ClearError();
        receive(FailedState(-15, "Heartbeat connection lost"));
        Check(model.Error == AppText.Get(""));
        output.Gate.SetResult();
        await model.StopAsync();
    }),
    ("The terminal state's credit error is recognized before cleanup", async () =>
    {
        var output = new FakeOutput { Gate = new() }; var model = ActiveModel(output);
        model.CreateSessionStateHandler()(FailedState(-15, "No credits remaining"));
        Check(!model.Active && model.Error == CreditPolicy.InsufficientMessage);
        output.Gate.SetResult();
        await model.StopAsync();
    }),
    ("An old lifecycle cannot reactivate or terminate the next workspace", async () =>
    {
        var model = ActiveModel(new FakeOutput()); var old = model.CreateSessionStateHandler(); await model.StopAsync();
        model.ConfigurePreview(true); model.ClearError();
        old(FailedState(-15, "Stale failure"));
        old(new RealtimeState(RealtimeConnectionState.Generating));
        Check(model.Active && model.Error == AppText.Get(""));
        model.ReportError(new XmaxException(XmaxErrorCode.ApiError, "Current notice"));
        Check(model.Active && model.Error == AppText.Get("Current notice"));
    }),
    ("Authentication uses the service ApiCode, never the SDK result field", () =>
    {
        var model = ActiveModel(new FakeOutput(), new FakeAccess()); int rejected = 0;
        model.AuthenticationRejected += () => rejected++;
        model.ReportError(new XmaxException(46002, "SDK result is not a business code")); Check(rejected == 0);
        model.ReportError(new XmaxException(XmaxErrorCode.ApiError, "Session expired", apiCode: 46002)); Check(rejected == 1);
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
static RealtimeState FailedState(int code, string message, int apiCode = 0, int http = 0) =>
    new(RealtimeConnectionState.Ready, "test-session", null, new RealtimeReason.Failure(new(code, message, apiCode, http)));

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
sealed class PendingThumbnails : IThumbnailLoader
{
    internal readonly TaskCompletionSource<object> Result = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public Task<object> LoadAsync(string source) => Result.Task;
}
sealed class FakeDispatcher : IUiDispatcher
{
    public List<FakeTimer> Timers { get; } = [];
    public void InvokeAsync(Action action) => action();
    public IUiTimer CreateTimer(TimeSpan interval) { var timer = new FakeTimer(); Timers.Add(timer); return timer; }
}
sealed class FakeTimer : IUiTimer
{
    public bool IsEnabled { get; private set; }
    public int Starts { get; private set; }
    public event EventHandler? Tick;
    public void Start() { ++Starts; IsEnabled = true; }
    public void Stop() => IsEnabled = false;
    public void Pulse() => Tick?.Invoke(this, EventArgs.Empty);
}
