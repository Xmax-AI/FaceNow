//
//  BeautySettings.cs
//  FaceNow
//

namespace FaceNow.Core.Media;

/// <summary>
/// Stores the beauty settings applied to generated video.
/// </summary>
/// <param name="Enabled">Whether beauty processing is enabled.</param>
/// <param name="Smoothness">The smoothing strength, from zero through one.</param>
/// <param name="Lightening">The lightening strength, from zero through one.</param>
/// <param name="Sharpness">The sharpening strength, from zero through one.</param>
/// <param name="Redness">The redness strength, from zero through one.</param>
public sealed record BeautySettings(
    bool Enabled = false,
    float Smoothness = 0,
    float Lightening = 0,
    float Sharpness = 0,
    float Redness = 0
)
{
    /// <summary>
    /// Checks that each strength is finite and within the supported range.
    /// </summary>
    public void Validate()
    {
        if (new[] { Smoothness, Lightening, Sharpness, Redness }.Any(value => !float.IsFinite(value) || value < 0 || value > 1))
            throw new ArgumentOutOfRangeException(nameof(Smoothness));
    }
}
