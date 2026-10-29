namespace FaceNow.Core.User;

public interface IAccountApi
{
    Task<LoginConfiguration> GetConfigurationAsync(CancellationToken cancellationToken);
    Task SendCodeAsync(LoginMethod method, string account, CaptchaProof proof, CancellationToken cancellationToken);
    Task<string> LoginAsync(LoginMethod method, string account, string code, CaptchaProof proof, CancellationToken cancellationToken);
    Task<AccountProfile> GetProfileAsync(string credential, CancellationToken cancellationToken);
    Task<IReadOnlyList<ApiKeyRecord>> GetKeysAsync(string credential, CancellationToken cancellationToken);
    Task<ApiKeyRecord> CreateKeyAsync(string credential, string name, CancellationToken cancellationToken);
    Task<double> GetBalanceAsync(string credential, CancellationToken cancellationToken);
    Task LogoutAsync(string credential, CancellationToken cancellationToken);
}

public interface IAccountStorage
{
    SessionCredential? ReadCredential();
    void SaveCredential(SessionCredential credential);
    void RemoveCredential();
    CachedAccount? ReadCache();
    void SaveCache(CachedAccount account);
    void RemoveCache();
}

public interface IGenerationAccess
{
    bool HasVerifiedSession { get; }
    string GetVerifiedGenerationKey();
}
