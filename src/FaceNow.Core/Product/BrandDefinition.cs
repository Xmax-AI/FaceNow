namespace FaceNow.Core.Product;

public static class BrandDefinition
{
    public const string Watermark = "✦ FaceNow";
    public const int ReferenceWidth = 640, ReferenceHeight = 360, Margin = 12;
    public const int BrandFontSize = 11, BadgeFontSize = 10;
    public static string GenerationCaption => Localization.AppText.Get("AI Generation");
}
