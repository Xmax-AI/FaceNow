using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace FaceNow.App.User;

internal sealed partial class LoginView
{
    internal FrameworkElement PhoneInputCaptureTarget => accountInput;
    internal FrameworkElement CodeInputCaptureTarget => codeInput;
    internal async Task PrepareLayoutCaptureAsync(int mode, string state = "idle")
    {
        if (!preview) throw new InvalidOperationException("Layout capture requires an isolated preview account.");
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
            account.Text = "1520314"; await Task.Delay(60);
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
            throw new InvalidOperationException("The account form escaped its macOS column margins.");
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
