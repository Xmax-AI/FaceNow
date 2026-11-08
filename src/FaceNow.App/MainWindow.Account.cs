using FaceNow.App.Controls;
using FaceNow.App.User;
using FaceNow.Core.User;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private readonly UserRepository? accountRepository;
    private LoginView? loginView;
    private readonly AccountAvatarButton accountButton = new();
    private readonly ToolbarButton homeCredits = new() { Text = "—", Glyph = "boltFilled" };
    private readonly ToolbarButton sessionCredits = new() { Text = "—", Glyph = "boltFilled" };
    private bool studioInitialized, studioInitializing, accountStopping, lastVerified;
    private readonly DispatcherTimer creditsRefreshTimer = new() { Interval = TimeSpan.FromSeconds(5) };
    private void BuildAccountUi()
    {
        if (accountRepository is null) return;
        loginView = new(accountRepository, root, Model.IsPreview);
        loginView.RequestError = message => { if (message is null) Model.ClearError(); else Model.ReportError(new AccountException(message)); };
        loginView.SignedIn = ShowSignInToast;
        root.Children.Insert(root.Children.Count - 1, loginView);
        homeControls.Children.Add(homeCredits);
        homeControls.Children.Add(accountButton);
        sessionControls.Children.Insert(sessionControls.Children.IndexOf(elapsed), sessionCredits);
        accountButton.Click += async (_, _) => await OpenAccountAsync();
        root.SizeChanged += (_, _) => { if (accountPopup?.IsOpen == true) ClosePopups(); };
        homeCredits.Click += (_, _) => OpenLink("https://platform.xmaxai.com/credits");
        sessionCredits.Click += (_, _) => OpenLink("https://platform.xmaxai.com/credits");
        accountRepository.Changed += AccountChanged;
        Model.AuthenticationRejected += RevalidateGenerationAccount;
        Model.CreditsRequired += ShowCreditsWarning;
        creditsRefreshTimer.Tick += RefreshCreditsTick;
        RefreshAccountUi();
    }
    private async Task InitializeAccountAsync()
    {
        if (accountRepository is null) return;
        // A development SDK override does not establish or replace a platform identity.
        string? legacy = null;
        try { legacy = apiKeyStore?.Load(); }
        catch (Exception error) { Model.ReportError(error); }
        await accountRepository.RestoreAsync(legacy);
        if (accountRepository.HasVerifiedSession)
        {
            try { apiKeyStore?.Save(""); } catch (Exception error) { Model.ReportError(error); }
            await EnsureAccountStudioAsync();
            _ = RefreshCreditsQuietlyAsync();
        }
        RefreshAccountUi();
    }
    private async void AccountChanged()
    {
        if (closing || closed || accountRepository is null) return;
        try
        {
            bool becameVerified = accountRepository.HasVerifiedSession && !lastVerified;
            lastVerified = accountRepository.HasVerifiedSession;
            if (!accountRepository.CanAccessHome) Model.ResetHomeReferences();
            RefreshAccountUi();
            if (becameVerified) _ = RefreshCreditsQuietlyAsync();
            if (!accountRepository.HasVerifiedSession && Model.Session is not null && !accountStopping)
            {
                accountStopping = true;
                try { await Model.StopAsync(); }
                finally { accountStopping = false; }
            }
            if (accountRepository.HasVerifiedSession)
            {
                await EnsureAccountStudioAsync();
            }
        }
        catch (Exception error) { if (!closing) Model.ReportError(error); }
    }
    private async Task EnsureAccountStudioAsync()
    {
        if (studioInitialized || studioInitializing || closing || accountRepository?.HasVerifiedSession != true) return;
        studioInitializing = true;
        try { await Model.InitializeAsync(); studioInitialized = true; }
        finally { studioInitializing = false; RefreshAccountUi(); }
    }
    private void RefreshAccountUi()
    {
        if (accountRepository is null || loginView is null || closing) return;
        bool home = accountRepository.CanAccessHome;
        if (!home) DismissSignInToast();
        loginView.SetPresented(!home);
        loginView.Refresh();
        scroller.Visibility = home ? Visibility.Visible : Visibility.Collapsed;
        keyButton.Visibility = Visibility.Collapsed;
        string value = "";
        if (accountRepository.HasVerifiedSession && accountRepository.SelectedKeyUid is not null)
        {
            try { value = accountRepository.GetVerifiedGenerationKey(); } catch (AccountException) { }
        }
        if (Model.ApiKey != value) SetApiKey(value);
        var presentation = AccountPresentation.From(accountRepository);
        accountButton.SetInitials(presentation.AvatarText);
        AutomationProperties.SetName(accountButton, "Account: " + accountRepository.DisplayName);
        accountButton.IsEnabled = !accountRepository.IsBusy && !accountStopping;
        homeCredits.Text = sessionCredits.Text = presentation.Credits;
        homeCredits.Tone = sessionCredits.Tone = accountRepository.RemainingCredits is < 300 ? ToolbarButtonTone.Danger : ToolbarButtonTone.Neutral;
        AutomationProperties.SetName(homeCredits, "Credits " + presentation.Credits);
        AutomationProperties.SetName(sessionCredits, "Credits " + presentation.Credits);
        accountCard?.Update(presentation, accountRepository.CanAccessHome, !accountRepository.IsBusy && !accountStopping);
        StartButton.IsEnabled = Model.CanChooseHomeReference && accountRepository.HasVerifiedSession && studioInitialized && !accountStopping;
        if (home && !accountRepository.HasVerifiedSession) StartButton.Text = AppText.Get("Verifying account…");
        homeCredits.IsEnabled = sessionCredits.IsEnabled = accountRepository.HasVerifiedSession;
        if (accountRepository.HasVerifiedSession) creditsRefreshTimer.Start();
        else creditsRefreshTimer.Stop();
    }
    private async void RefreshCreditsTick(object? sender, object e) => await RefreshCreditsQuietlyAsync();
    private async Task RefreshCreditsQuietlyAsync()
    {
        if (accountRepository is null || closing || closed) return;
        try { await accountRepository.RefreshCreditsAsync(); }
        catch (Exception) { /* A temporary billing failure keeps the last confirmed balance. */ }
    }
    private async Task OpenGenerationKeysAsync()
    {
        if (accountRepository?.HasVerifiedSession != true) return;
        var stack = new StackPanel { Spacing = 10 };
        stack.Children.Add(Theme.Text(accountRepository.DisplayName, 16));
        stack.Children.Add(Theme.Text("Generation API key", 12, "#6B7380"));
        foreach (var key in accountRepository.Keys)
        {
            string uid = key.Uid;
            var choose = new Pill { Text = key.Label, Accent = uid == accountRepository.SelectedKeyUid,
                IsEnabled = !Model.Active && !Model.Busy, HorizontalAlignment = HorizontalAlignment.Stretch };
            choose.Click += (_, _) =>
            {
                try { accountRepository.SelectKey(uid); ClosePopups(); }
                catch (Exception error) { Model.ReportError(error); }
            };
            stack.Children.Add(choose);
        }
        if (accountRepository.Keys.Count == 0)
            stack.Children.Add(Theme.Text("No active API key. Create one to start generating.", 12, "#6B7380"));
        var create = new Pill { Text = AppText.Get("Create FaceNow key"), IsEnabled = !Model.Active && !Model.Busy && !accountRepository.IsBusy };
        create.Click += async (_, _) =>
        {
            ClosePopups();
            try { await accountRepository.CreateKeyAsync(); }
            catch (Exception error) { Model.ReportError(error); }
        };
        stack.Children.Add(create);
        stack.Children.Add(Theme.Link("Usage ↗", () => OpenLink("https://platform.xmaxai.com/usage")));
        stack.Children.Add(Theme.Link("Manage API keys ↗", () => OpenLink("https://platform.xmaxsi.com/api-keys")));
        var signOut = new Pill { Text = AppText.Get("Sign out"), Destructive = true, HorizontalAlignment = HorizontalAlignment.Stretch };
        signOut.Click += async (_, _) => await SignOutAccountAsync(); stack.Children.Add(signOut);
        OpenPopup(accountButton, stack, 340, 18);
        await RefreshCreditsQuietlyAsync();
    }
    private async Task SignOutAccountAsync()
    {
        if (accountRepository is null || accountStopping) return;
        ClosePopups();
        accountStopping = true; RefreshAccountUi();
        try
        {
            Model.ResetHomeReferences();
            // Device registration survives sign-out; stopping switches its output back to the placeholder.
            try { await Model.StopAsync(); }
            finally
            {
                SetApiKey("");
                try { apiKeyStore?.Save(""); }
                finally { await accountRepository.SignOutAsync(); }
            }
        }
        catch (Exception error) { Model.ReportError(error); }
        finally { accountStopping = false; RefreshAccountUi(); }
    }
    private async void RevalidateGenerationAccount()
    {
        if (accountRepository is null || accountStopping || closing || !accountRepository.HasVerifiedSession) return;
        accountStopping = true; RefreshAccountUi();
        try
        {
            await Model.StopAsync();
            if (!closing) await accountRepository.RestoreAsync();
        }
        catch (Exception error) { if (!closing) Model.ReportError(error); }
        finally { accountStopping = false; RefreshAccountUi(); }
    }
    private void DisposeAccountUi()
    {
        creditsRefreshTimer.Stop();
        creditsRefreshTimer.Tick -= RefreshCreditsTick;
        loginView?.Dispose();
        Model.AuthenticationRejected -= RevalidateGenerationAccount;
        Model.CreditsRequired -= ShowCreditsWarning;
        if (accountRepository is not null) { accountRepository.Changed -= AccountChanged; accountRepository.Dispose(); }
    }
}
