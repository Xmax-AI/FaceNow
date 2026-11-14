//
//  AccountContracts.cs
//  FaceNow
//

namespace FaceNow.Core.User;

/// <summary>
/// Defines the account service calls used by the application session.
/// </summary>
public interface IAccountApi
{
    /// <summary>
    /// Loads the sign-in methods and verification requirements.
    /// </summary>
    Task<LoginConfiguration> GetConfigurationAsync(
        CancellationToken cancellationToken
    );

    /// <summary>
    /// Requests a verification code for the selected account and sign-in method.
    /// </summary>
    Task SendCodeAsync(
        LoginMethod method,
        string account,
        CaptchaProof proof,
        CancellationToken cancellationToken
    );

    /// <summary>
    /// Exchanges a verification code for an account token.
    /// </summary>
    Task<string> LoginAsync(
        LoginMethod method,
        string account,
        string code,
        CaptchaProof proof,
        CancellationToken cancellationToken
    );

    /// <summary>
    /// Loads the profile associated with a credential.
    /// </summary>
    Task<AccountProfile> GetProfileAsync(
        string credential,
        CancellationToken cancellationToken
    );

    /// <summary>
    /// Lists the generation keys visible to the authenticated account.
    /// </summary>
    Task<IReadOnlyList<ApiKeyRecord>> GetKeysAsync(
        string credential,
        CancellationToken cancellationToken
    );

    /// <summary>
    /// Creates a named generation key for the authenticated account.
    /// </summary>
    Task<ApiKeyRecord> CreateKeyAsync(
        string credential,
        string name,
        CancellationToken cancellationToken
    );

    /// <summary>
    /// Reads the remaining credit balance for the authenticated account.
    /// </summary>
    Task<double> GetBalanceAsync(
        string credential,
        CancellationToken cancellationToken
    );

    /// <summary>
    /// Ends the account session associated with the credential.
    /// </summary>
    Task LogoutAsync(
        string credential,
        CancellationToken cancellationToken
    );
}

/// <summary>
/// Stores the sign-in credential separately from the cached account presentation.
/// </summary>
public interface IAccountStorage
{
    /// <summary>
    /// Reads the saved credential, or null if no credential is stored.
    /// </summary>
    SessionCredential? ReadCredential();

    /// <summary>
    /// Replaces the saved credential and its selected generation key.
    /// </summary>
    void SaveCredential(
        SessionCredential credential
    );

    /// <summary>
    /// Removes the saved sign-in credential.
    /// </summary>
    void RemoveCredential();

    /// <summary>
    /// Reads cached account presentation, or null if no cache is stored.
    /// </summary>
    CachedAccount? ReadCache();

    /// <summary>
    /// Replaces the cached account presentation.
    /// </summary>
    void SaveCache(
        CachedAccount account
    );

    /// <summary>
    /// Removes the cached account presentation.
    /// </summary>
    void RemoveCache();
}

/// <summary>
/// Supplies account checks and credentials for generation.
/// </summary>
public interface IGenerationAccess
{
    /// <summary>
    /// Gets whether the account session has been verified by the service.
    /// </summary>
    bool HasVerifiedSession { get; }

    /// <summary>
    /// Returns the active generation key of the verified account.
    /// </summary>
    string GetVerifiedGenerationKey();

    /// <summary>
    /// Checks the last confirmed credit balance before starting generation.
    /// </summary>
    void EnsureSufficientCredits();
}
