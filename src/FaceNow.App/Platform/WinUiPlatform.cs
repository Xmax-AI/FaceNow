// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using Microsoft.UI.Dispatching;
using FaceNow.Windows.Studio.Platform;

namespace FaceNow.App.Platform;

internal sealed class WinUiDispatcher(DispatcherQueue dispatcher) : IUiDispatcher
{
    public void InvokeAsync(Action action) => dispatcher.TryEnqueue(() => action());
    public IUiTimer CreateTimer(TimeSpan interval) => new WinUiTimer(dispatcher, interval);
}
internal sealed class WinUiTimer : IUiTimer
{
    private readonly DispatcherQueueTimer timer;
    public WinUiTimer(DispatcherQueue dispatcher, TimeSpan interval)
    { timer = dispatcher.CreateTimer(); timer.Interval = interval; timer.Tick += (_, _) => Tick?.Invoke(this, EventArgs.Empty); }
    public bool IsEnabled => timer.IsRunning;
    public event EventHandler? Tick;
    public void Start() => timer.Start();
    public void Stop() => timer.Stop();
}
