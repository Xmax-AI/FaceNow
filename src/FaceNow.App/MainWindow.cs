//
//  MainWindow.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.ComponentModel;
using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using FaceNow.Windows.Studio.Services;
using FaceNow.Windows.Studio.ViewModels;
using FaceNow.App.Controls;
using FaceNow.App.Platform;
using Xmax.SDK.WinUI;
using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.VirtualCamera;
using FaceNow.Core.User;

namespace FaceNow.App;

public sealed partial class MainWindow : Window
{
    internal MainViewModel Model { get; }

    private readonly Grid root = new()
    {
        Background = Theme.Brush("#FFFFFF"),
        RequestedTheme = ElementTheme.Light
    };
    private readonly ScrollViewer scroller = new()
    {
        HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        HorizontalScrollMode = ScrollMode.Disabled
    };
    private readonly Canvas page = new() { Background = Theme.Brush("#FFFFFF") };
    private readonly Grid header = new() { Height = 60 };
    private readonly Image brand = new()
    {
        Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new("ms-appx:///Assets/FaceNowBrandMark.png")),
        Stretch = Stretch.Uniform
    };
    private readonly TextBlock brandName = Theme.Text("FaceNow", 24);
    private readonly StackPanel homeControls = new()
    {
        Orientation = Orientation.Horizontal,
        Spacing = ToolbarButton.ControlSpacing,
        HorizontalAlignment = HorizontalAlignment.Right,
        VerticalAlignment = VerticalAlignment.Center
    };
    private readonly StackPanel sessionControls = new()
    {
        Orientation = Orientation.Horizontal,
        Spacing = ToolbarButton.ControlSpacing,
        HorizontalAlignment = HorizontalAlignment.Right,
        VerticalAlignment = VerticalAlignment.Center
    };
    private readonly StackPanel landing = new();
    private readonly Grid landingStage = new() { HorizontalAlignment = HorizontalAlignment.Center };
    private readonly TextBlock title = Theme.Text("Bringing Your New Look into Video Calls", 31.6);
    private readonly TextBlock terms = Theme.Text("", 13, "#9CA3AF");
    private readonly StackPanel workspace = new();
    private const double VideoPanelSpacing = 24;
    private readonly Grid videoRow = new() { ColumnSpacing = VideoPanelSpacing };
    private readonly Grid localVideoPanel = new(), resultVideoPanel = new();
    private readonly XmaxRealtimeVideoView localVideoView = new()
    {
        IsMirrored = true,
        IsHitTestVisible = false,
        FirstFrameFadeInDuration = 0
    };
    private readonly XmaxRealtimeVideoView resultVideoView = new() { IsMirrored = true };
    private readonly TextBlock localPlaceholder = Theme.Text("", 14, "#8CFFFFFF");
    private readonly TextBlock resultPlaceholder = Theme.Text("", 14, "#8CFFFFFF");
    private readonly StackPanel localStatistics = new(), remoteStatistics = new();
    private readonly Grid referenceArea = new() { Height = 190 };
    private readonly Dictionary<string, ScrollViewer> referenceScrollers = [];
    internal readonly Dictionary<ReferenceItem, ReferenceTile> ReferenceTiles = [];
    private readonly Dictionary<string, CenteredWrapPanel> referencePanels = [];
    private readonly Dictionary<string, Button> tabs = [];
    private readonly Border freePromptBox = new()
    {
        Height = 160,
        Margin = new(0, 4, 0, 0),
        CornerRadius = new(18),
        Background = Theme.Brush("#F7F8FA"),
        BorderBrush = Theme.Brush("#E5E7EB"),
        BorderThickness = new(1),
        VerticalAlignment = VerticalAlignment.Top,
        HorizontalAlignment = HorizontalAlignment.Center
    };
    private readonly TextBox promptEditor = new()
    {
        PlaceholderText = AppText.Get("Describe how you want the video to change"),
        AcceptsReturn = true,
        TextWrapping = TextWrapping.Wrap,
        BorderThickness = new(0),
        Background = Theme.Brush("#00FFFFFF"),
        Padding = new(0),
        FontFamily = new("Segoe UI"),
        FontSize = 15
    };
    private readonly Grid freeReferenceHost = new()
    {
        Width = 44,
        Height = 44,
        Margin = new(0, 0, 10, 0)
    };
    private readonly Image freeReferenceImage = new() { Stretch = Stretch.UniformToFill };
    private readonly ReferenceUploadOverlay freeReferenceUploadOverlay = new(compact: true);
    private readonly TextBlock freeReferenceStatus = Theme.Text("", 8, "#FFFFFF");
    private readonly Grid footer = new() { Height = 36 };
    private readonly TextBlock previewFooter = Theme.Text(
        "UI preview · no camera, network session or generated output",
        11,
        "#9CA3AF"
    );
    private readonly Pill previewBadge = new()
    {
        Text = AppText.Get("UI Preview · camera off"),
        Accent = true,
        Margin = new(16, 0, 0, 0),
        IsHitTestVisible = false
    };
    internal readonly CameraStartButton StartButton = new();
    private readonly LandingInputButton cameraButton = new("Select Camera");
    private readonly CameraAspectPicker cameraAspect = new(MainViewModel.CameraPresets);
    private readonly HomeReferencePicker homeReferences;
    private readonly ToolbarButton modelButton = new(ToolbarButtonRole.Menu)
    {
        Text = "X2.1",
        Visibility = Visibility.Collapsed
    };
    private readonly ToolbarButton keyButton = new() { Glyph = "key" };
    private readonly WindowsVirtualCamera virtualCameraOutput = new();
    private readonly ToolbarButton homeVirtualCamera = new(ToolbarButtonRole.Menu) { Glyph = "display" };
    private readonly ToolbarButton statisticsButton = new(
        ToolbarButtonRole.Toggle,
        ToolbarButtonTone.Accent
    )
    {
        Glyph = "statistics"
    };
    private readonly ToolbarButton elapsed = new(ToolbarButtonRole.Status);
    private readonly ToolbarButton stopButton = new(tone: ToolbarButtonTone.Danger)
    {
        Text = "Stop Session",
        Glyph = "stop"
    };
    private readonly Pill freeUpload = new()
    {
        Glyph = "plus",
        Width = 44,
        Height = 44,
        Padding = new(0),
        Margin = new(0, 0, 10, 0)
    };
    private readonly Pill submit = new()
    {
        Glyph = "arrow",
        Primary = true,
        Width = 44,
        Height = 44,
        Padding = new(0)
    };
    private readonly ToastView toast = new();
    private readonly ApiKeyStore? apiKeyStore;
    private bool initialized, previousActive, closing, closed, settingApiKey, layoutPending;

    internal MainWindow(
        bool preview = false,
        bool previewSession = false,
        ApiKeyStore? store = null,
        bool environmentKey = true,
        bool setupPreview = false,
        UserRepository? user = null
    )
    {
        cameraSetupPreview = setupPreview;
        Title = preview ? "FaceNow — UI Preview" : FaceNow.Core.Product.ProductProfile.Current.DisplayName;
        if (setupPreview)
            Title = "FaceNow — Camera setup preview (simulated)";
        AppWindow.SetIcon(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "FaceNow.ico"));
        apiKeyStore = store;
        accountRepository = user;
        Model = new(
            new WinUiDispatcher(DispatcherQueue),
            new WinUiThumbnailLoader(),
            virtualCameraOutput,
            user
        );
        homeReferences = new(Model.HomeReferencePresets);
        Model.CameraFilter = item => !virtualCameraOutput.IsOwnCamera(item.Id, item.Name);
        if (preview)
            Model.ConfigurePreview(previewSession);
        root.DataContext = Model;
        BuildUi();
        BuildBeautyUi();
        BuildAccountUi();
        if (setupPreview)
        {
            previewBadge.Text = AppText.Get("Restart setup preview");
            previewBadge.IsHitTestVisible = true;
            previewBadge.Click += (_, _) => ResetCameraSetupPreview();
            previewFooter.Text = AppText.Get("Camera setup simulation · no installation, camera access or system changes");
        }
        Content = root;
        toast.Dismissed += ToastDismissed;
        Model.PropertyChanged += ModelChanged;
        virtualCameraOutput.StatusChanged += () => DispatcherQueue.TryEnqueue(() => { if (!closed) RefreshVirtualCameraUi(); });
        Activated += async (_, args) =>
        {
            if (args.WindowActivationState != WindowActivationState.Deactivated)
                await SynchronizeVirtualCameraStatusAsync();
        };
        Model.ApiKeyRequired += OpenKey;
        Model.CameraRequired += OpenCameras;
        localVideoView.PlaybackFailed += Model.ReportError;
        resultVideoView.PlaybackFailed += Model.ReportError;
        Theme.Bind(
            localVideoView,
            XmaxRealtimeVideoView.TrackProperty,
            nameof(Model.LocalVideo),
            Model
        );
        Theme.Bind(
            resultVideoView,
            XmaxRealtimeVideoView.TrackProperty,
            nameof(Model.RemoteVideo),
            Model
        );
        root.SizeChanged += (_, _) => RequestLayout();
        scroller.ViewChanged += (_, _) => RequestLayout();
        root.Loaded += async (_, _) =>
        {
            if (initialized)
                return;
            initialized = true;
            if (accountRepository is null)
                LoadApiKey(!preview && environmentKey ? Environment.GetEnvironmentVariable("XMAX_API_KEY") : null);
            VerificationProgress("Refreshing virtual camera");
            if (!cameraSetupPreview && !(preview && accountRepository is not null))
                await virtualCameraOutput.RefreshAsync();
            VerificationProgress("Enumerating input cameras");
            if (accountRepository is null)
                await Model.InitializeAsync();
            else
                await InitializeAccountAsync();
            RefreshUi();
            ArrangePage();
            VerificationProgress("Window ready");
            PageEntry.Reveal(Model.Active ? workspace : landing);
            if (!Model.Active)
                PageEntry.Reveal(footer);
            Ready?.Invoke();
        };
        ResizeWindow(1360, 890);
        AppWindow.Closing += async (_, args) =>
        {
            if (closed)
                return;
            args.Cancel = true;
            if (closing)
                return;
            closing = true;
            virtualMicrophoneDialog?.Hide();
            DisposeAboutView();
            ClosePopups();
            root.IsHitTestVisible = false;
            toast.Shutdown();
            DisposeAccountUi();
            try
            {
                try
                {
                    await Model.DisposeAsync();
                }
                finally
                {
                    await virtualCameraOutput.DisposeAsync();
                }
            }
            catch (Exception error)
            {
                Model.ReportError(error);
            }
            finally
            {
                closed = true;
                DispatcherQueue.TryEnqueue(() => Close());
            }
        };
        RefreshUi();
    }

    internal event Action? Ready;

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(
        IntPtr window
    );

    internal void ResizeWindow(
        double width,
        double height
    )
    {
        double scale = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96d;
        if (AppWindow.Presenter is Microsoft.UI.Windowing.OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = (int)(1180 * scale);
            presenter.PreferredMinimumHeight = (int)(800 * scale);
        }
        AppWindow.Resize(new((int)Math.Round(width * scale), (int)Math.Round(height * scale)));
        var area = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(
            AppWindow.Id,
            Microsoft.UI.Windowing.DisplayAreaFallback.Nearest
        ).WorkArea;
        AppWindow.Move(new(
            area.X + (area.Width - AppWindow.Size.Width) / 2,
            area.Y + (area.Height - AppWindow.Size.Height) / 2
        ));
    }

    private void ModelChanged(
        object? sender,
        PropertyChangedEventArgs args
    )
    {
        if (args.PropertyName == nameof(Model.Prompt) && promptEditor.Text != Model.Prompt)
            promptEditor.Text = Model.Prompt;
        RefreshUi();
    }

    private void RefreshUi()
    {
        RefreshBeautyUi();
        RefreshMicrophoneUi();
        bool changed = previousActive != Model.Active;
        homeControls.Visibility = landing.Visibility = footer.Visibility = Model.Active ? Visibility.Collapsed : Visibility.Visible;
        sessionControls.Visibility = workspace.Visibility = Model.Active ? Visibility.Visible : Visibility.Collapsed;
        previewBadge.Visibility = Model.IsPreview ? Visibility.Visible : Visibility.Collapsed;
        previewFooter.Visibility = Model.IsPreview ? Visibility.Visible : Visibility.Collapsed;
        RefreshVirtualCameraUi();
        RefreshLandingControls();
        RefreshVideoPanels();
        RefreshGenerationControls();
        UpdateToast();
        foreach (var tile in ReferenceTiles.Values)
            tile.IsEnabled = Model.CanEdit && !tile.Item.IsUploading;
        if (changed)
        {
            if (Model.Active)
                DisposeAboutView();
            previousActive = Model.Active;
            ClosePopups();
            scroller.ChangeView(null, 0, null, true);
            if (root.IsLoaded)
            {
                ArrangePage();
                PageEntry.Reveal(Model.Active ? workspace : landing);
                if (!Model.Active)
                    PageEntry.Reveal(footer);
            }
        }
        RequestLayout();
        RefreshAccountUi();
    }

    private void RefreshLandingControls()
    {
        cameraButton.Visibility = Model.Active ? Visibility.Collapsed : Visibility.Visible;
        cameraButton.Text = Model.SelectedCamera?.Name ?? "Select Camera";
        ToolTipService.SetToolTip(cameraButton, cameraButton.Text);
        keyButton.Text = Model.KeyLabel;
        cameraButton.IsEnabled = modelButton.IsEnabled = keyButton.IsEnabled = Model.CanEdit;
        StartButton.IsEnabled = Model.CanChooseHomeReference && !cameraSetupPreview;
        StartButton.Text = Model.StartLabel;
        StartButton.SetLoading(Model.Busy && !Model.IsClosing && !Model.Active);
        cameraAspect.Update(Model.SelectedFormat, Model.CanEdit);
        homeReferences.Update(
            Model.HomeSelectedReference,
            Model.HomeCustomReference,
            Model.CanChooseHomeReference,
            Model.Busy
        );
    }

    private void RefreshGenerationControls()
    {
        stopButton.Text = Model.StopLabel;
        statisticsButton.IsSelected = Model.StatisticsVisible;
        string statisticsAction = AppText.Get(Model.StatisticsVisible
            ? "Hide statistics (collection and logging continue)" : "Show statistics");
        AutomationProperties.SetName(statisticsButton, statisticsAction);
        ToolTipService.SetToolTip(statisticsButton, statisticsAction);
        elapsed.Text = Model.Elapsed;
        foreach (var (mode, viewer) in referenceScrollers)
            viewer.Visibility = mode == Model.SelectedMode ? Visibility.Visible : Visibility.Collapsed;
        foreach (var (mode, tab) in tabs)
        {
            bool selected = mode == Model.SelectedMode;
            tab.IsEnabled = Model.CanEdit;
            tab.Background = Theme.Brush(selected ? "#FFFFFF" : "#00FFFFFF");
            tab.BorderBrush = Theme.Brush(selected ? "#0D000000" : "#00FFFFFF");
            ((TextBlock)tab.Content).Foreground = Theme.Brush(selected ? "#111318" : "#6B7380");
        }
        freePromptBox.Visibility = Model.SelectedMode == "free" ? Visibility.Visible : Visibility.Collapsed;
        freeUpload.Visibility = Model.HasFreeReference ? Visibility.Collapsed : Visibility.Visible;
        freeUpload.Visibility = Model.HasFreeReference ? Visibility.Collapsed : Visibility.Visible;
        freeReferenceHost.Visibility = Model.HasFreeReference ? Visibility.Visible : Visibility.Collapsed;
        freeReferenceImage.Source = Model.FreeReference?.Thumbnail as ImageSource;
        freeReferenceUploadOverlay.SetUploading(
            Model.FreeReference?.IsUploading == true,
            Model.FreeReference?.UploadProgress
        );
        freeReferenceStatus.Text = Model.FreeReference?.HasError == true ? AppText.Get("Retry") : "";
        submit.IsEnabled = Model.SubmitPromptCommand.CanExecute(null);
    }

    private void RequestLayout()
    {
        if (layoutPending)
            return;
        layoutPending = true;
        DispatcherQueue.TryEnqueue(() =>
        {
            layoutPending = false;
            ArrangePage();
        });
    }

    internal void ArrangePage()
    {
        double width = scroller.ViewportWidth > 0 ? scroller.ViewportWidth : root.ActualWidth;
        double height = scroller.ViewportHeight > 0 ? scroller.ViewportHeight : root.ActualHeight;
        if (width <= 0 || height <= 0)
            return;
        page.Width = width;
        header.Width = footer.Width = workspace.Width = width - 56;
        landing.Width = width;
        double wordmarkHeight = Math.Clamp(width * .008 + 24, 34, 52);
        brand.Height = brand.Width = wordmarkHeight + 6;
        brandName.FontSize = wordmarkHeight * .7;
        header.Height = brand.Height + 32;
        homeControls.Margin = sessionControls.Margin = new(
            0,
            8 + (brand.Height - homeVirtualCamera.Height) / 2,
            0,
            0
        );
        title.FontSize = Math.Clamp(width * .01 + 18, 27, 45);
        landingStage.Margin = new(0, Math.Clamp(width * .011 + 17, 26, 40), 0, 0);
        landingStage.Width = Math.Min(width - 56, Math.Clamp(width * .55, 640, 1040));
        landingStage.Height = landingStage.Width * 1080 / 1920;
        terms.Width = Math.Max(0, landingStage.Width - 40);
        terms.FontSize = Math.Clamp(width * .0028 + 9.5, 12, 15);
        StartButton.SetViewportWidth(width);
        videoRow.Height = Math.Max(0, (workspace.Width - VideoPanelSpacing) / 2) * 9 / 16;
        freePromptBox.Width = Math.Min(880, workspace.Width);
        double workspaceHeight = videoRow.Height + sessionAudioControls.Margin.Top + sessionAudioControls.Height + ModeTabsTopSpacing + 42 + 28 + referenceArea.Height;
        const double homeTop = 16, landingGap = 30, footerBottom = 72;
        landing.Measure(new Size(width, double.PositiveInfinity));
        double minimumHomeHeight = homeTop + header.Height + landingGap + landing.DesiredSize.Height + landingGap + footerBottom;
        double minimumWorkspaceHeight = homeTop + header.Height + workspaceHeight + 48;
        page.Height = Math.Max(
            height,
            Model.Active ? minimumWorkspaceHeight : Math.Max(
            760,
            minimumHomeHeight
        )
        );
        double contentTop = homeTop + (Model.Active ? (page.Height - minimumWorkspaceHeight) / 2 : 0);
        Canvas.SetLeft(header, 28);
        Canvas.SetTop(header, contentTop);
        Canvas.SetLeft(workspace, 28);
        Canvas.SetTop(workspace, contentTop + header.Height);
        Canvas.SetTop(
            landing,
            Math.Max(
            contentTop + header.Height + landingGap,
            (page.Height - landing.DesiredSize.Height) / 2 - 5
        )
        );
        Canvas.SetLeft(footer, 28);
        Canvas.SetTop(footer, page.Height - footerBottom);
        previewFooter.Width = width;
        Canvas.SetTop(previewFooter, page.Height - 20);
    }

    private void OpenLink(
        string url
    )
    {
        try
        {
            Process.Start(new ProcessStartInfo(FaceNow.Core.Product.ProductProfile.Current.ResolveLink(url)) { UseShellExecute = true });
        }
        catch (Exception error)
        {
            Model.ReportError(error);
        }
    }
}
