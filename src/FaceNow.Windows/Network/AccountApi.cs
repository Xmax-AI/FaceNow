using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using FaceNow.Core.User;

namespace FaceNow.Windows.Network;

/// <summary>The domestic account contract shared with macOS. Credentials are scoped to each request.</summary>
public sealed class AccountApi : IAccountApi, IDisposable
{
    private readonly HttpClient client;
    private readonly bool ownsClient;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull, RespectNullableAnnotations = true };
    public AccountApi(HttpClient? client = null)
    {
        ownsClient = client is null;
        this.client = client ?? new HttpClient(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
        { Timeout = TimeSpan.FromSeconds(30) };
    }
    public async Task<LoginConfiguration> GetConfigurationAsync(CancellationToken token)
    {
        var result = await SendAsync<LoginConfiguration>(HttpMethod.Get,
            "/baas/api/user/login/config?tenantName=" + AccountContract.Tenant, null, null, token);
        if (result.TenantName != AccountContract.Tenant)
            throw new AccountException("The service returned settings for a different account platform.");
        return result;
    }
    public async Task SendCodeAsync(LoginMethod method, string account, CaptchaProof proof, CancellationToken token)
    {
        await SendAsync<JsonElement>(HttpMethod.Post,
            $"/baas/api/message/public/{(method == LoginMethod.Sms ? "sms-code" : "email-code")}/send",
            new { tenantName = AccountContract.Tenant, phone = method == LoginMethod.Sms ? account : null,
                email = method == LoginMethod.Email ? account : null, proof.CaptchaTicket, proof.CaptchaRandStr }, null, token, allowEmpty: true);
    }
    public Task<string> LoginAsync(LoginMethod method, string account, string code, CaptchaProof proof, CancellationToken token) =>
        SendAsync<string>(HttpMethod.Post, "/baas/api/user/login",
            new { tenantName = AccountContract.Tenant, loginMethod = method == LoginMethod.Sms ? "sms" : "email",
                accountName = account, credential = code, proof.CaptchaTicket, proof.CaptchaRandStr }, null, token);
    public async Task<AccountProfile> GetProfileAsync(string credential, CancellationToken token)
    {
        var profile = await SendAsync<AccountProfile>(HttpMethod.Get, "/baas/api/user/info", null, credential, token);
        if (string.IsNullOrWhiteSpace(profile.Identity)) throw new AccountException("The service returned an invalid account response.");
        return profile;
    }
    public async Task<IReadOnlyList<ApiKeyRecord>> GetKeysAsync(string credential, CancellationToken token)
    {
        var keys = await SendAsync<ApiKeyRecord[]>(HttpMethod.Get, "/baas/api/user/apikey/list", null, credential, token);
        if (keys.Any(item => item is null)) throw new AccountException("The service returned an invalid account response.");
        return keys;
    }
    public Task<ApiKeyRecord> CreateKeyAsync(string credential, string name, CancellationToken token) =>
        SendAsync<ApiKeyRecord>(HttpMethod.Post, "/baas/api/user/apikey/create", new { name }, credential, token);
    public async Task<double> GetBalanceAsync(string credential, CancellationToken token)
    {
        var value = await SendAsync<JsonElement>(HttpMethod.Get, "/open/api/v1/points/balance", null, credential, token);
        if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty("currentBalance", out var balance)
            || balance.ValueKind != JsonValueKind.Number || !balance.TryGetDouble(out double number) || !double.IsFinite(number) || number < 0)
            throw new AccountException("The service returned an invalid balance.");
        return number;
    }
    public async Task LogoutAsync(string credential, CancellationToken token) =>
        _ = await SendAsync<JsonElement>(HttpMethod.Post, "/baas/api/user/logout", null, credential, token, allowEmpty: true);

    private async Task<T> SendAsync<T>(HttpMethod method, string path, object? body, string? credential,
        CancellationToken token, bool allowEmpty = false)
    {
        using var request = new HttpRequestMessage(method, new Uri(AccountContract.ServiceOrigin, path));
        request.Headers.Accept.Add(new("application/json"));
        if (!string.IsNullOrWhiteSpace(credential)) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential);
        if (body is not null) request.Content = JsonContent.Create(body, options: Json);
        try
        {
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
                throw new AccountException("Your session has expired. Please sign in again.", (int)response.StatusCode);
            // Bound even chunked responses before parsing; account responses never contain media.
            using var input = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
            using var output = new MemoryStream();
            byte[] buffer = new byte[8192];
            int count;
            while ((count = await input.ReadAsync(buffer, token).ConfigureAwait(false)) > 0)
            {
                if (output.Length + count > 2 * 1024 * 1024) throw new AccountException("The account response is too large.");
                output.Write(buffer, 0, count);
            }
            using var document = JsonDocument.Parse(output.ToArray());
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new JsonException();
            if (!response.IsSuccessStatusCode)
                throw new AccountException(ErrorMessage(root, (int)response.StatusCode), (int)response.StatusCode);
            if (!root.TryGetProperty("success", out var success) || success.ValueKind is not (JsonValueKind.True or JsonValueKind.False)
                || !root.TryGetProperty("code", out var code) || code.ValueKind != JsonValueKind.Number || !code.TryGetInt32(out int status)) throw new JsonException();
            if (!success.GetBoolean() || status != 200) throw new AccountException(ErrorMessage(root, status), status);
            if (!root.TryGetProperty("data", out var data) || data.ValueKind == JsonValueKind.Null)
            {
                if (allowEmpty) return default!;
                throw new JsonException();
            }
            return data.Deserialize<T>(Json) ?? throw new JsonException();
        }
        catch (HttpRequestException) { throw new AccountException("Unable to connect. Check your connection and try again."); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        { throw new AccountException("The request timed out. Please try again."); }
        catch (JsonException) { throw new AccountException("The service returned an invalid account response."); }
    }
    private static string ErrorMessage(JsonElement root, int code)
    {
        if (code is 401 or 46002) return "Your session has expired. Please sign in again.";
        if (code == 403) return "This account does not have permission to perform this action.";
        string message = root.TryGetProperty("message", out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
        if (message.Contains("验证码") && (message.Contains("过期") || message.Contains("失效"))) return "This code has expired. Request a new one.";
        if (message.Contains("图形验证码") || message.Contains("安全验证")) return "Security verification failed. Please try again.";
        if (message.Contains("验证码") && (message.Contains("错误") || message.Contains("不正确"))) return "Invalid code. Check it and try again.";
        if (code == 429) return "Too many requests. Please wait and try again.";
        // Do not surface arbitrary server payloads, which may echo credentials or internal details.
        return code >= 500 ? "The service is temporarily unavailable. Please try again." : "Unable to complete the request. Check your details and try again.";
    }
    public void Dispose() { if (ownsClient) client.Dispose(); }
}
