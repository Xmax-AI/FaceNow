using System.Text.Json;
using FaceNow.Core.User;

namespace FaceNow.Windows.Security;

public sealed class AccountStorage : IAccountStorage
{
    private readonly ApiKeyStore credentialStore;
    private readonly string cachePath;
    public AccountStorage(string target = "XMAX.AI/FaceNow/Account", string? cacheDirectory = null)
    {
        credentialStore = new(target);
        cachePath = Path.Combine(cacheDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FaceNow"), "account-profile.json");
    }
    public SessionCredential? ReadCredential()
    {
        string value = credentialStore.Load();
        if (value.Length == 0) return null;
        try { return JsonSerializer.Deserialize<SessionCredential>(value) ?? throw new JsonException(); }
        catch (JsonException) { credentialStore.Save(""); return null; }
    }
    public void SaveCredential(SessionCredential credential) => credentialStore.Save(JsonSerializer.Serialize(credential));
    public void RemoveCredential() => credentialStore.Save("");
    public CachedAccount? ReadCache()
    {
        try { return JsonSerializer.Deserialize<CachedAccount>(File.ReadAllText(cachePath)); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return null; }
    }
    public void SaveCache(CachedAccount account)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(cachePath)!);
        string temporary = cachePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, JsonSerializer.Serialize(account)); File.Move(temporary, cachePath, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public void RemoveCache() => File.Delete(cachePath);
}
