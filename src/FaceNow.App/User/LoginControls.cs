using System.Numerics;
using System.Runtime.CompilerServices;
using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace FaceNow.App.User;

internal static class LoginTypography
{
    // The bundled variable font's name table declares "DM Sans 9pt"; "DM Sans" falls back to Segoe UI.
    internal static readonly FontFamily Font = new("ms-appx:///Assets/DMSans.ttf#DM Sans 9pt");
    internal static TextBlock Text(string text = "", double size = 13, string color = "#111318")
    { var label = Theme.Text(text, size, color); label.FontFamily = Font; return label; }

    private static readonly ConditionalWeakTable<TextBlock, TranslateTransform> prefixOffsets = new();
    internal static void CenterCountryCode(TextBlock label)
    {
        if (prefixOffsets.TryGetValue(label, out _)) return;
        var offset = new TranslateTransform(); prefixOffsets.Add(label, offset);
        label.Padding = new(0); label.VerticalAlignment = VerticalAlignment.Center; label.RenderTransform = offset;
        void Position()
        {
            // Optical centering is only for the separate +86 label, never an editor placeholder.
            offset.Y = label.ActualHeight / 2 - label.BaselineOffset + label.FontSize * .35;
        }
        label.SizeChanged += (_, _) => Position();
        label.RegisterPropertyChangedCallback(TextBlock.TextProperty, (_, _) => Position());
        label.RegisterPropertyChangedCallback(TextBlock.FontSizeProperty, (_, _) => Position());
        Position();
    }
}

internal sealed class LoginShadow
{
    private readonly Grid host;
    private readonly Func<float> radius;
    private readonly Color color;
    private readonly float blur, offset;
    private Microsoft.UI.Composition.DropShadow? shadow;
    private Action? resize;
    private float opacity;
    internal LoginShadow(Grid host, Func<float> radius, Color color, float blur, float offset, float opacity)
    {
        this.host = host; this.radius = radius; this.color = color; this.blur = blur; this.offset = offset; this.opacity = opacity;
        host.Loaded += (_, _) => Initialize(); host.SizeChanged += (_, _) => resize?.Invoke();
    }
    internal void SetOpacity(float value) { opacity = value; if (shadow is not null) shadow.Opacity = value; }
    private void Initialize()
    {
        if (shadow is not null) return;
        var compositor = ElementCompositionPreview.GetElementVisual(host).Compositor;
        var geometry = compositor.CreateRoundedRectangleGeometry();
        var shape = compositor.CreateSpriteShape(geometry); shape.FillBrush = compositor.CreateColorBrush(Microsoft.UI.Colors.White);
        var caster = compositor.CreateShapeVisual(); caster.Shapes.Add(shape);
        var mask = compositor.CreateVisualSurface(); mask.SourceVisual = caster;
        shadow = compositor.CreateDropShadow(); shadow.Color = color; shadow.BlurRadius = blur;
        shadow.Offset = new(0, offset, 0); shadow.Opacity = opacity; shadow.Mask = compositor.CreateSurfaceBrush(mask);
        var visual = compositor.CreateSpriteVisual(); visual.Shadow = shadow;
        resize = () =>
        {
            var size = new Vector2((float)host.ActualWidth, (float)host.ActualHeight);
            geometry.Size = caster.Size = mask.SourceSize = visual.Size = size;
            geometry.CornerRadius = new(radius());
        };
        resize(); ElementCompositionPreview.SetElementChildVisual(host, visual);
    }
}

/// <summary>Login-only control presentation, matching the AppKit controls without changing the studio toolbar.</summary>
internal static class LoginMotion
{
    private sealed class State { public State() { } public object? Desired; public Storyboard? Animation; }
    private static readonly ConditionalWeakTable<DependencyObject, State> states = new();
    internal static bool Enabled => new UISettings().AnimationsEnabled;
    internal static void Color(FrameworkElement owner, SolidColorBrush brush, string hex)
    {
        var next = Theme.Brush(hex).Color;
        var state = states.GetOrCreateValue(brush);
        if (Equals(state.Desired, next)) return;
        bool animate = state.Desired is not null && owner.IsLoaded && Enabled;
        var current = brush.Color;
        state.Animation?.Stop(); state.Desired = next; brush.Color = next;
        if (!animate) return;
        var animation = new ColorAnimation { From = current, To = next, Duration = TimeSpan.FromSeconds(.3),
            EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
        Storyboard.SetTarget(animation, brush); Storyboard.SetTargetProperty(animation, "Color");
        var storyboard = new Storyboard { FillBehavior = FillBehavior.Stop }; storyboard.Children.Add(animation);
        state.Animation = storyboard; storyboard.Begin();
    }
    internal static void Opacity(FrameworkElement owner, double next)
    {
        var state = states.GetOrCreateValue(owner);
        if (Equals(state.Desired, next)) return;
        bool animate = state.Desired is not null && owner.IsLoaded && Enabled;
        double current = owner.Opacity;
        state.Animation?.Stop(); state.Desired = next; owner.Opacity = next;
        if (!animate) return;
        var animation = new DoubleAnimation { From = current, To = next, Duration = TimeSpan.FromSeconds(.3),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut } };
        Storyboard.SetTarget(animation, owner); Storyboard.SetTargetProperty(animation, "Opacity");
        var storyboard = new Storyboard { FillBehavior = FillBehavior.Stop }; storyboard.Children.Add(animation);
        state.Animation = storyboard; storyboard.Begin();
    }
}

internal sealed class LoginActionButton : Button
{
    private readonly TextBlock label = LoginTypography.Text();
    private readonly ProgressRing spinner = new() { Width = 18, Height = 18, Foreground = Theme.Brush("#FFFFFF"), Visibility = Visibility.Collapsed };
    private readonly SolidColorBrush surface = Theme.Brush("#2F46E2");
    private bool hovered, pressed, loading;
    private double scale = 1;
    internal string Text { get => label.Text; set { if (label.Text != value) label.Text = value; } }
    internal LoginActionButton(string text)
    {
        Template = Theme.ButtonTemplate; UseSystemFocusVisuals = true;
        Background = surface; BorderThickness = new(0); MinHeight = MinWidth = 0;
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch; VerticalContentAlignment = VerticalAlignment.Stretch;
        label.Text = text; label.Foreground = Theme.Brush("#FFFFFF"); label.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        label.TextAlignment = TextAlignment.Center;
        var content = new Grid(); content.Children.Add(label); content.Children.Add(spinner); Content = content;
        label.HorizontalAlignment = HorizontalAlignment.Center;
        spinner.HorizontalAlignment = HorizontalAlignment.Center; spinner.VerticalAlignment = VerticalAlignment.Center;
        AutomationProperties.SetName(this, text);
        PointerEntered += (_, _) => { hovered = true; Refresh(); };
        PointerExited += (_, _) => { hovered = pressed = false; Refresh(); };
        PointerPressed += (_, _) => { pressed = true; Refresh(); };
        PointerReleased += (_, _) => { pressed = false; Refresh(); };
        RegisterPropertyChangedCallback(IsEnabledProperty, (_, _) => Refresh());
        ApplyScale(1, false); Refresh();
    }
    internal void ApplyScale(double value, bool compact)
    {
        scale = value; Height = (compact ? 38 : 54) * scale;
        CornerRadius = new((compact ? 6 : 12) * scale);
        label.FontSize = (compact ? 12.5 : 16) * scale;
        Padding = new(0);
    }
    internal double PreferredWidth
    {
        get { label.Measure(new(double.PositiveInfinity, double.PositiveInfinity)); return Math.Ceiling(label.DesiredSize.Width) + 24 * scale; }
    }
    internal void SetLoading(bool value)
    {
        if (loading == value) return;
        loading = value; spinner.IsActive = value;
        spinner.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
        label.Visibility = value ? Visibility.Collapsed : Visibility.Visible;
        AutomationProperties.SetItemStatus(this, value ? "Loading" : ""); Refresh();
    }
    private void Refresh()
    {
        LoginMotion.Color(this, surface, hovered && IsEnabled ? "#2438C4" : "#2F46E2");
        LoginMotion.Opacity(this, loading ? .9 : !IsEnabled ? .65 : pressed ? .85 : 1);
    }
}

internal sealed class LoginMethodSelector : UserControl
{
    private readonly Grid track = new() { Background = Theme.Brush("#F2F2F3") };
    private readonly Button[] buttons = new Button[3];
    private readonly TextBlock[] labels = new TextBlock[3];
    private readonly SolidColorBrush[] surfaces = new SolidColorBrush[3];
    private readonly SolidColorBrush[] foregrounds = new SolidColorBrush[3];
    private readonly LoginShadow[] shadows = new LoginShadow[3];
    private readonly bool[] available = [true, true, true];
    private int selectedIndex, hoveredIndex = -1, pressedIndex = -1;
    internal event Action? SelectionChanged;
    internal int SelectedIndex
    {
        get => selectedIndex;
        set { if (value is < 0 or > 2 || selectedIndex == value) return; selectedIndex = value; Refresh(); SelectionChanged?.Invoke(); }
    }
    internal LoginMethodSelector()
    {
        HorizontalContentAlignment = HorizontalAlignment.Stretch; VerticalContentAlignment = VerticalAlignment.Stretch;
        string[] titles = ["Phone", "Email", "API Key"];
        for (int i = 0; i < 3; i++)
        {
            int index = i; track.ColumnDefinitions.Add(new());
            foregrounds[i] = Theme.Brush("#6B7380"); surfaces[i] = Theme.Brush("#F2F2F3");
            labels[i] = LoginTypography.Text(titles[i], 15); labels[i].FontWeight = Microsoft.UI.Text.FontWeights.Medium;
            labels[i].Foreground = foregrounds[i]; labels[i].TextAlignment = TextAlignment.Center;
            var button = new Button { Template = Theme.ButtonTemplate, Background = surfaces[i], BorderThickness = new(0),
                Content = labels[i], Padding = new(0), MinWidth = 0, MinHeight = 0,
                UseSystemFocusVisuals = false,
                HorizontalAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center };
            AutomationProperties.SetName(button, titles[i]);
            button.Click += (_, _) => { if (available[index]) SelectedIndex = index; };
            button.PointerEntered += (_, _) => { hoveredIndex = index; Refresh(); };
            button.PointerExited += (_, _) => { if (hoveredIndex == index) hoveredIndex = -1; pressedIndex = -1; Refresh(); };
            button.PointerPressed += (_, _) => { pressedIndex = index; Refresh(); };
            button.PointerReleased += (_, _) => { pressedIndex = -1; Refresh(); };
            button.KeyDown += (_, args) =>
            {
                if (args.Key is not (global::Windows.System.VirtualKey.Left or global::Windows.System.VirtualKey.Right)) return;
                int step = args.Key == global::Windows.System.VirtualKey.Left ? -1 : 1;
                for (int next = index + step; next is >= 0 and < 3; next += step)
                    if (available[next]) { SelectedIndex = next; buttons[next].Focus(FocusState.Keyboard); break; }
                args.Handled = true;
            };
            var shadowHost = new Grid { IsHitTestVisible = false };
            shadows[i] = new(shadowHost, () => (float)button.CornerRadius.TopLeft, Microsoft.UI.Colors.Black, 4, 2, i == 0 ? .1f : 0);
            Grid.SetColumn(shadowHost, i); track.Children.Add(shadowHost);
            buttons[i] = button; Grid.SetColumn(button, i); track.Children.Add(button);
            button.GotFocus += (_, _) =>
            {
                button.BorderThickness = new(button.FocusState == FocusState.Keyboard ? 1 : 0);
                button.BorderBrush = Theme.Brush("#828FF0");
            };
            button.LostFocus += (_, _) => button.BorderThickness = new(0);
        }
        Content = track;
        RegisterPropertyChangedCallback(IsEnabledProperty, (_, _) => Refresh());
        ApplyScale(1); Refresh();
    }
    internal void SetAvailability(bool phone, bool email)
    { available[0] = phone; available[1] = email; Refresh(); }
    internal void ApplyScale(double scale)
    {
        Height = 52 * scale; track.CornerRadius = new(26 * scale); track.Padding = new(4 * scale); track.ColumnSpacing = 2 * scale;
        for (int i = 0; i < 3; i++) { buttons[i].CornerRadius = new(22 * scale); labels[i].FontSize = 15 * scale; }
    }
    private void Refresh()
    {
        for (int i = 0; i < 3; i++)
        {
            bool selected = i == selectedIndex, enabled = IsEnabled && available[i], hot = enabled && i == hoveredIndex;
            buttons[i].IsEnabled = enabled;
            LoginMotion.Color(this, surfaces[i], i == pressedIndex && enabled ? selected ? "#FAFAFA" : "#F0F0F0" : selected ? "#FFFFFF" : hot ? "#FBFBFB" : "#F2F2F3");
            LoginMotion.Color(this, foregrounds[i], selected || hot ? "#111318" : "#6B7380");
            LoginMotion.Opacity(buttons[i], enabled ? 1 : .5);
            shadows[i].SetOpacity(selected ? .1f : 0);
            AutomationProperties.SetItemStatus(buttons[i], selected ? "Selected" : "");
        }
    }
}

/// <summary>One shared surface contains the country prefix, editor and optional trailing action.</summary>
internal sealed class LoginInput : UserControl
{
    private readonly Grid body = new();
    private readonly Border surface = new();
    private readonly Control editor;
    private readonly SolidColorBrush background = Theme.Brush("#FBFCFC"), outline = Theme.Brush("#E5E7EB");
    private readonly TextBlock prefix = LoginTypography.Text("+86", 15);
    private readonly Border prefixDivider = new() { Width = 1, Height = 20, Background = Theme.Brush("#E5E7EB"), VerticalAlignment = VerticalAlignment.Center };
    private readonly Border actionDivider = new() { Width = 1, Height = 20, Background = Theme.Brush("#E5E7EB"), VerticalAlignment = VerticalAlignment.Center };
    private readonly Grid prefixRegion = new(), accessoryRegion = new();
    private readonly ColumnDefinition prefixColumn = new() { Width = new(0) }, actionColumn = new() { Width = new(0) };
    private bool focused, showPrefix;
    private ScrollViewer? editorViewport;
    private string? invalidMessage;
    private double scale = 1;
    internal LoginInput(Control editor, LoginActionButton? action = null)
    {
        this.editor = editor;
        HorizontalContentAlignment = HorizontalAlignment.Stretch; VerticalContentAlignment = VerticalAlignment.Stretch;
        surface.Background = background; surface.BorderBrush = outline; surface.BorderThickness = new(1);
        body.ColumnDefinitions.Add(prefixColumn); body.ColumnDefinitions.Add(new()); body.ColumnDefinitions.Add(actionColumn);
        prefix.HorizontalAlignment = HorizontalAlignment.Center; prefix.IsHitTestVisible = false;
        LoginTypography.CenterCountryCode(prefix);
        prefixRegion.Children.Add(prefix); prefixDivider.HorizontalAlignment = HorizontalAlignment.Right;
        prefixRegion.Children.Add(prefixDivider); body.Children.Add(prefixRegion);
        Grid.SetColumn(editor, 1); body.Children.Add(editor);
        if (action is not null)
        {
            actionDivider.HorizontalAlignment = HorizontalAlignment.Left; accessoryRegion.Children.Add(actionDivider);
            action.VerticalAlignment = VerticalAlignment.Center;
            action.Margin = new(16, 0, 8, 0); accessoryRegion.Children.Add(action);
            Grid.SetColumn(accessoryRegion, 2); body.Children.Add(accessoryRegion);
        }
        ConfigureEditor(editor);
        editor.Loaded += (_, _) => CenterNativeTextLine();
        editor.Unloaded += (_, _) => editorViewport = null;
        surface.Child = body; Content = surface;
        editor.GotFocus += (_, _) => { focused = true; Refresh(); };
        editor.LostFocus += (_, _) => { focused = false; Refresh(); };
        surface.PointerPressed += (_, _) => { if (IsEnabled && editor.IsEnabled) editor.Focus(FocusState.Pointer); };
        RegisterPropertyChangedCallback(IsEnabledProperty, (_, _) => { editor.IsEnabled = IsEnabled; Refresh(); });
        ApplyScale(1); Refresh();
    }
    internal void SetPrefix(bool value)
    { if (showPrefix == value) return; showPrefix = value; ApplyScale(scale); }
    internal void SetInvalid(string? value)
    {
        if (invalidMessage == value) return;
        invalidMessage = value; ToolTipService.SetToolTip(this, value);
        AutomationProperties.SetHelpText(editor, value ?? ""); Refresh();
    }
    internal void SetAccessoryWidth(double width)
    { actionColumn.Width = new(width + 24 * scale); }
    internal void ApplyScale(double value)
    {
        scale = value; Height = 54 * scale; surface.CornerRadius = new(12 * scale);
        editor.FontSize = prefix.FontSize = 15 * scale;
        // Include the native caret's full height and balance the cap/digit ink within its line box.
        // Placeholder and input text share a line center, independent of the visible glyphs.
        editor.Height = Math.Ceiling(26 * scale);
        editor.Padding = new(0, 2 * scale, 0, 0);
        prefixColumn.Width = new(showPrefix ? 64 * scale : 0);
        prefixRegion.Visibility = showPrefix ? Visibility.Visible : Visibility.Collapsed;
        editor.Margin = new(showPrefix ? 14 * scale : 20 * scale, 0, 20 * scale, 0);
        prefixDivider.Height = actionDivider.Height = 20 * scale;
        if (accessoryRegion.Children.Count > 1 && accessoryRegion.Children[1] is FrameworkElement action)
            // The outer border consumes height; fixed vertical margins would clip the fixed-height button.
            action.Margin = new(16 * scale, 0, 8 * scale, 0);
        if (editor.IsLoaded) CenterNativeTextLine();
    }
    private void CenterNativeTextLine()
    {
        CenterNativeTextLine(editor, ref editorViewport);
    }
    internal object TextLineMetrics()
    {
        var views = new List<object>();
        void Visit(DependencyObject parent)
        {
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
            {
                var child = VisualTreeHelper.GetChild(parent, i);
                if (child is FrameworkElement element && (element.Name is "ContentElement" or "PlaceholderTextContentPresenter" || element.GetType().Name.Contains("TextBoxView")))
                    views.Add(new { element.Name, type = element.GetType().Name, y = element.TransformToVisual(editor).TransformPoint(new()).Y,
                        height = element.ActualHeight, baseline = (element as TextBlock)?.BaselineOffset, element.Margin,
                        padding = (element as TextBlock)?.Padding });
                Visit(child);
            }
        }
        Visit(editor);
        return new { height = editor.ActualHeight, editor.Padding, views };
    }
    private static void CenterNativeTextLine(Control control, ref ScrollViewer? viewport)
    {
        // The default template stretches the editing viewport to the clear-button row.
        // Center both the viewport and its measured text view so typed text and caret share the prefix line.
        static ScrollViewer? FindContent(DependencyObject root)
        {
            ScrollViewer? result = null;
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            {
                var child = VisualTreeHelper.GetChild(root, i);
                if (child is TextBlock { Name: "PlaceholderTextContentPresenter" } placeholder)
                {
                    // Center the full font line, just like the native editing viewport.
                    // Per-string ink offsets or template top padding give it a different baseline.
                    placeholder.Padding = new(0);
                    placeholder.VerticalAlignment = VerticalAlignment.Center;
                }
                if (child is ScrollViewer { Name: "ContentElement" } content) result = content;
                if (FindContent(child) is { } nested) result ??= nested;
            }
            return result;
        }
        viewport ??= FindContent(control);
        if (viewport is { } content)
        {
            content.VerticalAlignment = VerticalAlignment.Center;
            content.VerticalContentAlignment = VerticalAlignment.Center;
            if (content.Content is FrameworkElement textView)
                textView.VerticalAlignment = VerticalAlignment.Center;
        }
    }
    private void Refresh()
    {
        LoginMotion.Color(this, background, focused ? "#FFFFFF" : "#FBFCFC");
        LoginMotion.Color(this, outline, invalidMessage is not null ? "#DC2626" : focused ? "#828FF0" : "#E5E7EB");
        surface.BorderThickness = new(focused || invalidMessage is not null ? 1.5 : 1);
        LoginMotion.Opacity(this, IsEnabled ? 1 : .55);
    }
    private static void ConfigureEditor(Control editor)
    {
        editor.Background = Theme.Brush("#00FFFFFF"); editor.BorderBrush = Theme.Brush("#00FFFFFF");
        editor.BorderThickness = new(0); editor.Padding = new(0); editor.MinHeight = editor.MinWidth = 0;
        editor.FontFamily = LoginTypography.Font; editor.FontWeight = Microsoft.UI.Text.FontWeights.Normal;
        editor.Foreground = Theme.Brush("#111318"); editor.VerticalContentAlignment = VerticalAlignment.Center;
        editor.HorizontalAlignment = HorizontalAlignment.Stretch; editor.VerticalAlignment = VerticalAlignment.Center;
        editor.UseSystemFocusVisuals = false;
        foreach (string suffix in new[] { "", "PointerOver", "Focused", "Disabled" })
        {
            editor.Resources["TextControlBackground" + suffix] = Theme.Brush("#00FFFFFF");
            editor.Resources["TextControlBorderBrush" + suffix] = Theme.Brush("#00FFFFFF");
            editor.Resources["TextControlForeground" + suffix] = Theme.Brush("#111318");
            editor.Resources["TextControlPlaceholderForeground" + suffix] = Theme.Brush("#808080");
        }
        editor.Resources["TextControlBorderThemeThickness"] = new Thickness(0);
        editor.Resources["TextControlBorderThemeThicknessFocused"] = new Thickness(0);
        editor.Resources["TextControlThemePadding"] = new Thickness(0);
        if (editor is TextBox text) { text.IsSpellCheckEnabled = false; text.IsTextPredictionEnabled = false; }
        if (editor is PasswordBox password) password.PasswordRevealMode = PasswordRevealMode.Hidden;
    }
}
