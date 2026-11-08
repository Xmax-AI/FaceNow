//
//  LoginInput.cs
//  FaceNow
//

using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App.User;

/// <summary>One shared surface contains the country prefix, editor and optional trailing action.</summary>
internal sealed class LoginInput : UserControl
{
    private readonly Grid body = new();
    private readonly Border surface = new();
    private readonly Control editor;
    private readonly SolidColorBrush background = Theme.Brush("#FBFCFC"), outline = Theme.Brush("#E5E7EB");
    private readonly TextBlock prefix = LoginTypography.Text("+86", 15);
    private readonly Border prefixDivider = new()
    {
        Width = 1,
        Height = 20,
        Background = Theme.Brush("#E5E7EB"),
        VerticalAlignment = VerticalAlignment.Center
    };
    private readonly Border actionDivider = new()
    {
        Width = 1,
        Height = 20,
        Background = Theme.Brush("#E5E7EB"),
        VerticalAlignment = VerticalAlignment.Center
    };
    private readonly Grid prefixRegion = new(), accessoryRegion = new();
    private readonly ColumnDefinition prefixColumn = new() { Width = new(0) }, actionColumn = new() { Width = new(0) };
    private bool focused, showPrefix;
    private ScrollViewer? editorViewport;
    private string? invalidMessage;
    private double scale = 1;

    internal LoginInput(
        Control editor,
        LoginActionButton? action = null
    )
    {
        this.editor = editor;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        surface.Background = background;
        surface.BorderBrush = outline;
        surface.BorderThickness = new(1);
        body.ColumnDefinitions.Add(prefixColumn);
        body.ColumnDefinitions.Add(new());
        body.ColumnDefinitions.Add(actionColumn);
        prefix.HorizontalAlignment = HorizontalAlignment.Center;
        prefix.IsHitTestVisible = false;
        LoginTypography.CenterCountryCode(prefix);
        prefixRegion.Children.Add(prefix);
        prefixDivider.HorizontalAlignment = HorizontalAlignment.Right;
        prefixRegion.Children.Add(prefixDivider);
        body.Children.Add(prefixRegion);
        Grid.SetColumn(editor, 1);
        body.Children.Add(editor);
        if (action is not null)
        {
            actionDivider.HorizontalAlignment = HorizontalAlignment.Left;
            accessoryRegion.Children.Add(actionDivider);
            action.VerticalAlignment = VerticalAlignment.Center;
            action.Margin = new(16, 0, 8, 0);
            accessoryRegion.Children.Add(action);
            Grid.SetColumn(accessoryRegion, 2);
            body.Children.Add(accessoryRegion);
        }
        ConfigureEditor(editor);
        editor.Loaded += (_, _) => CenterNativeTextLine();
        editor.Unloaded += (_, _) => editorViewport = null;
        surface.Child = body;
        Content = surface;
        editor.GotFocus += (_, _) =>
        {
            focused = true;
            Refresh();
        };
        editor.LostFocus += (_, _) =>
        {
            focused = false;
            Refresh();
        };
        surface.PointerPressed += (_, _) => { if (IsEnabled && editor.IsEnabled) editor.Focus(FocusState.Pointer); };
        RegisterPropertyChangedCallback(IsEnabledProperty, (_, _) =>
        {
            editor.IsEnabled = IsEnabled;
            Refresh();
        });
        ApplyScale(1);
        Refresh();
    }

    internal void SetPrefix(
        bool value
    )
    {
        if (showPrefix == value)
            return;
        showPrefix = value;
        ApplyScale(scale);
    }

    internal void SetInvalid(
        string? value
    )
    {
        if (invalidMessage == value)
            return;
        invalidMessage = value;
        ToolTipService.SetToolTip(this, value);
        AutomationProperties.SetHelpText(editor, value ?? "");
        Refresh();
    }

    internal void SetAccessoryWidth(
        double width
    )
    {
        actionColumn.Width = new(width + 24 * scale);
    }

    internal void ApplyScale(
        double value
    )
    {
        scale = value;
        Height = 54 * scale;
        surface.CornerRadius = new(12 * scale);
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
        if (editor.IsLoaded)
            CenterNativeTextLine();
    }

    private void CenterNativeTextLine()
    {
        CenterNativeTextLine(editor, ref editorViewport);
    }

    internal object TextLineMetrics()
    {
        var views = new List<object>();
        void Visit(
            DependencyObject parent
        )
        {
            for (int i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
            {
                var child = VisualTreeHelper.GetChild(parent, i);
                if (child is FrameworkElement element && (element.Name is "ContentElement" or "PlaceholderTextContentPresenter" || element.GetType().Name.Contains("TextBoxView")))
                    views.Add(new
                    {
                        element.Name,
                        type = element.GetType().Name,
                        y = element.TransformToVisual(editor).TransformPoint(new()).Y,
                        height = element.ActualHeight,
                        baseline = (element as TextBlock)?.BaselineOffset,
                        element.Margin,
                        padding = (element as TextBlock)?.Padding
                    });
                Visit(child);
            }
        }
        Visit(editor);
        return new
        {
            height = editor.ActualHeight,
            editor.Padding,
            views
        };
    }

    private static void CenterNativeTextLine(
        Control control,
        ref ScrollViewer? viewport
    )
    {
        // The default template stretches the editing viewport to the clear-button row.
        // Center both the viewport and its measured text view so typed text and caret share the prefix line.
        static ScrollViewer? FindContent(
            DependencyObject root
        )
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
                if (child is ScrollViewer { Name: "ContentElement" } content)
                    result = content;
                if (FindContent(child) is { } nested)
                    result ??= nested;
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
        LoginMotion.Color(
            this,
            outline,
            invalidMessage is not null ? "#DC2626" : focused ? "#828FF0" : "#E5E7EB"
        );
        surface.BorderThickness = new(focused || invalidMessage is not null ? 1.5 : 1);
        LoginMotion.Opacity(this, IsEnabled ? 1 : .55);
    }

    private static void ConfigureEditor(
        Control editor
    )
    {
        editor.Background = Theme.Brush("#00FFFFFF");
        editor.BorderBrush = Theme.Brush("#00FFFFFF");
        editor.BorderThickness = new(0);
        editor.Padding = new(0);
        editor.MinHeight = editor.MinWidth = 0;
        editor.FontFamily = LoginTypography.Font;
        editor.FontWeight = Microsoft.UI.Text.FontWeights.Normal;
        editor.Foreground = Theme.Brush("#111318");
        editor.VerticalContentAlignment = VerticalAlignment.Center;
        editor.HorizontalAlignment = HorizontalAlignment.Stretch;
        editor.VerticalAlignment = VerticalAlignment.Center;
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
        if (editor is TextBox text)
        {
            text.IsSpellCheckEnabled = false;
            text.IsTextPredictionEnabled = false;
        }
        if (editor is PasswordBox password)
            password.PasswordRevealMode = PasswordRevealMode.Hidden;
    }
}
