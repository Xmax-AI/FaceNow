//
//  LoginMethodSelector.cs
//  FaceNow
//

using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App.User;

/// <summary>
/// Selects one of the available sign-in methods.
/// </summary>
internal sealed class LoginMethodSelector : UserControl
{
    private readonly Grid track = new() { Background = Theme.Brush("#F2F2F3") };
    private readonly Button[] buttons = new Button[3];
    private readonly TextBlock[] labels = new TextBlock[3];
    private readonly SolidColorBrush[] surfaces = new SolidColorBrush[3];
    private readonly SolidColorBrush[] foregrounds = new SolidColorBrush[3];
    private readonly LoginShadow[] shadows = new LoginShadow[3];
    private readonly bool[] available = [true, true, true];
    private readonly bool[] visible = [FaceNow.Core.Product.ProductProfile.Current.ShowsPhoneLogin, FaceNow.Core.Product.ProductProfile.Current.ShowsEmailLogin, true];
    private int selectedIndex, hoveredIndex = -1, pressedIndex = -1;

    internal event Action? SelectionChanged;

    internal int SelectedIndex
    {
        get => selectedIndex;
        set
        {
            if (value is < 0 or > 2 || !visible[value] || selectedIndex == value)
                return;
            selectedIndex = value;
            Refresh();
            SelectionChanged?.Invoke();
        }
    }

    internal LoginMethodSelector()
    {
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        selectedIndex = visible[0] ? 0 : 1;
        string[] titles = ["Phone", "Email", "API Key"];
        for (int i = 0; i < 3; i++)
        {
            int index = i, column = visible[i] ? track.ColumnDefinitions.Count : 0;
            if (visible[i])
                track.ColumnDefinitions.Add(new());
            foregrounds[i] = Theme.Brush("#6B7380");
            surfaces[i] = Theme.Brush("#F2F2F3");
            labels[i] = LoginTypography.Text(titles[i], 15);
            labels[i].FontWeight = Microsoft.UI.Text.FontWeights.Medium;
            labels[i].Foreground = foregrounds[i];
            labels[i].TextAlignment = TextAlignment.Center;
            var button = new Button
            {
                Template = Theme.ButtonTemplate,
                Background = surfaces[i],
                BorderThickness = new(0),
                Content = labels[i],
                Padding = new(0),
                MinWidth = 0,
                MinHeight = 0,
                UseSystemFocusVisuals = false,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Center,
                VerticalContentAlignment = VerticalAlignment.Center
            };
            AutomationProperties.SetName(button, AppText.Get(titles[i]));
            button.Visibility = visible[i] ? Visibility.Visible : Visibility.Collapsed;
            button.Click += (_, _) => { if (visible[index] && available[index]) SelectedIndex = index; };
            button.PointerEntered += (_, _) =>
            {
                hoveredIndex = index;
                Refresh();
            };
            button.PointerExited += (_, _) =>
            {
                if (hoveredIndex == index)
                    hoveredIndex = -1;
                pressedIndex = -1;
                Refresh();
            };
            button.PointerPressed += (_, _) =>
            {
                pressedIndex = index;
                Refresh();
            };
            button.PointerReleased += (_, _) =>
            {
                pressedIndex = -1;
                Refresh();
            };
            button.KeyDown += (_, args) =>
            {
                if (args.Key is not (global::Windows.System.VirtualKey.Left or global::Windows.System.VirtualKey.Right))
                    return;
                int step = args.Key == global::Windows.System.VirtualKey.Left ? -1 : 1;
                for (int next = index + step; next is >= 0 and < 3; next += step)
                    if (visible[next] && available[next])
                    {
                        SelectedIndex = next;
                        buttons[next].Focus(FocusState.Keyboard);
                        break;
                    }
                args.Handled = true;
            };
            var shadowHost = new Grid { IsHitTestVisible = false, Visibility = button.Visibility };
            shadows[i] = new(
                shadowHost,
                () => (float)button.CornerRadius.TopLeft,
                Microsoft.UI.Colors.Black,
                4,
                2,
                i == selectedIndex ? .1f : 0
            );
            Grid.SetColumn(shadowHost, column);
            track.Children.Add(shadowHost);
            buttons[i] = button;
            Grid.SetColumn(button, column);
            track.Children.Add(button);
            button.GotFocus += (_, _) =>
            {
                button.BorderThickness = new(button.FocusState == FocusState.Keyboard ? 1 : 0);
                button.BorderBrush = Theme.Brush("#828FF0");
            };
            button.LostFocus += (_, _) => button.BorderThickness = new(0);
        }
        Content = track;
        RegisterPropertyChangedCallback(IsEnabledProperty, (_, _) => Refresh());
        ApplyScale(1);
        Refresh();
    }

    internal void SetAvailability(
        bool phone,
        bool email
    )
    {
        available[0] = phone;
        available[1] = email;
        Refresh();
    }

    internal void ApplyScale(
        double scale
    )
    {
        Height = 52 * scale;
        track.CornerRadius = new(26 * scale);
        track.Padding = new(4 * scale);
        track.ColumnSpacing = 2 * scale;
        for (int i = 0; i < 3; i++)
        {
            buttons[i].CornerRadius = new(22 * scale);
            labels[i].FontSize = 15 * scale;
        }
    }

    private void Refresh()
    {
        for (int i = 0; i < 3; i++)
        {
            bool selected = i == selectedIndex, enabled = IsEnabled && visible[i] && available[i], hot = enabled && i == hoveredIndex;
            buttons[i].IsEnabled = enabled;
            LoginMotion.Color(
                this,
                surfaces[i],
                i == pressedIndex && enabled ? selected ? "#FAFAFA" : "#F0F0F0" : selected ? "#FFFFFF" : hot ? "#FBFBFB" : "#F2F2F3"
            );
            LoginMotion.Color(this, foregrounds[i], selected || hot ? "#111318" : "#6B7380");
            LoginMotion.Opacity(buttons[i], enabled ? 1 : .5);
            shadows[i].SetOpacity(selected ? .1f : 0);
            AutomationProperties.SetItemStatus(buttons[i], selected ? "Selected" : "");
        }
    }
}
