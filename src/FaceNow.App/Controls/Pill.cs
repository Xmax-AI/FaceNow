//
//  Pill.cs
//  FaceNow
//

// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using FaceNow.App.User;

namespace FaceNow.App.Controls;

internal class Pill : Button
{
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text),
        typeof(string),
        typeof(Pill),
        new PropertyMetadata(
        "",
        Changed
    )
    );
    public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(
        nameof(Glyph),
        typeof(string),
        typeof(Pill),
        new PropertyMetadata(
        "",
        Changed
    )
    );
    public static readonly DependencyProperty AccentProperty = DependencyProperty.Register(
        nameof(Accent),
        typeof(bool),
        typeof(Pill),
        new PropertyMetadata(
        false,
        Changed
    )
    );
    public static readonly DependencyProperty ContentSpacingProperty = DependencyProperty.Register(
        nameof(ContentSpacing),
        typeof(double),
        typeof(Pill),
        new PropertyMetadata(
        8d,
        Changed
    )
    );
    private bool hot, pressed, focused, fitArtwork;
    private readonly StackPanel body = new() { Orientation = Orientation.Horizontal, Spacing = 8 };
    private readonly Grid iconSlot = new() { VerticalAlignment = VerticalAlignment.Center };
    private readonly Glyph icon = new()
    {
        Width = 16,
        Height = 16,
        VerticalAlignment = VerticalAlignment.Center
    };
    private ActivitySpinner? spinner;
    private readonly TextBlock label = Theme.Text();
    private readonly Glyph chevron = new()
    {
        Kind = "chevron",
        Width = 12,
        Height = 12,
        Margin = new(-3, 0, -3, 0),
        VerticalAlignment = VerticalAlignment.Center,
        Visibility = Visibility.Collapsed
    };

    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, AppText.Get(value));
    }

    public string Glyph
    {
        get => (string)GetValue(GlyphProperty);
        set => SetValue(GlyphProperty, value);
    }

    public bool Accent
    {
        get => (bool)GetValue(AccentProperty);
        set => SetValue(AccentProperty, value);
    }

    public double ContentSpacing
    {
        get => (double)GetValue(ContentSpacingProperty);
        set => SetValue(ContentSpacingProperty, value);
    }

    internal bool Primary { get; set; }

    internal bool Destructive { get; set; }

    internal bool ExtraChevron { get; set; }

    internal bool Translucent { get; set; }

    private readonly SolidColorBrush translucentSurface = Theme.Brush("#47000000");

    internal double LabelMaxWidth { get; set; } = 150;

    protected virtual double IconSize => Primary ? 20 : 16;

    public Pill()
    {
        Template = Theme.ButtonTemplate;
        UseSystemFocusVisuals = false;
        FontFamily = Theme.Font;
        FontSize = 13;
        Height = 36;
        MinWidth = 36;
        Padding = new(15, 0, 15, 0);
        HorizontalContentAlignment = HorizontalAlignment.Center;
        VerticalContentAlignment = VerticalAlignment.Center;
        iconSlot.Children.Add(icon);
        body.Children.Add(iconSlot);
        body.Children.Add(label);
        body.Children.Add(chevron);
        Content = body;
        ProtectedCursor = Microsoft.UI.Input.InputSystemCursor.Create(Microsoft.UI.Input.InputSystemCursorShape.Hand);
        PointerEntered += (_, _) =>
        {
            hot = true;
            Refresh();
        };
        PointerExited += (_, _) =>
        {
            hot = false;
            pressed = false;
            Refresh();
        };
        PointerPressed += (_, _) =>
        {
            pressed = true;
            focused = false;
            Refresh();
        };
        PointerReleased += (_, _) =>
        {
            pressed = false;
            Refresh();
        };
        GotFocus += (_, _) =>
        {
            focused = FocusState == Microsoft.UI.Xaml.FocusState.Keyboard;
            Refresh();
        };
        LostFocus += (_, _) =>
        {
            focused = false;
            Refresh();
        };
        RegisterPropertyChangedCallback(IsEnabledProperty, (_, _) => Refresh());
        Loaded += (_, _) => Refresh();
    }

    private static void Changed(
        DependencyObject sender,
        DependencyPropertyChangedEventArgs args
    ) => ((Pill)sender).Refresh();

    internal virtual void Refresh()
    {
        bool loading = spinner?.IsActive == true;
        chevron.Visibility = ExtraChevron ? Visibility.Visible : Visibility.Collapsed;
        icon.Kind = Glyph;
        icon.Visibility = loading ? Visibility.Collapsed : Visibility.Visible;
        iconSlot.Visibility = Glyph.Length > 0 || loading ? Visibility.Visible : Visibility.Collapsed;
        iconSlot.Width = fitArtwork && !loading ? double.NaN : IconSize;
        iconSlot.Height = IconSize;
        if (!fitArtwork)
            icon.Width = icon.Height = IconSize;
        label.Text = Text;
        label.Visibility = Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        label.FontFamily = FontFamily;
        label.FontSize = FontSize;
        label.FontWeight = Primary || Destructive ? Microsoft.UI.Text.FontWeights.SemiBold : FontWeight;
        label.TextTrimming = TextTrimming.CharacterEllipsis;
        label.MaxWidth = ExtraChevron ? LabelMaxWidth : double.PositiveInfinity;
        body.Spacing = ContentSpacing;
        BorderThickness = new(1);
        CornerRadius = new(Height / 2);
        ApplyAppearance(hot, pressed, focused);
        if (Text.Length > 0 && string.IsNullOrEmpty(AutomationProperties.GetName(this)))
            AutomationProperties.SetName(this, Text);
    }

    protected void SetContentForeground(
        Brush foreground,
        Brush? iconForeground = null
    )
    {
        Foreground = label.Foreground = chevron.Foreground = foreground;
        icon.Foreground = iconForeground ?? foreground;
    }

    protected void SetLabelVerticalOffset(
        double offset
    ) => label.RenderTransform = new TranslateTransform { Y = offset };

    protected void FitContentArtwork(
        double chevronSize
    )
    {
        fitArtwork = true;
        icon.FitArtwork(IconSize);
        chevron.FitArtwork(chevronSize);
        chevron.Margin = new(0);
        label.OpticalMarginAlignment = OpticalMarginAlignment.TrimSideBearings;
    }

    protected void ShowLoadingIcon(
        bool loading
    )
    {
        if (loading && spinner is null)
        {
            spinner = new()
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            iconSlot.Children.Add(spinner);
        }
        if (spinner is not null)
        {
            spinner.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;
            spinner.IsActive = loading;
        }
    }

    protected virtual void ApplyAppearance(
        bool hot,
        bool pressed,
        bool focused
    )
    {
        string color = Translucent ? "#D9FFFFFF" : Primary ? "#FFFFFF" : Destructive ? "#DC2626" : Accent ? "#2F46E2" : "#111318";
        SetContentForeground(Theme.Brush(color));
        BorderBrush = Theme.Brush(Translucent ? "#29FFFFFF" : Primary ? "#00FFFFFF" : Destructive ? "#F1BABA" : Accent ? "#D7DDFB" : focused ? "#2F46E2" : hot ? "#C9CED6" : "#E2E5EA");
        Background = Translucent ? translucentSurface : Primary || Accent || Destructive ? Theme.Brush(Primary ? (focused ? "#2438C4" : "#2F46E2") : Accent ? "#EEF1FF" : "#FDF2F2") : new LinearGradientBrush
        {
            StartPoint = new(0, 0),
            EndPoint = new(0, 1),
            GradientStops = { new() { Color = Microsoft.UI.Colors.White }, new()
{
Color = Theme.Brush("#F3F4F6").Color,
Offset = 1
} }
        };
        if (Translucent)
        {
            LoginMotion.Color(this, translucentSurface, hot ? "#563C3C3C" : "#47000000");
            LoginMotion.Opacity(this, !IsEnabled ? .5 : pressed ? .85 : 1);
        }
        else
            Opacity = !IsEnabled ? .5 : pressed ? .85 : 1;
    }
}
