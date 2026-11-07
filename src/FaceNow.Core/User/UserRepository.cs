using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace FaceNow.Core.User;

/// <summary>Application-scoped account state. Call from the owning UI context.</summary>
public sealed class UserRepository(IAccountApi api, IAccountStorage storage) : IGenerationAccess, IDisposable
{
    private SessionCredential? credential;
    private CancellationTokenSource lifetime = new();
    private long version;
    private bool creditsBusy;
    public event Action? Changed;
    public SessionState State { get; private set; }
    public AccountProfile? Profile { get; private set; }
    public IReadOnlyList<ApiKeyRecord> Keys { get; private set; } = [];
    public string? SelectedKeyUid { get; private set; }
    public bool IsBusy { get; private set; }
    public bool HasVerifiedSession => State == SessionState.Verified && Profile is not null;
    public bool CanAccessHome => State != SessionState.SignedOut && credential is not null;
    public double? RemainingCredits { get; private set; }
    public bool HasInsufficientCredits => CreditPolicy.IsInsufficient(RemainingCredits);
    public string? Notice { get; private set; }
    public string DisplayName => Profile?.DisplayName ?? "Account";
    public string? SessionApiKeySuffix => credential is { Kind: CredentialKind.ApiKey, Value.Length: > 4 }
        ? credential.Value[^4..] : null;
    public Task<LoginConfiguration> GetConfigurationAsync(CancellationToken token) => api.GetConfigurationAsync(token);

    /// <summary>Loads presentation before the first window frame, without any account request.</summary>
    public void LoadCachedSession()
    {
        if (IsBusy || CanAccessHome) return;
        try
        {
            var saved = storage.ReadCredential();
            if (saved is null) return;
            if (!Enum.IsDefined(saved.Kind) || string.IsNullOrWhiteSpace(saved.Value))
                throw new AccountException("Your saved session is invalid.", 401);
            credential = saved;
            SelectedKeyUid = saved.SelectedKeyUid;
            var cached = storage.ReadCache();
            Profile = cached?.CredentialDigest == Digest(saved.Value) && cached.Profile is not null && !string.IsNullOrWhiteSpace(cached.Profile.Identity)
                ? cached.Profile : null;
            State = SessionState.Cached;
            Publish();
        }
        catch (Exception error) { RejectSession(error, "Unable to restore your account. Please sign in again."); }
    }

    public async Task RestoreAsync(string? legacyKey = null)
    {
        if (IsBusy) return;
        var operation = Begin();
        try
        {
            var saved = storage.ReadCredential();
            if (saved is null && !string.IsNullOrWhiteSpace(legacyKey))
                saved = new() { Kind = CredentialKind.ApiKey, Value = legacyKey.Trim() };
            if (saved is null) return;
            if (!Enum.IsDefined(saved.Kind) || string.IsNullOrWhiteSpace(saved.Value))
                throw new AccountException("Your saved session is invalid. Please sign in again.", 401);
            credential = saved;
            SelectedKeyUid = saved.SelectedKeyUid;
            var cached = storage.ReadCache();
            Profile = cached?.CredentialDigest == Digest(saved.Value) && cached.Profile is not null && !string.IsNullOrWhiteSpace(cached.Profile.Identity)
                ? cached.Profile : null;
            State = SessionState.Cached;
            Publish();
            await ValidateAndCommitAsync(saved, operation.Version, operation.Token);
        }
        catch (OperationCanceledException) when (!IsCurrent(operation.Version)) { }
        catch (Exception error)
        {
            if (!IsCurrent(operation.Version)) return;
            RejectSession(error, error is AccountException { IsUnauthorized: true }
                ? "Your session has expired. Please sign in again."
                : "Unable to verify your session. Check your connection and sign in again.");
        }
        finally { End(operation.Version); }
    }

    public async Task SignInWithKeyAsync(string value, CancellationToken token = default)
    {
        var key = value.Trim();
        if (!key.StartsWith("uk-", StringComparison.Ordinal) || key.Length <= 3)
            throw new AccountException("Invalid API key. Check it and try again.", 400);
        await SignInAsync(new() { Kind = CredentialKind.ApiKey, Value = key }, token);
    }

    public async Task SignInWithCodeAsync(LoginConfiguration configuration, LoginMethod method,
        string account, string code, CaptchaProof proof, CancellationToken token = default)
    {
        if (configuration.TenantName != AccountContract.Tenant || !configuration.Supports(method))
            throw new AccountException("This sign-in method is currently unavailable.");
        ValidateCodeOperation(configuration, method, account, proof, login: true);
        if (code.Length != configuration.CodeLength(method) || code.Any(c => c is < '0' or > '9'))
            throw new AccountException("Enter the complete verification code.");
        if (IsBusy) throw new AccountException("Please wait for the current operation to finish.");
        var operation = Begin(token);
        try
        {
            string received = await api.LoginAsync(method, account.Trim(), code, proof, operation.Token);
            EnsureCurrent(operation.Version, operation.Token);
            if (string.IsNullOrWhiteSpace(received)) throw new AccountException("The service returned an invalid session.");
            await ValidateAndCommitAsync(new() { Kind = CredentialKind.AccountToken, Value = received }, operation.Version, operation.Token);
        }
        finally { End(operation.Version); }
    }

    public Task SendCodeAsync(LoginConfiguration configuration, LoginMethod method, string account,
        CaptchaProof proof, CancellationToken token)
    {
        if (configuration.TenantName != AccountContract.Tenant || !configuration.Supports(method))
            throw new AccountException("This sign-in method is currently unavailable.");
        ValidateCodeOperation(configuration, method, account, proof, login: false);
        return api.SendCodeAsync(method, account.Trim(), proof, token);
    }

    private async Task SignInAsync(SessionCredential candidate, CancellationToken token)
    {
        if (IsBusy) throw new AccountException("Please wait for the current operation to finish.");
        var operation = Begin(token);
        try { await ValidateAndCommitAsync(candidate, operation.Version, operation.Token); }
        finally { End(operation.Version); }
    }

    private async Task ValidateAndCommitAsync(SessionCredential candidate, long operation, CancellationToken token)
    {
        IReadOnlyList<ApiKeyRecord>? records = null;
        ApiKeyRecord? loginKey = null;
        if (candidate.Kind == CredentialKind.ApiKey)
        {
            records = await api.GetKeysAsync(candidate.Value, token);
            EnsureCurrent(operation, token);
            loginKey = records.FirstOrDefault(item => item.ApiKey == candidate.Value && item.Status == "active"
                && item.TenantName == AccountContract.Tenant && !string.IsNullOrWhiteSpace(item.UserUid));
            if (loginKey is null) throw new AccountException("This API key is inactive or unavailable.", 401);
        }
        var profile = await api.GetProfileAsync(candidate.Value, token);
        EnsureCurrent(operation, token);
        if (string.IsNullOrWhiteSpace(profile.Identity)) throw new AccountException("The service returned an invalid account.");
        if (loginKey is not null && profile.Identity != loginKey.UserUid)
            throw new AccountException("The API key does not belong to this account.", 401);
        // An empty list is valid; creating a billable-service credential is an explicit user action.
        records ??= await api.GetKeysAsync(candidate.Value, token);
        EnsureCurrent(operation, token);
        var active = records.Where(item => item.IsActiveFor(profile.Identity)).ToArray();
        string? selected = active.FirstOrDefault(item => item.Uid == candidate.SelectedKeyUid)?.Uid
            ?? (loginKey is not null ? active.FirstOrDefault(item => item.Uid == loginKey.Uid)?.Uid : null)
            ?? active.FirstOrDefault()?.Uid;
        var committed = new SessionCredential { Kind = candidate.Kind, Value = candidate.Value, SelectedKeyUid = selected };
        storage.SaveCredential(committed);
        credential = committed;
        Profile = profile;
        Keys = active;
        SelectedKeyUid = selected;
        RemainingCredits = null;
        Notice = null;
        State = SessionState.Verified;
        TryCache(() => storage.SaveCache(new() { CredentialDigest = Digest(candidate.Value), Profile = profile }));
        Publish();
    }

    public string GetVerifiedGenerationKey()
    {
        if (!HasVerifiedSession) throw new AccountException("Please wait for your account to be verified, or sign in again.");
        return Keys.FirstOrDefault(item => item.Uid == SelectedKeyUid && item.IsActiveFor(Profile!.Identity))?.ApiKey
            ?? throw new AccountException("Choose or create an API key in API key settings before starting.");
    }

    /// <summary>Checks cached balance only; camera startup must not request billing data.</summary>
    public void EnsureSufficientCredits()
    {
        if (HasInsufficientCredits)
            throw new AccountException(CreditPolicy.InsufficientMessage, CreditPolicy.InsufficientCode);
    }

    public void SelectKey(string uid)
    {
        if (!HasVerifiedSession || IsBusy || credential is null || !Keys.Any(item => item.Uid == uid)) return;
        var next = new SessionCredential { Kind = credential.Kind, Value = credential.Value, SelectedKeyUid = uid };
        storage.SaveCredential(next);
        credential = next;
        SelectedKeyUid = uid;
        Publish();
    }

    public async Task CreateKeyAsync()
    {
        if (!HasVerifiedSession || IsBusy || credential is null) return;
        var saved = credential;
        var operation = Begin();
        try
        {
            var key = await api.CreateKeyAsync(saved.Value, "FaceNow", operation.Token);
            EnsureCurrent(operation.Version, operation.Token);
            if (!key.IsActiveFor(Profile!.Identity)) throw new AccountException("The service returned an invalid API key.");
            var next = new SessionCredential { Kind = saved.Kind, Value = saved.Value, SelectedKeyUid = key.Uid };
            storage.SaveCredential(next);
            Keys = new[] { key }.Concat(Keys.Where(item => item.Uid != key.Uid)).ToArray();
            credential = next;
            SelectedKeyUid = key.Uid;
        }
        catch (AccountException error) when (error.IsUnauthorized)
        { if (IsCurrent(operation.Version)) RejectSession(error); throw; }
        finally { End(operation.Version); }
    }

    public async Task RefreshCreditsAsync()
    {
        if (!HasVerifiedSession || credential is null || creditsBusy) return;
        long current = version;
        string value = credential.Value;
        var token = lifetime.Token;
        creditsBusy = true;
        try
        {
            double balance = await api.GetBalanceAsync(value, token);
            EnsureCurrent(current, token);
            if (!double.IsFinite(balance) || balance < 0) throw new AccountException("The service returned an invalid balance.");
            RemainingCredits = balance;
        }
        catch (OperationCanceledException) when (!IsCurrent(current)) { }
        catch (AccountException error) when (error.IsUnauthorized)
        { if (IsCurrent(current)) RejectSession(error); }
        finally { if (IsCurrent(current)) { creditsBusy = false; Publish(); } }
    }

    /// <summary>Stops publication immediately; the application stops generation before calling this.</summary>
    public async Task SignOutAsync()
    {
        var previous = credential;
        Invalidate();
        ClearPublishedState();
        Exception? storageError = null;
        try { storage.RemoveCredential(); } catch (Exception error) { storageError = error; }
        TryCache(storage.RemoveCache);
        Publish();
        if (previous?.Kind == CredentialKind.AccountToken)
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(8));
            try { await api.LogoutAsync(previous.Value, timeout.Token); } catch { /* Local logout is authoritative. */ }
        }
        if (storageError is not null) throw new AccountException("Signed out, but the saved credential could not be removed. " + storageError.Message);
    }

    private (long Version, CancellationToken Token) Begin(CancellationToken token = default)
    {
        Invalidate(token);
        IsBusy = true;
        Notice = null;
        Publish();
        return (version, lifetime.Token);
    }
    private void End(long operation) { if (IsCurrent(operation)) { IsBusy = false; Publish(); } }
    private bool IsCurrent(long operation) => operation == version;
    private void EnsureCurrent(long operation, CancellationToken token)
    { token.ThrowIfCancellationRequested(); if (!IsCurrent(operation)) throw new OperationCanceledException(); }
    private void Invalidate(CancellationToken token = default)
    { ++version; lifetime.Cancel(); lifetime.Dispose(); lifetime = CancellationTokenSource.CreateLinkedTokenSource(token); creditsBusy = false; }
    private void RejectSession(Exception error, string? notice = null)
    {
        Invalidate();
        if (error is AccountException { IsUnauthorized: true })
        {
            try { storage.RemoveCredential(); } catch { Notice = "The saved credential could not be removed."; }
        }
        ClearPublishedState();
        Notice = notice ?? "Your session has expired. Please sign in again.";
        TryCache(storage.RemoveCache);
        Publish();
    }
    private void ClearPublishedState()
    { credential = null; State = SessionState.SignedOut; Profile = null; Keys = []; SelectedKeyUid = null; RemainingCredits = null; IsBusy = false; }
    private void TryCache(Action action) { try { action(); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    private static void ValidateCodeOperation(LoginConfiguration configuration, LoginMethod method, string account, CaptchaProof proof, bool login)
    {
        string destination = account.Trim();
        if (!Enum.IsDefined(method) || destination.Length > 254 || !Regex.IsMatch(destination,
            method == LoginMethod.Sms ? @"^1[3-9][0-9]{9}$" : @"^[^\s@]+@[^\s@]+\.[^\s@]+$", RegexOptions.CultureInvariant))
            throw new AccountException(method == LoginMethod.Sms ? "Enter a valid mainland China phone number." : "Enter a valid email address.");
        if (configuration.NeedsCaptcha(method, login) && (string.IsNullOrWhiteSpace(proof.CaptchaTicket) || string.IsNullOrWhiteSpace(proof.CaptchaRandStr)))
            throw new AccountException("Complete security verification before continuing.");
    }
    private static string Digest(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    private void Publish() => Changed?.Invoke();
    public void Dispose() { Invalidate(); lifetime.Dispose(); }
}
