using System.Text.Json;
using FaceNow.App.Controls;
using FaceNow.Core.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;

namespace FaceNow.App.User;

internal sealed class CaptchaPresenter(Grid host)
{
    private static readonly string Origin = AccountContract.ServiceOrigin.GetLeftPart(UriPartial.Authority);
    public async Task<CaptchaProof> PresentAsync(string appId, string businessState, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(appId)) throw new AccountException("Security verification is unavailable. Please try again.");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(TimeSpan.FromSeconds(90));
        var completion = new TaskCompletionSource<CaptchaProof>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var registration = timeout.Token.Register(() => completion.TrySetCanceled(timeout.Token));
        var overlay = new Grid { Background = Theme.Brush("#D9FFFFFF") };
        var surface = new Grid { Width = 520, Height = 560, Background = Theme.Brush("#FFFFFF"), CornerRadius = new(24) };
        var web = new WebView2 { Margin = new(8, 54, 8, 8) };
        var cancel = new Pill { Text = AppText.Get("Cancel"), HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top, Margin = new(12) };
        cancel.Click += (_, _) => completion.TrySetCanceled();
        surface.Children.Add(web); surface.Children.Add(cancel); overlay.Children.Add(surface); host.Children.Add(overlay);
        string nonce = Guid.NewGuid().ToString("N");
        try
        {
            string dataDirectory = Path.Combine(FaceNow.Core.Product.ProductProfile.Current.DataDirectory, "WebView2");
            var environment = await CoreWebView2Environment.CreateWithOptionsAsync("", dataDirectory, null);
            await web.EnsureCoreWebView2Async(environment);
            timeout.Token.ThrowIfCancellationRequested();
            var browser = web.CoreWebView2;
            browser.Settings.AreDevToolsEnabled = false;
            browser.Settings.AreDefaultContextMenusEnabled = false;
            browser.Settings.AreHostObjectsAllowed = false;
            // Match macOS's HTTPS base origin; no account credential or API key enters this WebView.
            browser.SetVirtualHostNameToFolderMapping(AccountContract.ServiceOrigin.Host, Path.Combine(AppContext.BaseDirectory, "Assets", "Login"), CoreWebView2HostResourceAccessKind.DenyCors);
            browser.NavigationStarting += (_, args) =>
            {
                if (!Uri.TryCreate(args.Uri, UriKind.Absolute, out var uri) || uri.GetLeftPart(UriPartial.Authority) != Origin
                    || uri.AbsolutePath != "/captcha.html") args.Cancel = true;
            };
            browser.NewWindowRequested += (_, args) => args.Handled = true;
            browser.PermissionRequested += (_, args) => args.State = CoreWebView2PermissionState.Deny;
            browser.ProcessFailed += (_, _) => completion.TrySetException(new AccountException("Security verification could not be loaded. Please try again."));
            browser.WebMessageReceived += (_, args) =>
            {
                if (args.Source != Origin + "/captcha.html") return;
                try
                {
                    using var document = JsonDocument.Parse(args.WebMessageAsJson);
                    var value = document.RootElement;
                    if (value.GetProperty("nonce").GetString() != nonce) return;
                    int result = value.GetProperty("ret").GetInt32();
                    if (result == 2) { completion.TrySetCanceled(); return; }
                    if (result == 0 && value.TryGetProperty("ticket", out var ticket) && value.TryGetProperty("randstr", out var random)
                        && !string.IsNullOrWhiteSpace(ticket.GetString()) && !string.IsNullOrWhiteSpace(random.GetString()))
                        completion.TrySetResult(new(ticket.GetString(), random.GetString()));
                    else completion.TrySetException(new AccountException("Security verification failed. Please try again."));
                }
                catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException) { }
            };
            browser.NavigationCompleted += async (_, args) =>
            {
                if (completion.Task.IsCompleted) return;
                if (!args.IsSuccess) { completion.TrySetException(new AccountException("Security verification could not be loaded. Check your connection.")); return; }
                try
                {
                    string options = JsonSerializer.Serialize(new { appId, businessState, nonce, language = FaceNow.Core.Product.ProductProfile.Current.CaptchaLanguage });
                    await browser.ExecuteScriptAsync($"window.startChallenge({options});");
                }
                catch { completion.TrySetException(new AccountException("Security verification could not be started. Please try again.")); }
            };
            browser.Navigate(Origin + "/captcha.html");
            return await completion.Task;
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested && timeout.IsCancellationRequested)
        { throw new AccountException("Security verification timed out. Please try again."); }
        catch (System.Runtime.InteropServices.COMException failure) when (failure.HResult == unchecked((int)0x80070002))
        { throw new AccountException("Install Microsoft Edge WebView2 Runtime to complete security verification."); }
        finally { web.Close(); host.Children.Remove(overlay); }
    }
}
