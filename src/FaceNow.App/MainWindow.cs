// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.ComponentModel;
using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using FaceNow.Windows.Studio.Services;
using FaceNow.Windows.Studio.ViewModels;
using FaceNow.App.Controls;
using FaceNow.App.Platform;
using Xmax.SDK;
using Xmax.SDK.WinUI;
using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.VirtualCamera;
using FaceNow.Core.User;

namespace FaceNow.App;

public sealed partial class MainWindow : Window
{
    internal MainViewModel Model { get; }
    private readonly Grid root = new() { Background = Theme.Brush("#FFFFFF"), RequestedTheme = ElementTheme.Light };
    private readonly ScrollViewer scroller = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollMode = ScrollMode.Disabled };
    private readonly Canvas page = new() { Background = Theme.Brush("#FFFFFF") };
    private readonly Grid header = new() { Height = 60 };
    private readonly Image brand = new() { Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new("ms-appx:///Assets/xmax-wordmark.png")), Stretch = Stretch.Uniform };
    private readonly StackPanel homeControls = new() { Orientation = Orientation.Horizontal, Spacing = 12, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
    private readonly StackPanel sessionControls = new() { Orientation = Orientation.Horizontal, Spacing = 12, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
    private readonly StackPanel landing = new();
    private readonly Grid landingStage = new() { HorizontalAlignment = HorizontalAlignment.Center };
    private readonly TextBlock title = Theme.Text("Bringing Your New Look into Video Calls", 31.6);
    private readonly TextBlock terms = Theme.Text("", 13, "#9CA3AF");
    private readonly StackPanel workspace = new();
    private readonly Grid localPanel = new() { Background = Theme.Brush("#000000") }, remotePanel = new() { Background = Theme.Brush("#000000") };
    internal readonly XmaxRealtimeVideoView LocalView = new() { ContentMode = VideoContentMode.Fill };
    internal readonly ResultVideoView RemoteView = new() { ContentMode = VideoContentMode.Fill };
    private readonly TextBlock localPlaceholder = Theme.Text("", 14, "#B3FFFFFF"), resultPlaceholder = Theme.Text("", 14, "#B3FFFFFF");
    private readonly StackPanel localStatistics = new(), remoteStatistics = new();
    private readonly Grid referenceArea = new() { Height = 190 };
    private readonly Dictionary<string, ScrollViewer> referenceScrollers = [];
    internal readonly Dictionary<ReferenceItem, ReferenceTile> ReferenceTiles = [];
    private readonly Dictionary<string, CenteredWrapPanel> referencePanels = [];
    private readonly Dictionary<string, Button> tabs = [];
    private readonly Border freePromptBox = new() { Height = 136, CornerRadius = new(18), Background = Theme.Brush("#F7F8FA"), BorderBrush = Theme.Brush("#E5E7EB"), BorderThickness = new(1), VerticalAlignment = VerticalAlignment.Top, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly TextBox promptEditor = new() { PlaceholderText = AppText.Get("Describe what you want to see…"), AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, BorderThickness = new(0), Background = Theme.Brush("#00FFFFFF"), Padding = new(0), FontFamily = Theme.Font, FontSize = 14 };
    private readonly Grid freeReferenceHost = new() { Width = 44, Height = 44, Margin = new(0, 0, 10, 0) };
    private readonly Image freeReferenceImage = new() { Stretch = Stretch.UniformToFill };
    private readonly ReferenceUploadOverlay freeReferenceUploadOverlay = new(compact: true);
    private readonly TextBlock freeReferenceStatus = Theme.Text("", 8, "#FFFFFF");
    private readonly Grid footer = new() { Height = 36 };
    private readonly TextBlock previewFooter = Theme.Text("UI preview · no camera, network session or generated output", 11, "#9CA3AF");
    private readonly Pill previewBadge = new() { Text = AppText.Get("UI Preview · camera off"), Accent = true, Margin = new(16, 0, 0, 0), IsHitTestVisible = false };
    internal readonly Pill StartButton = new() { Text = AppText.Get("Start Camera"), Glyph = "camera", Primary = true, Height = 52, FontSize = 16, HorizontalAlignment = HorizontalAlignment.Center,
        OpacityTransition = new ScalarTransition { Duration = TimeSpan.FromMilliseconds(300) } };
    private readonly Pill cameraButton = new() { Text = AppText.Get("Select Camera"), MaxWidth = 280, LabelMaxWidth = 220,
        FontSize = 13, Height = 32, Translucent = true };
    private readonly Pill modelButton = new() { Text = AppText.Get("X2.1"), Glyph = "chevron", TrailingGlyph = true, Padding = new(18, 0, 12, 0), ContentSpacing = 6, Visibility = Visibility.Collapsed };
    private readonly Pill keyButton = new() { Glyph = "key", LabelVerticalOffset = 2.75 };
    private readonly WindowsVirtualCamera virtualCameraOutput = new();
    private readonly Pill homeVirtualCamera = new() { Glyph = "camera", ExtraChevron = true, FontSize = 12, LabelMaxWidth = 220, Padding = new(15, 0, 12, 0) };
    private readonly Pill statisticsButton = new() { Glyph = "statistics", Secondary = true };
    private readonly Pill elapsed = new() { Passive = true, MinWidth = 72, IsHitTestVisible = false };
    private readonly Pill stopButton = new() { Text = AppText.Get("Stop Session"), Glyph = "stop", Destructive = true };
    private readonly Pill freeUpload = new() { Glyph = "plus", Width = 44, Height = 44, Padding = new(0), Margin = new(0, 0, 10, 0) };
    private readonly Pill submit = new() { Glyph = "arrow", Primary = true, Width = 44, Height = 44, Padding = new(0) };
    private readonly ToastView toast = new();
    private readonly ApiKeyStore? apiKeyStore;
    private bool initialized, previousActive, closing, closed, settingApiKey, layoutPending;

    internal MainWindow(bool preview = false, bool previewSession = false, ApiKeyStore? store = null, bool environmentKey = true, bool setupPreview = false, UserRepository? user = null)
    {
        cameraSetupPreview = setupPreview;
        Title = preview ? "FaceNow — UI Preview" : FaceNow.Core.Product.ProductProfile.Current.DisplayName;
        if (setupPreview) Title = "FaceNow — Camera setup preview (simulated)";
        AppWindow.SetIcon(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "FaceNow.ico"));
        apiKeyStore = store;
        accountRepository = user;
        Model = new(new WinUiDispatcher(DispatcherQueue), new WinUiThumbnailLoader(), virtualCameraOutput, user);
        Model.CameraFilter = item => !virtualCameraOutput.IsOwnCamera(item.Id);
        if (preview) Model.ConfigurePreview(previewSession);
        root.DataContext = Model;
        BuildUi();
        BuildBeautyUi();
        BuildAccountUi();
        if (setupPreview)
        {
            previewBadge.Text = AppText.Get("Restart setup preview"); previewBadge.IsHitTestVisible = true;
            previewBadge.Click += (_, _) => ResetCameraSetupPreview();
            previewFooter.Text = AppText.Get("Camera setup simulation · no installation, camera access or system changes");
        }
        Content = root;
        toast.Dismissed += ToastDismissed;
        Model.PropertyChanged += ModelChanged;
        virtualCameraOutput.StatusChanged += () => DispatcherQueue.TryEnqueue(() => { if (!closed) RefreshVirtualCameraUi(); });
        Activated += async (_, args) =>
        {
            if (args.WindowActivationState != WindowActivationState.Deactivated) await SynchronizeVirtualCameraStatusAsync();
        };
        Model.ApiKeyRequired += OpenKey;
        Model.CameraRequired += OpenCameras;
        LocalView.PlaybackFailed += Model.ReportError; RemoteView.PlaybackFailed += Model.ReportError;
        Theme.Bind(LocalView, XmaxRealtimeVideoView.VideoSourceProperty, nameof(Model.LocalVideo), Model);
        Theme.Bind(RemoteView, ResultVideoView.VideoSourceProperty, nameof(Model.ResultVideoSource), Model);
        root.SizeChanged += (_, _) => RequestLayout();
        scroller.ViewChanged += (_, _) => RequestLayout();
        root.Loaded += async (_, _) =>
        {
            if (initialized) return;
            initialized = true;
            if (accountRepository is null)
                LoadApiKey(!preview && environmentKey ? Environment.GetEnvironmentVariable("XMAX_API_KEY") : null);
            VerificationProgress("Refreshing virtual camera");
            if (!cameraSetupPreview && !(preview && accountRepository is not null)) await virtualCameraOutput.RefreshAsync();
            VerificationProgress("Enumerating input cameras");
            if (accountRepository is null) await Model.InitializeAsync();
            else await InitializeAccountAsync();
            RefreshUi(); ArrangePage();
            VerificationProgress("Window ready");
            PageEntry.Reveal(Model.Active ? workspace : landing);
            if (!Model.Active) PageEntry.Reveal(footer);
            Ready?.Invoke();
        };
        ResizeWindow(1360, 890);
        AppWindow.Closing += async (_, args) =>
        {
            if (closed) return;
            args.Cancel = true;
            if (closing) return;
            closing = true; DisposeAboutView(); ClosePopups(); root.IsHitTestVisible = false; toast.Shutdown();
            DisposeAccountUi();
            try { try { await Model.DisposeAsync(); } finally { await virtualCameraOutput.DisposeAsync(); } }
            catch (Exception error) { Model.ReportError(error); }
            finally { closed = true; DispatcherQueue.TryEnqueue(() => Close()); }
        };
        RefreshUi();
    }
    internal event Action? Ready;
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);
    internal void ResizeWindow(double width, double height)
    {
        double scale = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96d;
        if (AppWindow.Presenter is Microsoft.UI.Windowing.OverlappedPresenter presenter)
        { presenter.PreferredMinimumWidth = (int)(1180 * scale); presenter.PreferredMinimumHeight = (int)(800 * scale); }
        AppWindow.Resize(new((int)Math.Round(width * scale), (int)Math.Round(height * scale)));
        var area = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(AppWindow.Id, Microsoft.UI.Windowing.DisplayAreaFallback.Nearest).WorkArea;
        AppWindow.Move(new(area.X + (area.Width - AppWindow.Size.Width) / 2, area.Y + (area.Height - AppWindow.Size.Height) / 2));
    }
    private void ModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        RefreshUi();
    }
    private void RefreshUi()
    {
        RefreshBeautyUi();
        bool changed = previousActive != Model.Active;
        homeControls.Visibility = landing.Visibility = footer.Visibility = Model.Active ? Visibility.Collapsed : Visibility.Visible;
        sessionControls.Visibility = workspace.Visibility = Model.Active ? Visibility.Visible : Visibility.Collapsed;
        previewBadge.Visibility = Model.IsPreview ? Visibility.Visible : Visibility.Collapsed;
        previewFooter.Visibility = Model.IsPreview ? Visibility.Visible : Visibility.Collapsed;
        RefreshVirtualCameraUi();
        cameraButton.Visibility = Model.Active ? Visibility.Collapsed : Visibility.Visible;
        cameraButton.Text = Model.SelectedCamera?.Name ?? "Select Camera";
        ToolTipService.SetToolTip(cameraButton, cameraButton.Text);
        keyButton.Text = Model.KeyLabel;
        cameraButton.IsEnabled = modelButton.IsEnabled = keyButton.IsEnabled = StartButton.IsEnabled = Model.CanEdit;
        if (cameraSetupPreview) StartButton.IsEnabled = false;
        StartButton.Text = Model.StartLabel; stopButton.Text = Model.StopLabel;
        statisticsButton.Accent = Model.StatisticsVisible; elapsed.Text = Model.Elapsed;
        localPlaceholder.Text = Model.LocalPlaceholder; resultPlaceholder.Text = Model.ResultPlaceholder;
        localStatistics.Visibility = remoteStatistics.Visibility = Model.StatisticsVisible ? Visibility.Visible : Visibility.Collapsed;
        localPlaceholder.Margin = resultPlaceholder.Margin = new(24, 0, 24, 0);
        foreach (var (mode, viewer) in referenceScrollers) viewer.Visibility = mode == Model.SelectedMode ? Visibility.Visible : Visibility.Collapsed;
        foreach (var (mode, tab) in tabs)
        {
            bool selected = mode == Model.SelectedMode;
            tab.Background = Theme.Brush(selected ? "#FFFFFF" : "#00FFFFFF"); tab.BorderBrush = Theme.Brush(selected ? "#0D000000" : "#00FFFFFF");
            ((TextBlock)tab.Content).Foreground = Theme.Brush(selected ? "#111318" : "#6B7380");
        }
        freePromptBox.Visibility = Model.SelectedMode == "free" ? Visibility.Visible : Visibility.Collapsed;
        freeUpload.Visibility = Model.HasFreeReference ? Visibility.Collapsed : Visibility.Visible;
        freeReferenceHost.Visibility = Model.HasFreeReference ? Visibility.Visible : Visibility.Collapsed;
        freeReferenceImage.Source = Model.FreeReference?.Thumbnail as ImageSource;
        freeReferenceUploadOverlay.SetUploading(Model.FreeReference?.IsUploading == true, Model.FreeReference?.UploadProgress);
        freeReferenceStatus.Text = Model.FreeReference?.HasError == true ? AppText.Get("Retry") : "";
        submit.IsEnabled = Model.SubmitPromptCommand.CanExecute(null);
        UpdateToast();
        foreach (var tile in ReferenceTiles.Values) tile.IsEnabled = Model.CanEdit && !tile.Item.IsUploading;
        if (changed)
        {
            if (Model.Active) DisposeAboutView();
            previousActive = Model.Active; ClosePopups(); scroller.ChangeView(null, 0, null, true);
            if (root.IsLoaded)
            { ArrangePage(); PageEntry.Reveal(Model.Active ? workspace : landing); if (!Model.Active) PageEntry.Reveal(footer); }
        }
        RequestLayout();
        RefreshAccountUi();
    }
    private void RequestLayout()
    {
        if (layoutPending) return;
        layoutPending = true;
        DispatcherQueue.TryEnqueue(() => { layoutPending = false; ArrangePage(); });
    }
    internal void ArrangePage()
    {
        double width = scroller.ViewportWidth > 0 ? scroller.ViewportWidth : root.ActualWidth;
        double height = scroller.ViewportHeight > 0 ? scroller.ViewportHeight : root.ActualHeight;
        if (width <= 0 || height <= 0) return;
        page.Width = width; header.Width = footer.Width = workspace.Width = width - 56; landing.Width = width;
        brand.Height = Math.Clamp(width * .008 + 24, 34, 52); brand.Width = brand.Height * 552 / 172;
        title.FontSize = Math.Clamp(width * .01 + 18, 27, 45);
        landingStage.Margin = new(0, Math.Clamp(width * .011 + 17, 26, 40), 0, 0);
        landingStage.Width = Math.Min(width - 56, Math.Min(940, Math.Max(580, width * .45)));
        landingStage.Height = landingStage.Width * 1080 / 1920;
        terms.Width = Math.Max(0, landingStage.Width - 40); terms.FontSize = Math.Clamp(width * .0028 + 9.5, 12, 15);
        StartButton.FontSize = Math.Clamp(width * .003 + 12, 15, 18);
        double padding = Math.Clamp(width * .0075 + 18, 25, 40); StartButton.Padding = new(padding - 1, 0, padding + 1, 0);
        StartButton.Height = Math.Max(20, Math.Ceiling(StartButton.FontSize * 1.3)) + Math.Clamp(width * .0028 + 9, 12, 16) * 2; StartButton.Refresh();
        localPanel.Height = remotePanel.Height = Math.Max(0, (width - 80) / 2 * 1080 / 1920);
        freePromptBox.Width = Math.Min(880, workspace.Width);
        double workspaceHeight = localPanel.Height + 34 + 42 + 28 + referenceArea.Height;
        double contentHeight = header.Height + 8 + workspaceHeight;
        page.Height = Math.Max(height, Model.Active ? contentHeight + 48 : 760);
        double contentTop = Model.Active ? (page.Height - contentHeight) / 2 : 24;
        Canvas.SetLeft(header, 28); Canvas.SetTop(header, contentTop);
        Canvas.SetLeft(workspace, 28); Canvas.SetTop(workspace, contentTop + header.Height + 8);
        landing.Measure(new Size(width, double.PositiveInfinity));
        Canvas.SetTop(landing, Math.Max(24 + 108, (page.Height - landing.DesiredSize.Height) / 2 - 5));
        Canvas.SetLeft(footer, 28); Canvas.SetTop(footer, page.Height - 72);
        previewFooter.Width = width; Canvas.SetTop(previewFooter, page.Height - 20);
    }
    private void OpenLink(string url)
    { try { Process.Start(new ProcessStartInfo(FaceNow.Core.Product.ProductProfile.Current.ResolveLink(url)) { UseShellExecute = true }); } catch (Exception error) { Model.ReportError(error); } }
}
