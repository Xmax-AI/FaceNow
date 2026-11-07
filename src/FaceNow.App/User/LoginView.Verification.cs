using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;
using Windows.Media.Playback;

namespace FaceNow.App.User;

internal sealed partial class LoginView
{
    internal async Task VerifyCodeLoginAsync(int method)
    {
        if (!preview || user.HasVerifiedSession) throw new InvalidOperationException("Code login verification requires a signed-out preview account.");
        if (!model.IsChannelVisible(method)) throw new InvalidOperationException("The requested code channel is hidden for this edition.");
        if (!configurationLoaded) await LoadConfigurationAsync();
        methods.SelectedIndex = method; await Task.Delay(30);
        string destination = method == 0 ? "13800000000" : "preview@example.com";
        account.Text = destination;
        // TextChanged is queued; let the account draft settle before entering a code.
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (model.Account != destination && DateTime.UtcNow < deadline) await Task.Delay(10);
        code.Text = "123456";
        while (model.Code != "123456" && DateTime.UtcNow < deadline) await Task.Delay(10);
        await RunAsync(false);
        if (model.Cooldown <= 0) throw new InvalidOperationException("The code login fixture did not establish a resend countdown.");
        await RunAsync(true);
        if (!user.HasVerifiedSession) throw new InvalidOperationException($"Preview code login failed (ready={configurationLoaded}, presented={presented}, formBusy={model.IsBusy}, userBusy={user.IsBusy}, canSubmit={model.CanSubmit}, accountValid={model.ValidAccount}, codeLength={model.Code.Length}, apiKey={model.UsesApiKey}, error={model.Error}).");
    }

    internal async Task VerifyApiKeyLoginAsync()
    {
        if (!preview || user.HasVerifiedSession) throw new InvalidOperationException("API key verification requires a signed-out preview account.");
        methods.SelectedIndex = 2;
        key.Password = PreviewAccountApi.Key;
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (model.ApiKey != PreviewAccountApi.Key && DateTime.UtcNow < deadline) await Task.Delay(10);
        await RunAsync(true);
        if (!user.HasVerifiedSession) throw new InvalidOperationException("Preview API key login failed.");
    }

    internal void VerifyResetAndRegionalChannels()
    {
        if (model.Account.Length != 0 || model.Code.Length != 0 || model.ApiKey.Length != 0 || model.Cooldown != 0 || model.Error is not null
            || account.Text.Length != 0 || code.Text.Length != 0 || key.Password.Length != 0 || rejectedKey is not null || rejectedCodes.Count != 0
            || send.Text != AppText.Get("Get Code") || submittingLogin || sendingCode || model.UsesApiKey)
            throw new InvalidOperationException("Successful login left form input, validation or countdown state behind.");
        var names = new List<string>();
        void Visit(DependencyObject parent)
        {
            if (parent is Button { Visibility: Visibility.Visible } button) names.Add(Microsoft.UI.Xaml.Automation.AutomationProperties.GetName(button));
            for (int i = 0; i < Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(parent); ++i)
                Visit(Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(parent, i));
        }
        Visit(methods);
        string primary = FaceNow.Core.Product.ProductProfile.Current.ShowsPhoneLogin ? "Phone" : "Email";
        if (!names.SequenceEqual(new[] { AppText.Get(primary), AppText.Get("API Key") }) || methods.SelectedIndex != model.DefaultIndex)
            throw new InvalidOperationException("The login selector did not expose exactly the two regional channels or restore its default.");
    }

    internal async Task VerifyVideoPlaybackAsync()
    {
        var deadline = DateTime.UtcNow.AddSeconds(15);
        var initial = player.PlaybackSession.Position;
        while (DateTime.UtcNow < deadline)
        {
            if (videoFailure is not null) throw new InvalidOperationException("Login video failed: " + videoFailure);
            if (media.IsLoaded && media.Visibility == Visibility.Visible && player.PlaybackSession.NaturalVideoWidth > 0
                && player.PlaybackSession.Position > initial + TimeSpan.FromMilliseconds(300)) return;
            await Task.Delay(100);
        }
        throw new InvalidOperationException($"Login video did not advance: animations={LoginMotion.Enabled}, visible={media.Visibility}, loaded={media.IsLoaded}, state={player.PlaybackSession.PlaybackState}, position={player.PlaybackSession.Position}, source={player.Source is not null}.");
    }

    private async Task VerifyVideoLifecycleAsync()
    {
        await VerifyVideoPlaybackAsync();
        if (!player.IsMuted || !player.IsLoopingEnabled) throw new InvalidOperationException("Login video must remain muted and looping.");
        SetPresented(false);
        await Task.Delay(200);
        var paused = player.PlaybackSession.Position;
        await Task.Delay(350);
        if (player.PlaybackSession.PlaybackState != MediaPlaybackState.Paused
            || (player.PlaybackSession.Position - paused).Duration() > TimeSpan.FromMilliseconds(100))
            throw new InvalidOperationException("Hidden login video did not pause.");
        SetPresented(true);
        await VerifyVideoPlaybackAsync();

        var duration = player.PlaybackSession.NaturalDuration;
        if (!player.PlaybackSession.CanSeek || duration < TimeSpan.FromSeconds(1))
            throw new InvalidOperationException("Login video duration or seek support is missing.");
        player.PlaybackSession.Position = duration - TimeSpan.FromMilliseconds(500);
        bool reachedEnd = false;
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < deadline)
        {
            if (videoFailure is not null) throw new InvalidOperationException("Login video failed: " + videoFailure);
            var position = player.PlaybackSession.Position;
            reachedEnd |= position >= duration - TimeSpan.FromMilliseconds(750);
            if (reachedEnd && position < duration / 2
                && player.PlaybackSession.PlaybackState == MediaPlaybackState.Playing) return;
            await Task.Delay(30);
        }
        throw new InvalidOperationException("Login video did not loop after reaching its end.");
    }

    internal FrameworkElement PhoneInputCaptureTarget => accountInput;
    internal object AccountTextLineMetrics() => accountInput.TextLineMetrics();
    internal FrameworkElement CodeInputCaptureTarget => codeInput;
    internal async Task PrepareLayoutCaptureAsync(int mode, string state = "idle")
    {
        if (!preview) throw new InvalidOperationException("Layout capture requires an isolated preview account.");
        if (!model.IsChannelVisible(mode)) throw new InvalidOperationException("Cannot capture a hidden regional login channel.");
        if (!configurationLoaded) await LoadConfigurationAsync();
        captureMode = true; player.Pause(); media.Visibility = Visibility.Collapsed;
        scenarios.SetPlaying(false); status.Visibility = Visibility.Collapsed;
        model.IsBusy = submittingLogin = sendingCode = false;
        rejectedKey = null; rejectedCodes.Clear();
        methods.SelectedIndex = mode; await Task.Delay(60);
        model.RecordSent(model.Method, mode == 1 ? "preview@example.com" : "13800000000", 0);
        account.Text = ""; key.Password = ""; await Task.Delay(60);
        code.Text = ""; await Task.Delay(60);
        IsTabStop = true; UseSystemFocusVisuals = false; Focus(FocusState.Programmatic);
        if (state == "focused") (mode == 2 ? (Control)key : account).Focus(FocusState.Programmatic);
        if (state is "enabled" or "loading" or "resend")
        {
            account.Text = mode == 1 ? "preview@example.com" : "13800000000"; await Task.Delay(60);
            code.Text = "123456"; await Task.Delay(60);
        }
        if (state == "typing")
        {
            account.Text = mode == 1 ? "preview@exa" : "1520314"; await Task.Delay(60);
            account.Focus(FocusState.Programmatic);
            account.SelectionStart = account.Text.Length;
        }
        if (state is "alignment-empty" or "alignment-text")
        {
            string expected = state == "alignment-text" ? account.PlaceholderText : "";
            model.SetAccount(expected); Render(); await Task.Delay(60);
            if (account.Text != expected || model.Account != expected)
                throw new InvalidOperationException("The native placeholder comparison did not reach its requested text state.");
            account.Focus(FocusState.Programmatic);
            account.SelectionStart = account.Text.Length;
        }
        if (state == "invalid")
        {
            key.Password = "uk-preview-rejected"; await Task.Delay(60);
            rejectedKey = key.Password; key.Focus(FocusState.Programmatic);
        }
        if (state == "loading") model.IsBusy = submittingLogin = true;
        if (state == "resend") model.RecordSent(model.Method, model.Account, 60);
        Render(); UpdateLayout(); await Task.Delay(350);
    }

    internal object VerifyLayoutBounds()
    {
        Rect Bounds(FrameworkElement view)
        {
            var origin = view.TransformToVisual(this).TransformPoint(new Point());
            return new(origin.X, origin.Y, view.ActualWidth, view.ActualHeight);
        }
        var selector = Bounds(methods); var first = Bounds(model.UsesApiKey ? keyInput : accountInput);
        var primary = Bounds(submit); var legal = Bounds(terms); var footer = Bounds(scenarios); var subtitleBounds = Bounds(subtitle);
        if (selector.X < ActualWidth / 2 + 40 || selector.Right > ActualWidth - 40)
            throw new InvalidOperationException("The account form must keep a 40-point inset inside the login column.");
        if (selector.Y < subtitleBounds.Bottom + 12 || first.Y < selector.Bottom + 12 || primary.Bottom > legal.Top - 8 || legal.Bottom > footer.Top - 12)
            throw new InvalidOperationException("Login header, inputs, actions or scenario footer overlap.");
        if (model.UsesApiKey)
        {
            if (codeInput.Visibility != Visibility.Collapsed || primary.Y < first.Bottom + 12)
                throw new InvalidOperationException("API-key mode did not preserve the first-input anchor.");
        }
        else
        {
            var verification = Bounds(codeInput); var editor = Bounds(code); var action = Bounds(send);
            if (verification.Y < first.Bottom + 8 || primary.Y < verification.Bottom + 12 || editor.Right > action.X - 6 || action.Right > verification.Right - 3)
                throw new InvalidOperationException("Verification editor and inline code action overlap.");
            double topInset = action.Top - verification.Top, bottomInset = verification.Bottom - action.Bottom;
            if (topInset < 4 * layoutScale || bottomInset < 4 * layoutScale || Math.Abs(topInset - bottomInset) > 1)
                throw new InvalidOperationException($"Inline code action is clipped or off-center (top {topInset:F2}, bottom {bottomInset:F2}).");
        }
        return new { viewport = new { width = ActualWidth, height = ActualHeight }, scale = layoutScale,
            icon = Bounds(appIcon), heading = Bounds(title), subtitle = subtitleBounds, selector, firstInput = first,
            codeInput = model.UsesApiKey ? (Rect?)null : Bounds(codeInput),
            codeAction = model.UsesApiKey ? (Rect?)null : Bounds(send),
            submit = primary, terms = legal, scenarios = footer, font = LoginTypography.Font.Source };
    }
}
