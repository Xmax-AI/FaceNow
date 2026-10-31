using System.Text.Json;
using Microsoft.UI.Xaml;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private async Task VerifyLoginLayoutAsync()
    {
        Check(loginView is { IsLoaded: true, Visibility: Visibility.Visible }, "Login page is missing.");
        int primary = FaceNow.Core.Product.ProductProfile.Current.ShowsPhoneLogin ? 0 : 1;
        var records = new List<object>();
        foreach (var (width, height, name) in new[] { (1180, 800, "minimum"), (1360, 890, "default"), (1920, 1080, "wide") })
        {
            ResizeWindow(width, height); await Task.Delay(250); root.UpdateLayout();
            await loginView!.PrepareLayoutCaptureAsync(primary);
            records.Add(new { name, metrics = loginView.VerifyLayoutBounds() });
            await SaveScreenshotAsync("login-" + name, loginView);
            await SaveScreenshotAsync("login-phone-empty-" + name, loginView.PhoneInputCaptureTarget, 2);
            await SaveScreenshotAsync("login-code-empty-" + name, loginView.CodeInputCaptureTarget, 2);
            await SaveNativeLoginScreenshotAsync("native-phone-empty-" + name, loginView.PhoneInputCaptureTarget);
            await SaveNativeLoginScreenshotAsync("native-code-empty-" + name, loginView.CodeInputCaptureTarget);
            await loginView.PrepareLayoutCaptureAsync(primary, "typing");
            records.Add(new { name = "phone-typing-" + name, metrics = loginView.VerifyLayoutBounds() });
            await SaveScreenshotAsync("login-phone-typing-" + name, loginView.PhoneInputCaptureTarget, 2);
            await SaveNativeLoginScreenshotAsync("native-phone-typing-" + name, loginView.PhoneInputCaptureTarget);
            foreach (var state in new[] { "enabled", "resend" })
            {
                await loginView.PrepareLayoutCaptureAsync(primary, state);
                records.Add(new { name = $"code-{state}-{name}", metrics = loginView.VerifyLayoutBounds() });
                await SaveScreenshotAsync($"login-code-{state}-{name}", loginView.CodeInputCaptureTarget, 2);
            }
            foreach (var state in new[] { "alignment-empty", "alignment-text" })
            {
                await loginView.PrepareLayoutCaptureAsync(primary, state);
                records.Add(new { name = $"email-{state}-{name}", metrics = loginView.AccountTextLineMetrics() });
                await SaveNativeLoginScreenshotAsync($"native-email-{state}-{name}", loginView.PhoneInputCaptureTarget);
            }
        }
        ResizeWindow(1360, 890); await Task.Delay(250); root.UpdateLayout();
        foreach (var (mode, state, name) in new[] { (primary, "focused", "account-focus"), (primary, "typing", "account-typing"), (primary, "enabled", "account-ready"),
            (primary, "idle", "account"), (primary, "loading", "signing-in"), (2, "idle", "api-key"), (2, "invalid", "api-key-error") })
        {
            await loginView!.PrepareLayoutCaptureAsync(mode, state);
            records.Add(new { name, metrics = loginView.VerifyLayoutBounds() });
            await SaveScreenshotAsync("login-" + name, loginView);
            if (name == "account-typing") await SaveScreenshotAsync("login-account-typing-detail", loginView.PhoneInputCaptureTarget, 2);
        }
        string? output = Environment.GetEnvironmentVariable("FACENOW_SMOKE_OUTPUT");
        if (output is not null)
            await File.WriteAllTextAsync(Path.Combine(output, "login-layout-metrics.json"), JsonSerializer.Serialize(records, new JsonSerializerOptions { WriteIndented = true }));
        Check(Model.Session is null && Model.Cameras.Count == 0 && accountRepository?.HasVerifiedSession == false,
            "Layout verification touched a camera or authenticated an account.");
    }
}
