using System.Text.Json;
using FaceNow.App.Controls;
using FaceNow.Core.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;

namespace FaceNow.App.User;

internal sealed class CaptchaPresenter(Grid host, Action selectApiKey)
{
    private static readonly string Origin = AccountContract.ServiceOrigin.GetLeftPart(UriPartial.Authority);
    public async Task<CaptchaProof> PresentAsync(string appId, string businessState, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(appId)) throw new AccountException("Security verification is unavailable. Please try again.");
        token.ThrowIfCancellationRequested();
        if (!File.Exists(Path.Combine(AppContext.BaseDirectory, "Assets", "Login", "captcha.html")))
            throw new AccountException(CaptchaStartupPolicy.ApplicationFilesMessage);
        try
        {
            if (string.IsNullOrWhiteSpace(CoreWebView2Environment.GetAvailableBrowserVersionString()))
                throw new FileNotFoundException();
            return await PresentChallengeAsync(appId, businessState, token);
        }
        catch (OperationCanceledException) { throw; }
        catch (AccountException) { throw; }
        catch (Exception failure)
        {
            var issue = CaptchaStartupPolicy.Classify(failure);
            if (issue is CaptchaStartupIssue.RuntimeMissing or CaptchaStartupIssue.UnsupportedRuntime)
            {
                await ShowRuntimeHelpAsync(issue, token);
                throw new OperationCanceledException("Verification component setup is required.", token);
            }
            throw new AccountException(CaptchaStartupPolicy.Message(issue));
        }
    }

    private async Task ShowRuntimeHelpAsync(CaptchaStartupIssue issue, CancellationToken token)
    {
        string guidance = issue == CaptchaStartupIssue.UnsupportedRuntime
            ? CaptchaStartupPolicy.Message(issue)
            : "Download and install Microsoft Edge WebView2 Runtime from Microsoft, then restart FaceNow.";
        var dialog = new ContentDialog
        {
            XamlRoot = host.XamlRoot,
            Title = AppText.Get("Security verification needs WebView2"),
            Content = new TextBlock
            {
                Text = AppText.Get(guidance) + "\n\n" + AppText.Get("You can also sign in with an existing Xmax API key."),
                TextWrapping = TextWrapping.Wrap
            },
            PrimaryButtonText = AppText.Get("Download WebView2"),
            SecondaryButtonText = AppText.Get("Sign in with API Key"),
            CloseButtonText = AppText.Get("Cancel"),
            DefaultButton = ContentDialogButton.Close
        };
        using var registration = token.Register(() => host.DispatcherQueue.TryEnqueue(() => dialog.Hide()));
        token.ThrowIfCancellationRequested();
        var result = await dialog.ShowAsync();
        token.ThrowIfCancellationRequested();
        if (result == ContentDialogResult.Primary)
        {
            try
            {
                if (!await global::Windows.System.Launcher.LaunchUriAsync(new(CaptchaStartupPolicy.DownloadUrl)))
                    throw new InvalidOperationException();
            }
            catch { throw new AccountException("The Microsoft download page could not be opened. Install Microsoft Edge WebView2 Runtime and try again."); }
        }
        else if (result == ContentDialogResult.Secondary) selectApiKey();
    }

    private async Task<CaptchaProof> PresentChallengeAsync(string appId, string businessState, CancellationToken token)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(TimeSpan.FromSeconds(90));
        var completion = new TaskCompletionSource<CaptchaProof>(TaskCreationOptions.RunContinuationsAsynchronously);
        bool cancelledByUser = false;
        using var registration = timeout.Token.Register(() => completion.TrySetCanceled(timeout.Token));
        var overlay = new Grid { Background = Theme.Brush("#D9FFFFFF") };
        var surface = new Grid { Width = 520, Height = 560, Background = Theme.Brush("#FFFFFF"), CornerRadius = new(24) };
        var web = new WebView2 { Margin = new(8, 54, 8, 8) };
        var cancel = new Pill { Text = AppText.Get("Cancel"), HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top, Margin = new(12) };
        cancel.Click += (_, _) => { cancelledByUser = true; timeout.Cancel(); };
        surface.Children.Add(web); surface.Children.Add(cancel); overlay.Children.Add(surface); host.Children.Add(overlay);
        string nonce = Guid.NewGuid().ToString("N");
        try
        {
            string dataDirectory = Path.Combine(FaceNow.Core.Product.ProductProfile.Current.DataDirectory, "WebView2");
            Directory.CreateDirectory(dataDirectory);
            var environment = await CoreWebView2Environment.CreateWithOptionsAsync("", dataDirectory, null).AsTask(timeout.Token);
            await web.EnsureCoreWebView2Async(environment).AsTask(timeout.Token);
            timeout.Token.ThrowIfCancellationRequested();
            var browser = web.CoreWebView2;
            browser.Settings.AreDevToolsEnabled = false;
            browser.Settings.AreDefaultContextMenusEnabled = false;
            browser.Settings.AreHostObjectsAllowed = false;
            // Serve the local verification page under the account service origin without passing credentials.
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
        catch (OperationCanceledException) when (!cancelledByUser && !token.IsCancellationRequested && timeout.IsCancellationRequested)
        { throw new AccountException("Security verification timed out. Please try again."); }
        finally
        {
            try { web.Close(); } catch { /* Native initialization may have failed before the control can close normally. */ }
            host.Children.Remove(overlay);
        }
    }
}
