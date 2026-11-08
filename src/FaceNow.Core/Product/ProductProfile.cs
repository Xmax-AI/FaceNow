//
//  ProductProfile.cs
//  FaceNow
//

using System.Globalization;

namespace FaceNow.Core.Product;

public enum ProductEdition
{
    Domestic, Overseas
}

/// <summary>One immutable regional identity for endpoints, language, storage and packaging.</summary>
public sealed record ProductProfile(
    ProductEdition Edition
)
{
#if FACENOW_OVERSEAS
    public static ProductProfile Current { get; } = new(ProductEdition.Overseas);
#else
    public static ProductProfile Current { get; } = new(ProductEdition.Domestic);
#endif
    public bool IsOverseas => Edition == ProductEdition.Overseas;

    public bool ShowsPhoneLogin => !IsOverseas;

    public bool ShowsEmailLogin => IsOverseas;

    public string Id => IsOverseas ? "FaceNowOverseas" : "FaceNow";

    public string DisplayName => IsOverseas ? "FaceNow Overseas" : "FaceNow";

    public string Language => IsOverseas ? "en" : "zh-Hans";

    public CultureInfo Culture => CultureInfo.GetCultureInfo(Language);

    public Uri ApiOrigin => new(IsOverseas ? "https://api.xmax.cloud" : "https://cloud.xmax.22duck.cn");

    public Uri AssetOrigin => new(IsOverseas ? "https://cdn.xmax.ai" : "https://cdn.22duck.cn");

    public Uri PlatformOrigin => new(IsOverseas ? "https://platform.xmax.ai" : "https://platform.xmaxai.com");

    public Uri Website => new(IsOverseas ? "https://xmax.ai" : "https://xmaxai.com");

    public string CaptchaLanguage => IsOverseas ? "en" : "zh-cn";

    public string CredentialPrefix => "XMAX.AI/" + Id;

    public string RegistryPath => @"Software\XMAX.AI\" + Id;

    public string DataDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        Id
    );

    public string ResolveLink(
        string value
    )
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri))
            return value;
        if (uri.Scheme == "mailto")
            return "mailto:" + (IsOverseas ? "contact@xmax.ai" : "contact@xmaxai.com");
        if (uri.Host is "platform.xmax.ai" or "platform.xmaxai.com" or "platform.xmaxsi.com")
            return new Uri(PlatformOrigin, uri.PathAndQuery).ToString();
        if (uri.Host is "www.xmaxsi.com" or "www.xmaxai.com" or "www.xmax.ai" or "xmaxai.com" or "xmax.ai")
        {
            if (IsOverseas && uri.AbsolutePath == "/facenow/guide")
                return "http://xmax.ai/facenow/guide";
            return new Uri(Website, uri.PathAndQuery).ToString();
        }
        return value;
    }

    public string ResolveAsset(
        string value
    )
    {
        if (Uri.TryCreate(
            value,
            UriKind.Absolute,
            out var uri
        ) && uri.Host is "cdn.22duck.cn" or "cdn.xmax.ai")
            return new Uri(AssetOrigin, uri.PathAndQuery).ToString();
        return value;
    }
}
