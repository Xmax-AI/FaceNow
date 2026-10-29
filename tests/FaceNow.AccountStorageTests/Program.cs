using FaceNow.Core.User;
using FaceNow.Windows.Security;

if (args.Length != 3 || !Guid.TryParse(args[1], out var identity)) throw new ArgumentException("Pass mode, isolated UUID and cache directory.");
string target = "XMAX.AI/FaceNow/Account.Smoke." + identity.ToString("N");
var storage = new AccountStorage(target, args[2]);
const string value = "isolated-account-token-凭据";
switch (args[0])
{
    case "write":
        storage.SaveCredential(new() { Kind = CredentialKind.AccountToken, Value = value, SelectedKeyUid = "selected-key" });
        storage.SaveCache(new() { CredentialDigest = "non-secret-digest", Profile = new() { Uid = "isolated-owner", Nickname = "Preview" } });
        if (File.ReadAllText(Path.Combine(args[2], "account-profile.json")).Contains(value)) throw new Exception("Credential leaked into profile cache.");
        break;
    case "read":
        var credential = storage.ReadCredential();
        if (credential?.Value != value || credential.Kind != CredentialKind.AccountToken || credential.SelectedKeyUid != "selected-key"
            || storage.ReadCache()?.Profile.Identity != "isolated-owner") throw new Exception("Account did not restore across processes.");
        break;
    case "delete":
        storage.RemoveCredential(); storage.RemoveCache();
        break;
    case "empty":
        if (storage.ReadCredential() is not null || storage.ReadCache() is not null) throw new Exception("Account did not clear across processes.");
        // Corrupt entries fail closed and are removed from this isolated target only.
        new ApiKeyStore(target).Save("{broken-json");
        if (storage.ReadCredential() is not null || new ApiKeyStore(target).Load().Length != 0) throw new Exception("Corrupt credential was not removed.");
        break;
    default: throw new ArgumentException("Unknown mode.");
}
Console.WriteLine("PASS isolated Windows account storage " + args[0]);
