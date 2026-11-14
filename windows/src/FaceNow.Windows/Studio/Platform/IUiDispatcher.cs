//
//  IUiDispatcher.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
namespace FaceNow.Windows.Studio.Platform;

internal interface IUiDispatcher
{
    void InvokeAsync(
        Action action
    );

    IUiTimer CreateTimer(
        TimeSpan interval
    );
}
internal interface IUiTimer
{
    bool IsEnabled { get; }

    event EventHandler? Tick;

    void Start();

    void Stop();
}
