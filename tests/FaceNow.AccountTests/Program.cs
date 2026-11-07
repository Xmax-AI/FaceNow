using System.Net;
using System.Text;
using System.Text.Json;
using FaceNow.App.User;
using FaceNow.Core.User;
using FaceNow.Windows.Network;

var tests = new (string Name, Func<Task> Run)[]
{
    ("Missing WebView2 is recognized for both managed and COM file-not-found projections", () =>
    {
        Check(CaptchaStartupPolicy.Classify(new FileNotFoundException()) == CaptchaStartupIssue.RuntimeMissing);
        Check(CaptchaStartupPolicy.Classify(new System.Runtime.InteropServices.COMException("missing", unchecked((int)0x80070002))) == CaptchaStartupIssue.RuntimeMissing);
        Check(CaptchaStartupPolicy.Classify(new System.Runtime.InteropServices.COMException("uninstalled", unchecked((int)0x80070645))) == CaptchaStartupIssue.RuntimeMissing);
        return Task.CompletedTask;
    }),
    ("WebView2 deployment, permissions and shared-process failures keep distinct recovery advice", () =>
    {
        Check(CaptchaStartupPolicy.Classify(new DllNotFoundException()) == CaptchaStartupIssue.ApplicationFilesMissing);
        Check(CaptchaStartupPolicy.Classify(new BadImageFormatException()) == CaptchaStartupIssue.ApplicationFilesMissing);
        Check(CaptchaStartupPolicy.Classify(new UnauthorizedAccessException()) == CaptchaStartupIssue.AccessDenied);
        Check(CaptchaStartupPolicy.Classify(new System.Runtime.InteropServices.COMException("busy", unchecked((int)0x8007139F))) == CaptchaStartupIssue.InUse);
        Check(CaptchaStartupPolicy.Classify(new System.Runtime.InteropServices.COMException("old runtime", unchecked((int)0x80004002))) == CaptchaStartupIssue.UnsupportedRuntime);
        Check(CaptchaStartupPolicy.Classify(new IOException("other failure")) == CaptchaStartupIssue.Unknown);
        return Task.CompletedTask;
    }),
    ("Known zero credits block startup without requesting balance or invalidating the key", async () =>
    {
        var api = new FakeApi { BalanceOverride = () => Task.FromResult(0d) };
        using var user = new UserRepository(api, new MemoryStorage());
        await user.SignInWithKeyAsync("uk-test"); await user.RefreshCreditsAsync();
        int requests = api.BalanceRequests;
        var error = await Throws<AccountException>(() => { user.EnsureSufficientCredits(); return Task.CompletedTask; });
        Check(user.HasInsufficientCredits && error.Code == CreditPolicy.InsufficientCode
            && error.Message == CreditPolicy.InsufficientMessage && !error.IsUnauthorized);
        Check(api.BalanceRequests == requests && user.HasVerifiedSession && user.GetVerifiedGenerationKey() == "uk-test");
    }),
    ("Unknown and positive low balances permit startup using only in-memory state", async () =>
    {
        var api = new FakeApi(); using var user = new UserRepository(api, new MemoryStorage());
        await user.SignInWithKeyAsync("uk-test");
        user.EnsureSufficientCredits(); Check(!user.HasInsufficientCredits && api.BalanceRequests == 0);
        foreach (double balance in new[] { .000001, 299d, 300d, 869589d })
        {
            api.BalanceOverride = () => Task.FromResult(balance); await user.RefreshCreditsAsync();
            int requests = api.BalanceRequests; user.EnsureSufficientCredits();
            Check(!user.HasInsufficientCredits && api.BalanceRequests == requests);
        }
        Check(CreditPolicy.IsInsufficient(-1));
    }),
    ("Balance refresh releases the startup gate after recharge; transient failures retain it", async () =>
    {
        var api = new FakeApi { BalanceOverride = () => Task.FromResult(0d) };
        using var user = new UserRepository(api, new MemoryStorage());
        await user.SignInWithKeyAsync("uk-test"); await user.RefreshCreditsAsync();
        api.BalanceOverride = () => Task.FromException<double>(new IOException("offline"));
        await Throws<IOException>(() => user.RefreshCreditsAsync()); Check(user.HasInsufficientCredits);
        api.BalanceOverride = () => Task.FromResult(1d); await user.RefreshCreditsAsync();
        user.EnsureSufficientCredits(); Check(!user.HasInsufficientCredits);
        await user.SignOutAsync(); Check(user.RemainingCredits is null && !user.HasInsufficientCredits);
    }),
    ("Account card masks key identity and formats server credits without exposing credentials", async () =>
    {
        var api = new FakeApi { BalanceOverride = () => Task.FromResult(869589.1234567) };
        using var user = new UserRepository(api, new MemoryStorage());
        await user.SignInWithKeyAsync("uk-test"); await user.RefreshCreditsAsync();
        var card = AccountPresentation.From(user);
        Check(card.Title == "••••••••test" && !card.Title.Contains("uk-") && user.SessionApiKeySuffix == "test");
        Check(card.AvatarText == "" && card.Credits == "869,589.123457");
        await user.SignOutAsync();
        card = AccountPresentation.From(user);
        Check(card.Title == "Account" && card.AvatarText == "" && card.Credits == "—" && user.SessionApiKeySuffix is null);
    }),
    ("Account avatar and title prioritize phone, then email", async () =>
    {
        var api = new FakeApi { ProfileOverride = () => Task.FromResult(new AccountProfile { Uid = "owner", Phone = " 13800000000 ", Email = " yu@example.com " }) };
        using var user = new UserRepository(api, new MemoryStorage());
        await user.SignInWithCodeAsync(Configuration(), LoginMethod.Email, "yu@example.com", "123456", new());
        var card = AccountPresentation.From(user);
        Check(card.AvatarText == "13" && card.Title == "yu@example.com" && user.SessionApiKeySuffix is null);
        await user.SignOutAsync();
        api.ProfileOverride = () => Task.FromResult(new AccountProfile { Uid = "owner", Phone = " ", Email = " yu@example.com " });
        await user.SignInWithCodeAsync(Configuration(), LoginMethod.Email, "yu@example.com", "123456", new());
        Check(AccountPresentation.From(user).AvatarText == "YU");
    }),
    ("API key login verifies owner and filters foreign/revoked keys", async () =>
    {
        var api = new FakeApi(); var store = new MemoryStorage();
        using var user = new UserRepository(api, store);
        api.Keys = [Key(), Key("foreign", "uk-foreign", "other"), Key("revoked", "uk-revoked", status: "revoked")];
        await user.SignInWithKeyAsync("  uk-test\n");
        Check(user.HasVerifiedSession && user.Keys.Count == 1 && user.GetVerifiedGenerationKey() == "uk-test");
        Check(store.Credential?.Kind == CredentialKind.ApiKey && api.Creates == 0);
    }),
    ("Unmatched, revoked, wrong-tenant and mismatched-owner keys cannot authenticate", async () =>
    {
        foreach (var record in new[] { Key(key: "uk-other"), Key(status: "revoked"), Key(tenant: "another"), Key(owner: "another") })
        {
            var api = new FakeApi { Keys = [record] }; var store = new MemoryStorage();
            using var user = new UserRepository(api, store);
            await Throws<AccountException>(() => user.SignInWithKeyAsync("uk-test"));
            Check(!user.CanAccessHome && store.Credential is null);
        }
    }),
    ("Unverified saved credentials can show cached home but cannot generate", async () =>
    {
        var gate = new TaskCompletionSource<AccountProfile>();
        var api = new FakeApi { ProfileOverride = () => gate.Task }; var store = Saved();
        using var user = new UserRepository(api, store);
        var restore = user.RestoreAsync();
        Check(user.CanAccessHome && !user.HasVerifiedSession && user.State == SessionState.Cached);
        await Throws<AccountException>(() => Task.FromResult(user.GetVerifiedGenerationKey()));
        gate.SetResult(Profile()); await restore;
        Check(user.HasVerifiedSession);
    }),
    ("Cached home loads before network verification without granting generation access", () =>
    {
        var api = new FakeApi(); using var user = new UserRepository(api, Saved());
        user.LoadCachedSession();
        Check(user.CanAccessHome && !user.HasVerifiedSession && user.State == SessionState.Cached && api.LastProfileCredential is null);
        return Task.CompletedTask;
    }),
    ("Unauthorized restoration clears the saved session", async () =>
    {
        var api = new FakeApi { ProfileOverride = () => Task.FromException<AccountProfile>(new AccountException("expired", 401)) }; var store = Saved();
        using var user = new UserRepository(api, store);
        await user.RestoreAsync();
        Check(!user.CanAccessHome && store.Credential is null && user.Notice?.Contains("expired") == true);
    }),
    ("Temporary restoration failure retains credential but returns to login", async () =>
    {
        var api = new FakeApi { ProfileOverride = () => Task.FromException<AccountProfile>(new AccountException("offline")) }; var store = Saved();
        using var user = new UserRepository(api, store);
        await user.RestoreAsync();
        Check(!user.CanAccessHome && store.Credential is not null && !user.IsBusy);
    }),
    ("Late login responses cannot recreate a signed-out session", async () =>
    {
        var gate = new TaskCompletionSource<AccountProfile>();
        var api = new FakeApi { ProfileOverride = () => gate.Task }; var store = new MemoryStorage();
        using var user = new UserRepository(api, store);
        var login = user.SignInWithKeyAsync("uk-test");
        await user.SignOutAsync(); gate.SetResult(Profile());
        await Throws<OperationCanceledException>(() => login);
        Check(!user.CanAccessHome && store.Credential is null);
    }),
    ("Late restoration responses cannot recreate a signed-out session", async () =>
    {
        var gate = new TaskCompletionSource<AccountProfile>();
        var api = new FakeApi { ProfileOverride = () => gate.Task }; var store = Saved();
        using var user = new UserRepository(api, store);
        var restore = user.RestoreAsync(); await user.SignOutAsync(); gate.SetResult(Profile()); await restore;
        Check(!user.CanAccessHome && store.Credential is null);
    }),
    ("Code login keeps account tokens separate from generation keys", async () =>
    {
        var api = new FakeApi(); var store = new MemoryStorage();
        using var user = new UserRepository(api, store);
        await user.SignInWithCodeAsync(Configuration(), LoginMethod.Email, "user@example.com", "123456", new());
        Check(store.Credential?.Kind == CredentialKind.AccountToken && store.Credential.Value == "account-token");
        Check(user.GetVerifiedGenerationKey() == "uk-test" && api.LastProfileCredential == "account-token" && api.Creates == 0);
    }),
    ("An account with no keys can sign in but cannot start generation", async () =>
    {
        var api = new FakeApi { Keys = [] }; using var user = new UserRepository(api, new MemoryStorage());
        await user.SignInWithCodeAsync(Configuration(), LoginMethod.Sms, "13800000000", "123456", new());
        Check(user.HasVerifiedSession && user.Keys.Count == 0 && api.Creates == 0);
        await Throws<AccountException>(() => Task.FromResult(user.GetVerifiedGenerationKey()));
        await user.CreateKeyAsync(); Check(api.Creates == 1 && user.GetVerifiedGenerationKey() == "uk-created");
    }),
    ("Persisted key selection must belong to the authenticated owner", async () =>
    {
        var store = Saved(); store.Credential = new() { Kind = CredentialKind.AccountToken, Value = "account-token", SelectedKeyUid = "foreign" };
        var api = new FakeApi { Keys = [Key(), Key("foreign", "uk-foreign", "other")] };
        using var user = new UserRepository(api, store); await user.RestoreAsync();
        user.SelectKey("foreign"); Check(user.SelectedKeyUid == "key-1" && user.GetVerifiedGenerationKey() == "uk-test");
    }),
    ("Legacy keys migrate only after server verification", async () =>
    {
        var store = new MemoryStorage(); using var user = new UserRepository(new FakeApi(), store);
        await user.RestoreAsync("uk-test"); Check(user.HasVerifiedSession && store.Credential?.Value == "uk-test");
        var invalid = new MemoryStorage(); using var other = new UserRepository(new FakeApi { Keys = [] }, invalid);
        await other.RestoreAsync("uk-test"); Check(!other.CanAccessHome && invalid.Credential is null);
    }),
    ("Logout invalidates pending credits and never logs out an API key remotely", async () =>
    {
        var gate = new TaskCompletionSource<double>(); var api = new FakeApi { BalanceOverride = () => gate.Task };
        using var user = new UserRepository(api, new MemoryStorage()); await user.SignInWithKeyAsync("uk-test");
        var balance = user.RefreshCreditsAsync(); await user.SignOutAsync(); gate.SetResult(99); await balance;
        Check(!user.CanAccessHome && user.RemainingCredits is null && api.Logouts == 0);
    }),
    ("Account-token logout invokes server logout after local state is cleared", async () =>
    {
        var api = new FakeApi(); var store = new MemoryStorage(); using var user = new UserRepository(api, store);
        await user.SignInWithCodeAsync(Configuration(), LoginMethod.Sms, "13800000000", "123456", new());
        api.OnLogout = () => Check(!user.CanAccessHome && store.Credential is null);
        await user.SignOutAsync(); Check(api.Logouts == 1);
    }),
    ("Unauthorized balance responses invalidate the session", async () =>
    {
        var api = new FakeApi { BalanceOverride = () => Task.FromException<double>(new AccountException("expired", 401)) };
        var store = new MemoryStorage(); using var user = new UserRepository(api, store);
        await user.SignInWithKeyAsync("uk-test"); await user.RefreshCreditsAsync();
        Check(!user.HasVerifiedSession && store.Credential is null);
    }),
    ("Storage failures do not publish successful authentication", async () =>
    {
        using var user = new UserRepository(new FakeApi(), new MemoryStorage { FailSave = true });
        await Throws<IOException>(() => user.SignInWithKeyAsync("uk-test")); Check(!user.CanAccessHome);
    }),
    ("Form channel drafts, ASCII filtering and per-destination cooldowns", () =>
    {
        long now = 1000; var model = new LoginViewModel(() => now, new(FaceNow.Core.Product.ProductEdition.Domestic)) { Configuration = Configuration() };
        model.SetAccount("13800000000"); model.SetCode("１a1234567"); Check(model.Code == "123456");
        model.RecordSent(LoginMethod.Sms, model.Account, 60); Check(model.Cooldown == 60 && !model.CanSendCode);
        model.Select(2); model.ApiKey = "uk-test"; Check(model.CanSubmit);
        model.Select(0); Check(model.Account == "13800000000" && model.Code == "123456");
        now += 2001; Check(model.Cooldown == 58);
        model.SetAccount("13900000000"); Check(model.Code == "" && model.Cooldown == 0);
        model.Select(2); model.ApiKey = "uk-test"; Check(model.CanSubmit);
        model.IsBusy = true; Check(!model.CanSubmit); return Task.CompletedTask;
    }),
    ("Failed login configuration leaves a retry action available in both editions", () =>
    {
        foreach (var edition in Enum.GetValues<FaceNow.Core.Product.ProductEdition>())
        {
            var model = new LoginViewModel(product: new(edition));
            model.SetAccount(model.Method == LoginMethod.Sms ? "13800000000" : "user@example.com");
            Check(!model.CanSendCode);
            model.ConfigurationFailed = true;
            Check(model.CanSendCode && !model.CanSubmit);
            model.IsBusy = true; Check(!model.CanSendCode);
            model.IsBusy = false;
            model.Configuration = Configuration(); model.ConfigurationFailed = false;
            Check(model.CanSendCode);
            model.SetCode("123456"); Check(model.CanSubmit);
        }
        return Task.CompletedTask;
    }),
    ("Nonempty API key input reports local validation without sending malformed credentials", async () =>
    {
        var model = new LoginViewModel(); model.Select(2);
        model.ApiKey = " \n "; Check(!model.CanSubmit);
        model.ApiKey = "not-an-api-key"; Check(model.CanSubmit);
        var api = new FakeApi(); using var user = new UserRepository(api, new MemoryStorage());
        var error = await Throws<AccountException>(() => user.SignInWithKeyAsync(model.ApiKey));
        Check(api.LastProfileCredential is null && !user.CanAccessHome);
        Check(LoginViewModel.SignInErrorMessage(error, true) == "Invalid API key. Check it and try again.");
        foreach (int code in new[] { 400, 401, 403, 46002 })
            Check(LoginViewModel.SignInErrorMessage(new AccountException("rejected", code), true) == "Invalid API key. Check it and try again.");
        foreach (int code in new[] { 429, 500, 503 })
            Check(LoginViewModel.SignInErrorMessage(new AccountException("temporary failure", code), true) == "temporary failure");
        Check(LoginViewModel.SignInErrorMessage(new IOException("offline"), true) == "offline");
        model.IsBusy = true; Check(!model.CanSubmit);
    }),
    ("Regional login forms expose only the local code channel and API key", () =>
    {
        foreach (var edition in new[] { FaceNow.Core.Product.ProductEdition.Domestic, FaceNow.Core.Product.ProductEdition.Overseas })
        {
            var model = new LoginViewModel(product: new(edition)) { Configuration = Configuration() };
            bool overseas = edition == FaceNow.Core.Product.ProductEdition.Overseas;
            Check(model.DefaultIndex == (overseas ? 1 : 0) && model.Method == (overseas ? LoginMethod.Email : LoginMethod.Sms));
            Check(model.IsChannelVisible(model.DefaultIndex) && model.IsChannelVisible(2) && !model.IsChannelVisible(overseas ? 0 : 1));
            model.Select(overseas ? 0 : 1); Check(model.Method == (overseas ? LoginMethod.Email : LoginMethod.Sms));
            model.SetAccount(overseas ? "user@example.com" : "13800000000"); model.SetCode("123456"); Check(model.CanSubmit);
            model.Select(2); model.ApiKey = "uk-test"; Check(model.CanSubmit);
        }
        return Task.CompletedTask;
    }),
    ("Successful login clears form drafts, credentials, errors and resend deadlines", () =>
    {
        foreach (var edition in new[] { FaceNow.Core.Product.ProductEdition.Domestic, FaceNow.Core.Product.ProductEdition.Overseas })
        {
            var model = new LoginViewModel(() => 1000, new(edition)) { Configuration = Configuration() };
            string destination = model.Method == LoginMethod.Sms ? "13800000000" : "user@example.com";
            model.SetAccount(destination); model.SetCode("123456"); model.RecordSent(model.Method, destination, 60);
            model.Select(2); model.ApiKey = "uk-test"; model.Error = "Rejected attempt"; model.IsBusy = true;
            model.ResetAfterSignIn();
            Check(model.Account.Length == 0 && model.Code.Length == 0 && model.ApiKey.Length == 0 && model.Error is null && !model.UsesApiKey);
            Check(model.Cooldown == 0 && model.IsBusy); // The request owns its final busy transition.
            model.IsBusy = false; Check(!model.CanSubmit && !model.CanSendCode);
            model.SetAccount(destination); Check(model.Cooldown == 0 && model.CanSendCode);
            model.Select(2); model.Select(model.DefaultIndex); Check(model.Code.Length == 0 && model.Cooldown == 0);
        }
        return Task.CompletedTask;
    }),
    ("Required security proofs and invalid destinations never reach account endpoints", async () =>
    {
        var api = new FakeApi(); using var user = new UserRepository(api, new MemoryStorage());
        var secure = Configuration(captcha: true);
        await Throws<AccountException>(() => user.SendCodeAsync(secure, LoginMethod.Sms, "13800000000", new(), default));
        await Throws<AccountException>(() => user.SignInWithCodeAsync(secure, LoginMethod.Sms, "13800000000", "123456", new()));
        await Throws<AccountException>(() => user.SendCodeAsync(Configuration(), LoginMethod.Email, "not-an-email", new(), default));
        await Throws<AccountException>(() => user.SignInWithCodeAsync(Configuration(), LoginMethod.Email, "user@example.com", "１２３４５６", new()));
        Check(api.CodeRequests == 0 && api.LoginRequests == 0);
        await user.SendCodeAsync(secure, LoginMethod.Sms, "13800000000", new("one-use-ticket", "random"), default);
        Check(api.CodeRequests == 1);
    }),
    ("Email login follows the platform's separate login-challenge setting", async () =>
    {
        var api = new FakeApi(); using var user = new UserRepository(api, new MemoryStorage());
        await Throws<AccountException>(() => user.SignInWithCodeAsync(Configuration(loginCaptcha: true), LoginMethod.Email, "user@example.com", "123456", new()));
        await user.SignInWithCodeAsync(Configuration(captcha: true), LoginMethod.Email, "user@example.com", "123456", new());
        Check(user.HasVerifiedSession && api.LoginRequests == 1);
    }),
    ("Another credential's cached profile is never displayed", async () =>
    {
        var gate = new TaskCompletionSource<AccountProfile>();
        var api = new FakeApi { ProfileOverride = () => gate.Task }; var store = Saved();
        store.Cache = new() { CredentialDigest = "different-credential", Profile = new() { Uid = "foreign", Nickname = "Another user" } };
        using var user = new UserRepository(api, store); var restore = user.RestoreAsync();
        Check(user.CanAccessHome && user.Profile is null);
        gate.SetResult(Profile()); await restore; Check(user.Profile?.Identity == "owner");
    }),
    ("Empty profile identities cannot create a session", async () =>
    {
        var api = new FakeApi { ProfileOverride = () => Task.FromResult(new AccountProfile()) };
        var store = new MemoryStorage(); using var user = new UserRepository(api, store);
        await Throws<AccountException>(() => user.SignInWithKeyAsync("uk-test")); Check(!user.CanAccessHome && store.Credential is null);
    }),
    ("HTTP contract uses the edition origin, tenant and camel-case DTOs", async () =>
    {
        var handler = new RecordingHandler(); using var client = new HttpClient(handler); using var api = new AccountApi(client);
        handler.Response = Envelope("\"account-token\"");
        await api.LoginAsync(LoginMethod.Sms, "13800000000", "123456", new("ticket", "random"), default);
        Check(handler.Uri == new Uri(AccountContract.ServiceOrigin, "/baas/api/user/login") && handler.Authorization is null);
        using var body = JsonDocument.Parse(handler.Body!); var root = body.RootElement;
        Check(root.GetProperty("tenantName").GetString() == "open-platform" && root.GetProperty("loginMethod").GetString() == "sms"
            && root.GetProperty("credential").GetString() == "123456" && root.GetProperty("captchaTicket").GetString() == "ticket");
        handler.Response = Envelope("null"); await api.SendCodeAsync(LoginMethod.Email, "user@example.com", new(), default);
        Check(handler.Uri!.AbsolutePath == "/baas/api/message/public/email-code/send" && !handler.Body!.Contains("phone"));
    }),
    ("Authorization is request scoped and cannot leak into public configuration", async () =>
    {
        var handler = new RecordingHandler { Response = Envelope("{\"uid\":\"owner\"}") };
        using var client = new HttpClient(handler); using var api = new AccountApi(client);
        await api.GetProfileAsync("secret", default); Check(handler.Authorization == "Bearer secret");
        handler.Response = Envelope(JsonSerializer.Serialize(Configuration(), new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        await api.GetConfigurationAsync(default); Check(handler.Authorization is null && handler.Uri!.Query == "?tenantName=open-platform");
    }),
    ("Malformed envelopes, partial DTOs, wrong tenants and invalid balances are rejected", async () =>
    {
        var handler = new RecordingHandler(); using var client = new HttpClient(handler); using var api = new AccountApi(client);
        foreach (var json in new[] { "{}", "{\"success\":true,\"code\":\"200\",\"data\":[]}", Envelope("null"), Envelope("[{}]"), Envelope("[null]") })
        { handler.Response = json; await Throws<AccountException>(() => api.GetKeysAsync("secret", default)); }
        handler.Response = Envelope("{\"tenantName\":\"other\"}");
        await Throws<AccountException>(() => api.GetConfigurationAsync(default));
        foreach (var json in new[] { "{}", "{\"currentBalance\":true}", "{\"currentBalance\":-1}", "{\"currentBalance\":\"12\"}" })
        { handler.Response = Envelope(json); await Throws<AccountException>(() => api.GetBalanceAsync("secret", default)); }
    }),
    ("Chinese and English code errors share field feedback without exposing server payloads", async () =>
    {
        var handler = new RecordingHandler(); using var client = new HttpClient(handler); using var api = new AccountApi(client);
        var cases = new (int Code, string Message, string Expected)[] {
            (400, "验证码错误", "Invalid code. Check it and try again."),
            (400, "Invalid verification code", "Invalid code. Check it and try again."),
            (400, "OTP mismatch", "Invalid code. Check it and try again."),
            (400, "验证码已过期", "This code has expired. Request a new one."),
            (400, "The email code has expired", "This code has expired. Request a new one."),
            (400, "图形验证码错误", "Security verification failed. Please try again."),
            (400, "Captcha verification code expired", "Security verification failed. Please try again."),
            (429, "Invalid verification code", "Too many requests. Please wait and try again."),
            (503, "Invalid verification code", "The service is temporarily unavailable. Please try again."),
            (400, "internal account details uk-do-not-display", "Unable to complete the request. Check your details and try again.")
        };
        foreach (var item in cases)
        {
            handler.Response = JsonSerializer.Serialize(new { success = false, code = item.Code, message = item.Message });
            var error = await Throws<AccountException>(() => api.GetProfileAsync("isolated", default));
            Check(error.Message == item.Expected && LoginViewModel.SignInErrorMessage(error, false) == item.Expected);
        }
    }),
    ("HTTP and business-level authentication failures preserve their classification", async () =>
    {
        var handler = new RecordingHandler { Status = HttpStatusCode.Unauthorized, Response = "not json" };
        using var client = new HttpClient(handler); using var api = new AccountApi(client);
        Check((await Throws<AccountException>(() => api.GetProfileAsync("secret", default))).IsUnauthorized);
        handler.Status = HttpStatusCode.OK;
        foreach (int code in new[] { 401, 46002 })
        {
            handler.Response = $"{{\"success\":false,\"code\":{code},\"message\":\"secret\"}}";
            var error = await Throws<AccountException>(() => api.GetProfileAsync("secret", default));
            Check(error.IsUnauthorized && !error.Message.Contains("secret"));
        }
        Check(!new AccountException("forbidden", 403).IsUnauthorized);
    }),
    ("Oversized responses and cancellation are handled", async () =>
    {
        var handler = new RecordingHandler { Response = new string('x', 2 * 1024 * 1024 + 1) };
        using var client = new HttpClient(handler); using var api = new AccountApi(client);
        await Throws<AccountException>(() => api.GetProfileAsync("secret", default));
        using var canceled = new CancellationTokenSource(); canceled.Cancel();
        await Throws<OperationCanceledException>(() => api.GetProfileAsync("secret", canceled.Token));
    }),
};
int failed = 0;
foreach (var test in tests)
{
    try { await test.Run(); Console.WriteLine("PASS " + test.Name); }
    catch (Exception error) { failed++; Console.WriteLine("FAIL " + test.Name + ": " + error); }
}
Console.WriteLine($"{tests.Length - failed}/{tests.Length} account tests passed.");
return failed == 0 ? 0 : 1;

static void Check(bool value) { if (!value) throw new Exception("Assertion failed."); }
static async Task<T> Throws<T>(Func<Task> action) where T : Exception
{
    try { await action(); } catch (T error) { return error; }
    throw new Exception("Expected " + typeof(T).Name);
}
static string Envelope(string data) => "{\"success\":true,\"code\":200,\"data\":" + data + "}";
static AccountProfile Profile() => Fixtures.Profile();
static ApiKeyRecord Key(string uid = "key-1", string key = "uk-test", string owner = "owner", string status = "active", string tenant = "open-platform") => Fixtures.Key(uid, key, owner, status, tenant);
static LoginConfiguration Configuration(bool captcha = false, bool loginCaptcha = false) => Fixtures.Configuration(captcha, loginCaptcha);
static MemoryStorage Saved() => new() { Credential = new() { Kind = CredentialKind.AccountToken, Value = "account-token" } };

static class Fixtures
{
    public static AccountProfile Profile() => new() { Uid = "owner", Nickname = "Test User" };
    public static ApiKeyRecord Key(string uid = "key-1", string key = "uk-test", string owner = "owner", string status = "active", string tenant = "open-platform") =>
        new() { Uid = uid, ApiKey = key, UserUid = owner, Status = status, TenantName = tenant, Name = "Test" };
    public static LoginConfiguration Configuration(bool captcha = false, bool loginCaptcha = false) => new() { TenantName = "open-platform", EnableSmsLogin = true, EnableEmailLogin = true,
        EnableCaptcha = captcha, CaptchaRequiredOnLogin = loginCaptcha, SmsCodeLength = 6, EmailCodeLength = 6, SmsCodeCooldownSeconds = 60, EmailCodeCooldownSeconds = 60 };
}
sealed class FakeApi : IAccountApi
{
    public IReadOnlyList<ApiKeyRecord> Keys = [Fixtures.Key()];
    public Func<Task<AccountProfile>>? ProfileOverride;
    public Func<Task<double>>? BalanceOverride;
    public Action? OnLogout;
    public int Creates, Logouts, CodeRequests, LoginRequests, BalanceRequests;
    public string? LastProfileCredential;
    public Task<LoginConfiguration> GetConfigurationAsync(CancellationToken token) => Task.FromResult(Fixtures.Configuration());
    public Task SendCodeAsync(LoginMethod method, string account, CaptchaProof proof, CancellationToken token) { CodeRequests++; return Task.CompletedTask; }
    public Task<string> LoginAsync(LoginMethod method, string account, string code, CaptchaProof proof, CancellationToken token) { LoginRequests++; return Task.FromResult("account-token"); }
    public Task<AccountProfile> GetProfileAsync(string credential, CancellationToken token)
    { LastProfileCredential = credential; return ProfileOverride?.Invoke() ?? Task.FromResult(Fixtures.Profile()); }
    public Task<IReadOnlyList<ApiKeyRecord>> GetKeysAsync(string credential, CancellationToken token) => Task.FromResult(Keys);
    public Task<ApiKeyRecord> CreateKeyAsync(string credential, string name, CancellationToken token)
    { Creates++; return Task.FromResult(Fixtures.Key("created", "uk-created")); }
    public Task<double> GetBalanceAsync(string credential, CancellationToken token)
    { BalanceRequests++; return BalanceOverride?.Invoke() ?? Task.FromResult(123d); }
    public Task LogoutAsync(string credential, CancellationToken token) { Logouts++; OnLogout?.Invoke(); return Task.CompletedTask; }
}
sealed class MemoryStorage : IAccountStorage
{
    public SessionCredential? Credential;
    public CachedAccount? Cache;
    public bool FailSave;
    public SessionCredential? ReadCredential() => Credential;
    public void SaveCredential(SessionCredential value) { if (FailSave) throw new IOException("test"); Credential = value; }
    public void RemoveCredential() => Credential = null;
    public CachedAccount? ReadCache() => Cache;
    public void SaveCache(CachedAccount value) => Cache = value;
    public void RemoveCache() => Cache = null;
}
sealed class RecordingHandler : HttpMessageHandler
{
    public string Response = "{}";
    public HttpStatusCode Status = HttpStatusCode.OK;
    public Uri? Uri;
    public string? Body, Authorization;
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        token.ThrowIfCancellationRequested(); Uri = request.RequestUri; Authorization = request.Headers.Authorization?.ToString();
        Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
        return new(Status) { Content = new StringContent(Response, Encoding.UTF8, "application/json") };
    }
}
