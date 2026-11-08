//
//  MainViewModel.Generation.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using Xmax.SDK;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    public async Task GenerateAsync()
    {
        if (IsClosing)
            return;
        if (generationAccess is not null)
            ApiKey = generationAccess.GetVerifiedGenerationKey();
        EnsureCreditsForStart();
        if (string.IsNullOrWhiteSpace(ApiKey))
            throw new InvalidOperationException("实时生成需要 Xmax API Key；摄像头预览可以单独使用。");
        if (string.IsNullOrWhiteSpace(Prompt))
            throw new InvalidOperationException("请输入生成提示词。");
        var selectedReference = AllReferences.FirstOrDefault(item => item.IsSelected);
        await EnsureSessionAsync();
        var currentSession = session ?? throw new OperationCanceledException();
        int current = revision;
        if (selectedReference is not null)
            MarkSelected(selectedReference);
        bool wasGenerating = RemoteVideo is not null || RemoteReady;
        var generation = new CancellationTokenSource();
        operationCancellation = generation;
        var generationToken = generation.Token;
        try
        {
            if (generationAccess is not null && generationAccess.GetVerifiedGenerationKey() != ApiKey)
                throw new OperationCanceledException("The active account credential changed.");
            EnsureCreditsForStart();
            await GenerateOnStreamAsync(
                currentSession, new(Prompt, ReferenceImage), FaceRestoration, current, generationToken
            );
        }
        catch (Exception) when (current != revision) { /* A terminal callback or explicit stop already owns cleanup and the error. */ }
        catch (Exception failure)
        {
            HandleGenerationFailure(failure, endsSession: !wasGenerating);
            await cleanup;
        }
        finally
        {
            if (current == revision)
            {
                operationCancellation?.Dispose();
                operationCancellation = null;
            }
        }
    }

    private async Task GenerateOnStreamAsync(
        IXmaxRealtimeManaging target,
        GenerationContext context,
        bool faceRestoration,
        int current,
        CancellationToken cancellationToken = default
    )
    {
        var stream = localStream ?? throw new OperationCanceledException();
        var result = await target.StartGenerationAsync(stream, context, faceRestoration, cancellationToken);
        if (current != revision)
            return;
        if (RemoteVideo == result.VideoTrack)
            return;
        RemoteVideo = result.VideoTrack;
        await EnsureCameraOutputAsync(current);
    }
}
