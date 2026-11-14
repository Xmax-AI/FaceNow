//
//  AppText.cs
//  FaceNow
//

using System.Collections.Concurrent;
using System.Globalization;
using System.Resources;
using System.Security.Cryptography;
using System.Text;
using FaceNow.Core.Product;

namespace FaceNow.Core.Localization;

/// <summary>Explicit edition language; never changes the operating system's language or protocol values.</summary>
public static class AppText
{
    private static readonly ResourceManager Resources = new(
        "FaceNow.Core.Localization.Strings",
        typeof(AppText).Assembly
    );
    private static readonly ConcurrentDictionary<string, string> Cache = new();

    public static string Key(
        string source
    ) => "Text_" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(source)))[..16];

    public static string Get(
        string source
    )
    {
        if (Cache.TryGetValue(source, out var cached))
            return cached;
        string? translated = Resources.GetString(Key(source), ProductProfile.Current.Culture);
        if (translated is not null)
            Cache.TryAdd(source, translated);
        return translated ?? source;
    }

    public static string Format(
        string source,
        params object?[] values
    ) => string.Format(
        ProductProfile.Current.Culture,
        Get(source),
        values
    );

    public static string GetFor(
        string source,
        ProductProfile profile
    ) => Resources.GetString(
        Key(source),
        profile.Culture
    ) ?? source;
}
