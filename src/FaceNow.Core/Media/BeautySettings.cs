namespace FaceNow.Core.Media;

public sealed record BeautySettings(bool Enabled = true, float Smoothness = 0, float Lightening = 0, float Sharpness = 0, float Redness = 0)
{
    public void Validate()
    {
        if (new[] { Smoothness, Lightening, Sharpness, Redness }.Any(value => !float.IsFinite(value) || value < 0 || value > 1))
            throw new ArgumentOutOfRangeException(nameof(Smoothness));
    }
}
