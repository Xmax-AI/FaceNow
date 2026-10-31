using FaceNow.Core.User;

namespace FaceNow.App.User;

/// <summary>Explicit UI-preview fixture. Never reads credentials or contacts an account service.</summary>
internal sealed class PreviewAccountApi : IAccountApi
{
    internal const string Key = "uk-facenow-isolated-preview";
    public Task<LoginConfiguration> GetConfigurationAsync(CancellationToken token) => Task.FromResult(new LoginConfiguration
    {
        TenantName = AccountContract.Tenant, EnableSmsLogin = true, EnableEmailLogin = true,
        EnableCaptcha = false, CaptchaRequiredOnLogin = false, EmailCodeLength = 6, SmsCodeLength = 6,
        EmailCodeCooldownSeconds = 60, SmsCodeCooldownSeconds = 60
    });
    public Task SendCodeAsync(LoginMethod method, string account, CaptchaProof proof, CancellationToken token) => Task.CompletedTask;
    public Task<string> LoginAsync(LoginMethod method, string account, string code, CaptchaProof proof, CancellationToken token) => Task.FromResult("preview-token");
    public Task<AccountProfile> GetProfileAsync(string credential, CancellationToken token) =>
        Task.FromResult(new AccountProfile { Uid = "preview-user", Nickname = "Preview account", Email = "preview@example.com" });
    public Task<IReadOnlyList<ApiKeyRecord>> GetKeysAsync(string credential, CancellationToken token) => Task.FromResult<IReadOnlyList<ApiKeyRecord>>(
        [new() { Uid = "preview-key", TenantName = AccountContract.Tenant, UserUid = "preview-user", Name = "Preview", ApiKey = Key, Status = "active" }]);
    public Task<ApiKeyRecord> CreateKeyAsync(string credential, string name, CancellationToken token) => throw new AccountException("Key creation is unavailable in preview.");
    public Task<double> GetBalanceAsync(string credential, CancellationToken token) => Task.FromResult(1234d);
    public Task LogoutAsync(string credential, CancellationToken token) => Task.CompletedTask;
}

internal sealed class PreviewAccountStorage : IAccountStorage
{
    private SessionCredential? credential;
    private CachedAccount? cache;
    internal PreviewAccountStorage(bool savedSession = false)
    {
        if (savedSession) credential = new() { Kind = CredentialKind.ApiKey, Value = PreviewAccountApi.Key, SelectedKeyUid = "preview-key" };
    }
    public SessionCredential? ReadCredential() => credential;
    public void SaveCredential(SessionCredential value) => credential = value;
    public void RemoveCredential() => credential = null;
    public CachedAccount? ReadCache() => cache;
    public void SaveCache(CachedAccount value) => cache = value;
    public void RemoveCache() => cache = null;
}
