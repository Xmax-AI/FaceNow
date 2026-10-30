using FaceNow.App.Controls;
using FaceNow.Core.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage;
using Windows.System;

namespace FaceNow.App.User;

internal sealed partial class LoginView : UserControl, IDisposable
{
    private readonly UserRepository user;
    private readonly CaptchaPresenter captcha;
    private readonly bool preview;
    private readonly LoginViewModel model = new();
    private readonly CancellationTokenSource lifetime = new();
    private readonly LoginMethodSelector methods = new();
    private readonly TextBox account = Input("Enter your phone number");
    private readonly TextBox code = Input("Enter verification code");
    private readonly PasswordBox key = new() { PlaceholderText = "Enter your active Xmax API key" };
    private readonly LoginActionButton send = new("Get Code"), submit = new("Sign in");
    private readonly LoginInput accountInput, codeInput, keyInput;
    private readonly LoginScenarios scenarios = new();
    private readonly Grid layout = new() { Background = Theme.Brush("#FFFFFF") };
    private readonly Grid column = new(), formContent = new(), form = new();
    private readonly StackPanel heading = new();
    private readonly Grid inputArea = new();
    private readonly Image appIcon = new() { Source = new BitmapImage(new("ms-appx:///Assets/FaceNow.png")) };
    private readonly TextBlock title = LoginTypography.Text("Welcome to FaceNow", 34);
    private readonly TextBlock subtitle = LoginTypography.Text("Your new look for every camera moment", 17, "#6B7380");
    private readonly TextBlock terms = LoginTypography.Text("", 14, "#6B7380");
    private readonly TextBlock status = LoginTypography.Text("", 10, "#9CA3AF");
    private readonly MediaPlayer player = new() { IsLoopingEnabled = true, IsMuted = true };
    private readonly MediaPlayerElement media = new() { AreTransportControlsEnabled = false, Stretch = Stretch.UniformToFill };
    private MediaSource? videoSource;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer timer;
    private readonly Dictionary<LoginMethod, (string Value, string Message)> rejectedCodes = [];
    private string? rejectedKey, lastNotice;
    private string? videoFailure;
    private bool videoLoading;
    private bool updating, presented, configurationLoaded, configurationFailed, disposed, submittingLogin, sendingCode, captureMode;
    private double layoutScale = 1;
    internal Action<string?>? RequestError { get; set; }
    internal Action? SignedIn { get; set; }

    public LoginView(UserRepository user, Grid overlayHost, bool preview = false)
    {
        this.user = user; this.preview = preview; Visibility = Visibility.Collapsed;
        captcha = new(overlayHost);
        HorizontalContentAlignment = HorizontalAlignment.Stretch; VerticalContentAlignment = VerticalAlignment.Stretch;
        layout.ColumnDefinitions.Add(new()); layout.ColumnDefinitions.Add(new());
        var showcase = new Grid { Margin = new(20, 20, 0, 20), Background = Theme.Brush("#111318") };
        RoundedClip.Attach(showcase, 24);
        showcase.Children.Add(new Border { Background = new ImageBrush
        {
            ImageSource = new BitmapImage(new("ms-appx:///Assets/Login/FaceNowLoginPoster.png")),
            Stretch = Stretch.UniformToFill, AlignmentX = AlignmentX.Center, AlignmentY = AlignmentY.Center
        } });
        media.SetMediaPlayer(player); showcase.Children.Add(media);
        player.MediaOpened += (_, _) => DispatcherQueue.TryEnqueue(UpdateVideoPlayback);
        player.MediaFailed += (_, args) => DispatcherQueue.TryEnqueue(() =>
        {
            videoFailure = $"{args.Error}: {args.ErrorMessage} ({args.ExtendedErrorCode?.HResult:X8})";
            if (!disposed) media.Visibility = Visibility.Collapsed;
        });
        showcase.Children.Add(new Border { Background = new LinearGradientBrush
        {
            StartPoint = new(0, 0), EndPoint = new(0, 1), GradientStops = {
                new() { Color = Microsoft.UI.Colors.Transparent }, new() { Color = Theme.Brush("#C7000000").Color, Offset = 1 } }
        } });
        var caption = new StackPanel { Margin = new(32), Spacing = 12, VerticalAlignment = VerticalAlignment.Bottom };
        var slogan = LoginTypography.Text("Be Anyone.  Be You.", 38, "#FFFFFF"); slogan.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        caption.Children.Add(slogan);
        caption.Children.Add(LoginTypography.Text("Powered by the world-leading real-time video editing model from Xmax.ai", 12.5, "#CCFFFFFF"));
        showcase.Children.Add(caption); layout.Children.Add(showcase);

        formContent.HorizontalAlignment = HorizontalAlignment.Center;
        formContent.RowDefinitions.Add(new() { Height = GridLength.Auto });
        formContent.RowDefinitions.Add(new());
        formContent.RowDefinitions.Add(new() { Height = GridLength.Auto });
        title.TextAlignment = subtitle.TextAlignment = TextAlignment.Center;
        title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        appIcon.HorizontalAlignment = HorizontalAlignment.Center;
        heading.Children.Add(appIcon); heading.Children.Add(title); heading.Children.Add(subtitle); formContent.Children.Add(heading);
        for (int i = 0; i < 10; i++) form.RowDefinitions.Add(new() { Height = GridLength.Auto });
        accountInput = new(account); codeInput = new(code, send); keyInput = new(key);
        form.Children.Add(methods);
        var firstInput = new Grid(); firstInput.Children.Add(accountInput); firstInput.Children.Add(keyInput);
        Grid.SetRow(firstInput, 2); form.Children.Add(firstInput);
        Grid.SetRow(codeInput, 4); form.Children.Add(codeInput);
        var primaryHost = new Grid(); var primaryShadow = new Grid { IsHitTestVisible = false };
        _ = new LoginShadow(primaryShadow, () => (float)submit.CornerRadius.TopLeft, Theme.Brush("#2F46E2").Color, 7.5f, 5, .175f);
        Theme.Bind(primaryShadow, OpacityProperty, nameof(submit.Opacity), submit);
        primaryHost.Children.Add(primaryShadow); primaryHost.Children.Add(submit);
        Grid.SetRow(primaryHost, 6); form.Children.Add(primaryHost);
        terms.TextAlignment = TextAlignment.Center; terms.TextWrapping = TextWrapping.Wrap; terms.Opacity = .75;
        terms.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = "By signing in, you are agreeing to the " });
        terms.Inlines.Add(LegalLink("Terms of Use", "terms"));
        terms.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = " and " });
        terms.Inlines.Add(LegalLink("Privacy Policy", "privacy"));
        terms.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = "." });
        Grid.SetRow(terms, 8); form.Children.Add(terms);
        form.VerticalAlignment = VerticalAlignment.Center; inputArea.Children.Add(form);
        Grid.SetRow(inputArea, 1); formContent.Children.Add(inputArea);
        scenarios.Margin = new(0, 0, 0, 24); Grid.SetRow(scenarios, 2); formContent.Children.Add(scenarios);
        column.Children.Add(formContent);
        status.TextAlignment = TextAlignment.Center; status.VerticalAlignment = VerticalAlignment.Bottom; status.Margin = new(0, 0, 0, 3);
        column.Children.Add(status); Grid.SetColumn(column, 1); layout.Children.Add(column); Content = layout;
        AutomationProperties.SetName(account, "Phone number"); AutomationProperties.SetName(code, "Verification code"); AutomationProperties.SetName(key, "API Key");
        methods.SelectionChanged += () => { if (!updating) { model.Select(methods.SelectedIndex); Render(); } };
        account.TextChanged += (_, _) =>
        {
            if (updating) return;
            if (model.Account != account.Text) rejectedCodes.Remove(model.Method);
            model.SetAccount(account.Text); Render();
        };
        code.TextChanged += (_, _) =>
        {
            if (updating) return;
            model.SetCode(code.Text);
            if (rejectedCodes.TryGetValue(model.Method, out var rejection) && rejection.Value != model.Code) rejectedCodes.Remove(model.Method);
            Render();
        };
        key.PasswordChanged += (_, _) =>
        {
            model.ApiKey = key.Password; model.Error = null;
            if (rejectedKey != key.Password) rejectedKey = null;
            Render();
        };
        send.Click += async (_, _) => await RunAsync(false);
        submit.Click += async (_, _) => await RunAsync(true);
        code.KeyDown += async (_, args) => { if (args.Key == VirtualKey.Enter && model.CanSubmit) { args.Handled = true; await RunAsync(true); } };
        key.KeyDown += async (_, args) => { if (args.Key == VirtualKey.Enter && model.CanSubmit) { args.Handled = true; await RunAsync(true); } };
        timer = DispatcherQueue.CreateTimer(); timer.Interval = TimeSpan.FromSeconds(1); timer.Tick += (_, _) => Render();
        SizeChanged += (_, _) => ApplyLayout();
        Loaded += (_, _) => { UpdateVideoPlayback(); if (presented && !captureMode) account.Focus(FocusState.Programmatic); };
        Unloaded += (_, _) => { if (!disposed) player.Pause(); };
        ApplyLayout(); Render();
    }

    private static Microsoft.UI.Xaml.Documents.Hyperlink LegalLink(string text, string slug) => new()
    {
        NavigateUri = new($"https://platform.xmaxsi.com/docs/resources/{slug}"), Foreground = Theme.Brush("#2F46E2"),
        TextDecorations = global::Windows.UI.Text.TextDecorations.None,
        Inlines = { new Microsoft.UI.Xaml.Documents.Run { Text = text } }
    };

    private void ApplyLayout()
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        // The same 1440 x 900 design reference, bounded scale and independent anchors as macOS.
        layoutScale = Math.Round(Math.Clamp(Math.Min(ActualWidth / 1440, ActualHeight / 900), .9, 1.1), 2);
        double s = layoutScale;
        formContent.Width = Math.Max(240, Math.Min(ActualWidth / 2 - 96, Math.Min(ActualWidth / 2 * .82, 560 * s)));
        heading.Margin = new(0, 80 * s, 0, 0);
        appIcon.Width = appIcon.Height = 112 * s;
        title.FontSize = 34 * s; title.Height = 48 * s; title.Margin = new(0, 20 * s, 0, 0);
        subtitle.FontSize = 17 * s; subtitle.Height = 26 * s; subtitle.Margin = new(0, 8 * s, 0, 0);
        inputArea.Margin = new(0, 24 * s, 0, 24 * s);
        methods.ApplyScale(s); accountInput.ApplyScale(s); codeInput.ApplyScale(s); keyInput.ApplyScale(s);
        send.ApplyScale(s, true); submit.ApplyScale(s, false); terms.FontSize = 14 * s;
        form.RowDefinitions[1].Height = new(24 * s);
        form.RowDefinitions[3].Height = new(model.UsesApiKey ? 0 : 16 * s);
        form.RowDefinitions[5].Height = new(20 * s);
        form.RowDefinitions[7].Height = new(24 * s);
        form.RowDefinitions[9].Height = new(model.UsesApiKey ? 70 * s : 0);
        UpdateAccessory();
    }

    private void UpdateAccessory()
    {
        send.Width = Math.Max(88 * layoutScale, send.PreferredWidth);
        codeInput.SetAccessoryWidth(send.Width);
    }

    public void SetPresented(bool value)
    {
        if (presented == value || disposed) return;
        presented = value;
        Visibility = value ? Visibility.Visible : Visibility.Collapsed;
        UpdateVideoPlayback();
        if (value) { scenarios.SetPlaying(!captureMode); timer.Start(); if (!configurationLoaded) _ = LoadConfigurationAsync(); }
        else { scenarios.SetPlaying(false); timer.Stop(); model.ClearSecrets(); rejectedKey = null; rejectedCodes.Clear(); key.Password = ""; Render(); }
    }

    private void UpdateVideoPlayback()
    {
        if (disposed) return;
        // Video playback is independent of the system setting for control animations.
        bool play = presented && IsLoaded && !captureMode && videoFailure is null;
        media.Visibility = play ? Visibility.Visible : Visibility.Collapsed;
        if (!play) { player.Pause(); return; }
        if (videoSource is not null) player.Play();
        else if (!videoLoading) _ = LoadVideoAsync();
    }

    private async Task LoadVideoAsync()
    {
        videoLoading = true;
        try
        {
            // This is an unpackaged desktop app: MediaSource cannot resolve ms-appx assets.
            var file = await StorageFile.GetFileFromPathAsync(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Login", "FaceNowLogin.mp4"));
            if (disposed) return;
            videoSource = MediaSource.CreateFromStorageFile(file);
            player.Source = videoSource;
            UpdateVideoPlayback();
        }
        catch (Exception error)
        {
            if (disposed) return;
            videoFailure = $"{error.GetType().Name}: {error.Message} ({error.HResult:X8})";
            media.Visibility = Visibility.Collapsed;
        }
        finally { videoLoading = false; }
    }
    private async Task LoadConfigurationAsync()
    {
        if (configurationLoaded || model.IsBusy || disposed) return;
        model.IsBusy = true; model.Error = null; configurationFailed = false; Render();
        try
        {
            model.Configuration = await user.GetConfigurationAsync(lifetime.Token);
            configurationLoaded = true;
            if (!model.Configuration.Supports(model.Method))
            { model.Select(model.Configuration.EnableSmsLogin ? 0 : model.Configuration.EnableEmailLogin ? 1 : 2); }
        }
        catch (OperationCanceledException) { }
        catch (Exception failure) { configurationFailed = true; ReportRequestError(failure.Message); }
        finally { model.IsBusy = false; if (!disposed) Render(); }
    }
    private async Task RunAsync(bool login)
    {
        if (disposed || !presented || user.IsBusy) return;
        if (login && configurationFailed && !model.UsesApiKey) { await LoadConfigurationAsync(); return; }
        if (!(login ? model.CanSubmit : model.CanSendCode)) return;
        bool withKey = model.UsesApiKey;
        var method = model.Method;
        string destination = model.Account.Trim(), enteredCode = model.Code, enteredKey = model.ApiKey;
        var configuration = model.Configuration;
        model.IsBusy = true; submittingLogin = login; sendingCode = !login; model.Error = null; RequestError?.Invoke(null); Render();
        try
        {
            if (withKey) await user.SignInWithKeyAsync(enteredKey, lifetime.Token);
            else
            {
                if (configuration is null) throw new AccountException("Connect to the service before signing in.");
                CaptchaProof proof = configuration.NeedsCaptcha(method, login)
                    ? await captcha.PresentAsync(configuration.CaptchaAppId ?? "", login ? "login" : $"send-{method.ToString().ToLowerInvariant()}-code", lifetime.Token)
                    : new();
                if (login) await user.SignInWithCodeAsync(configuration, method, destination, enteredCode, proof, lifetime.Token);
                else
                {
                    await user.SendCodeAsync(configuration, method, destination, proof, lifetime.Token);
                    model.RecordSent(method, destination, configuration.Cooldown(method));
                    code.Focus(FocusState.Programmatic);
                }
            }
            if (login && !disposed && user.HasVerifiedSession) SignedIn?.Invoke();
        }
        catch (OperationCanceledException) { }
        catch (Exception failure)
        {
            if (withKey && failure is AccountException { IsUnauthorized: true }) rejectedKey = enteredKey;
            if (!withKey && (failure.Message.StartsWith("Invalid code.", StringComparison.Ordinal) || failure.Message.StartsWith("This code has expired.", StringComparison.Ordinal)))
                rejectedCodes[method] = (enteredCode, failure.Message);
            ReportRequestError(failure.Message);
        }
        finally { model.IsBusy = submittingLogin = sendingCode = false; if (!disposed) Render(); }
    }
    private void ReportRequestError(string message) { model.Error = message; RequestError?.Invoke(message); }
    public void Refresh()
    {
        if (disposed) return;
        if (lastNotice != user.Notice)
        {
            lastNotice = user.Notice;
            if (!string.IsNullOrWhiteSpace(lastNotice)) RequestError?.Invoke(lastNotice);
        }
        Render();
    }
    private void Render()
    {
        updating = true;
        try
        {
            bool busy = model.IsBusy || user.IsBusy;
            methods.SelectedIndex = model.UsesApiKey ? 2 : model.Method == LoginMethod.Sms ? 0 : 1;
            methods.SetAvailability(model.Configuration?.EnableSmsLogin ?? true, model.Configuration?.EnableEmailLogin ?? true);
            methods.IsEnabled = !busy;
            accountInput.Visibility = codeInput.Visibility = model.UsesApiKey ? Visibility.Collapsed : Visibility.Visible;
            keyInput.Visibility = model.UsesApiKey ? Visibility.Visible : Visibility.Collapsed;
            accountInput.SetPrefix(model.Method == LoginMethod.Sms);
            account.PlaceholderText = model.Method == LoginMethod.Sms ? "Enter your phone number" : "Enter your email address";
            AutomationProperties.SetName(account, model.Method == LoginMethod.Sms ? "Phone number" : "Email address");
            if (account.Text != model.Account) account.Text = model.Account;
            if (code.Text != model.Code) code.Text = model.Code;
            code.MaxLength = model.CodeLength;
            accountInput.IsEnabled = codeInput.IsEnabled = keyInput.IsEnabled = !busy;
            keyInput.SetInvalid(rejectedKey is not null ? "This API key is inactive or unavailable." : null);
            codeInput.SetInvalid(rejectedCodes.GetValueOrDefault(model.Method).Message);
            send.IsEnabled = !busy && model.CanSendCode;
            send.Text = model.Cooldown > 0 ? $"Resend ({model.Cooldown}s)" : "Get Code";
            send.SetLoading(sendingCode);
            submit.IsEnabled = !busy && (model.CanSubmit || configurationFailed && !model.UsesApiKey && model.ValidAccount && model.Code.Length == model.CodeLength);
            submit.SetLoading(submittingLogin);
            status.Text = preview ? "Login preview · simulated account, no account requests" : "";
            ApplyLayout();
        }
        finally { updating = false; }
    }
    private static TextBox Input(string placeholder) => new() { PlaceholderText = placeholder, IsSpellCheckEnabled = false, IsTextPredictionEnabled = false };
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; lifetime.Cancel(); lifetime.Dispose(); timer.Stop(); scenarios.SetPlaying(false);
        // Detach the XAML player before closing its WinRT object; unloading must not call a closed player.
        player.Pause(); media.SetMediaPlayer(null); player.Source = null; videoSource?.Dispose(); videoSource = null; Content = null; player.Dispose();
    }

    internal async Task VerifyFormAsync()
    {
        if (!preview) throw new InvalidOperationException("Form verification requires an isolated preview account.");
        await VerifyVideoLifecycleAsync();
        if (!configurationLoaded) await LoadConfigurationAsync();
        if (!configurationLoaded || user.CanAccessHome) throw new InvalidOperationException("Login preview did not initialize signed out.");
        methods.SelectedIndex = 0; await Task.Delay(50);
        account.Text = "13800000000"; await Task.Delay(50);
        code.Text = "123456"; await Task.Delay(50);
        if (code.Text != "123456" || !submit.IsEnabled) throw new InvalidOperationException($"Phone input validation failed (account length {model.Account.Length}, code length {model.Code.Length}, busy {model.IsBusy}, ready {configurationLoaded}).");
        await RunAsync(false);
        if (send.IsEnabled || model.Cooldown <= 0) throw new InvalidOperationException("Resend cooldown failed.");
        methods.SelectedIndex = 1; await Task.Delay(50);
        account.Text = "preview@example.com"; await Task.Delay(50);
        code.Text = "654321"; await Task.Delay(50);
        methods.SelectedIndex = 0; await Task.Delay(50);
        if (account.Text != "13800000000" || code.Text != "123456") throw new InvalidOperationException("Channel drafts were not restored.");
        methods.SelectedIndex = 2; await Task.Delay(50);
        key.Password = "uk-missing"; await Task.Delay(50); await RunAsync(true);
        if (user.HasVerifiedSession || string.IsNullOrWhiteSpace(model.Error)) throw new InvalidOperationException("An invalid key bypassed login.");
        key.Password = PreviewAccountApi.Key; await Task.Delay(50); await RunAsync(true);
        if (!user.HasVerifiedSession) throw new InvalidOperationException("Validated preview login did not publish a session.");
    }
}
