// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using Microsoft.UI.Xaml;
using System.IO;
using FaceNow.Windows.Studio.Services;
using FaceNow.Core.User;
using FaceNow.Windows.Network;
using FaceNow.Windows.Security;
using FaceNow.App.User;

namespace FaceNow.App;

public partial class App : Application
{
    private Window? window;
    // The installer checks this named object before replacing or removing running binaries.
    private readonly Mutex installerMutex = new(false, @"Local\XMAX.AI." + FaceNow.Core.Product.ProductProfile.Current.Id + ".Running");
    public App()
    {
        InitializeComponent();
        UnhandledException += (_, args) =>
        {
            string? output = Environment.GetEnvironmentVariable("FACENOW_SMOKE_OUTPUT");
            if (!string.IsNullOrEmpty(output))
            { Directory.CreateDirectory(output); File.WriteAllText(Path.Combine(output, "unhandled.txt"), args.Exception.ToString()); }
        };
    }
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        string[] arguments = Environment.GetCommandLineArgs();
        string? mode = arguments.FirstOrDefault(value => value.StartsWith("--smoke-test"));
        bool setupPreview = arguments.Contains("--preview-camera-setup") || mode == "--smoke-test-camera-setup";
        bool loginPreview = arguments.Contains("--preview-login") || mode is "--smoke-test-account" or "--smoke-test-login-layout" or "--smoke-test-signout" or "--smoke-test-signout-cached";
        bool preview = loginPreview || setupPreview || arguments.Contains("--preview") || arguments.Contains("--preview-session") || mode is "--smoke-test-ui" or "--smoke-test-frames";
        ApiKeyStore? store = !preview && mode is null ? new() : null;
        if (mode?.StartsWith("--smoke-test-key-memory-") == true)
            store = new ApiKeyStore("XMAX.AI/FaceNow/ApiKey.Smoke." + Guid.Parse(Environment.GetEnvironmentVariable("FACENOW_SMOKE_CREDENTIAL_ID") ?? "").ToString("N"));
        AccountApi? accountApi = !preview && mode is null ? new() : null;
        UserRepository? user = loginPreview ? new(new PreviewAccountApi(), new PreviewAccountStorage(mode == "--smoke-test-signout-cached"))
            : accountApi is null ? null : new(accountApi, new AccountStorage());
        user?.LoadCachedSession();
        var main = new MainWindow(preview, arguments.Contains("--preview-session") || mode == "--smoke-test-frames", store, mode is null or "--smoke-test-camera" or "--smoke-test-live", setupPreview, user);
        main.Closed += (_, _) => accountApi?.Dispose();
        if (setupPreview) main.Ready += main.ResetCameraSetupPreview;
        if (mode is not null) main.Ready += async () => await main.RunSmokeAsync(mode);
        window = main;
        window.Activate();
    }
}
