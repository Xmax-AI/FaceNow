namespace FaceNow.Core.Media;

public sealed record BeautySettings(bool Enabled = false, float Smoothness = .5f, float Lightening = .5f, float Sharpness = 0, float Redness = 0)
{
    public void Validate()
    {
        if (new[] { Smoothness, Lightening, Sharpness, Redness }.Any(value => !float.IsFinite(value) || value < 0 || value > 1))
            throw new ArgumentOutOfRangeException(nameof(Smoothness));
    }
}

public interface IResultBeautyProcessor : IAsyncDisposable
{
    ValueTask<ResultFrame> ProcessAsync(ResultFrame frame, BeautySettings settings, CancellationToken cancellationToken);
}
