using FaceNow.Core.Media;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using FaceNow.App.User;

namespace FaceNow.App.Controls;

internal sealed class BeautyPanel : UserControl
{
    private readonly Slider[] sliders = new Slider[4];
    private readonly TextBlock[] values = new TextBlock[4];
    private bool updating;
    private BeautySettings current = new();
    internal Action<BeautySettings>? SettingsChanged;
    internal BeautyPanel()
    {
        Width = 248;
        var surface = new Border { Padding = new(10), CornerRadius = new(8), Background = Theme.Brush("#CC000000"), BorderBrush = Theme.Brush("#22FFFFFF"), BorderThickness = new(1) };
        var stack = new StackPanel { Spacing = 2 };
        string[] labels = ["Smoothness", "Lightening", "Sharpness", "Redness"];
        for (int i = 0; i < 4; ++i)
        {
            int index = i; var row = new Grid { Height = 30, ColumnSpacing = 6 };
            row.ColumnDefinitions.Add(new() { Width = new(74) }); row.ColumnDefinitions.Add(new()); row.ColumnDefinitions.Add(new() { Width = new(34) });
            var title = Theme.Text(labels[i], 11, "#E6FFFFFF"); title.FontFamily = new("Segoe UI"); row.Children.Add(title);
            var slider = new Slider { Minimum = 0, Maximum = 100, StepFrequency = 1, VerticalAlignment = VerticalAlignment.Center, MinWidth = 0, RequestedTheme = ElementTheme.Dark };
            sliders[i] = slider; Grid.SetColumn(slider, 1); row.Children.Add(slider);
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(slider, AppText.Get(labels[i]));
            var value = Theme.Text("0%", 11, "#E6FFFFFF"); value.FontFamily = new("Segoe UI"); value.TextAlignment = TextAlignment.Right;
            values[i] = value; Grid.SetColumn(value, 2); row.Children.Add(value);
            slider.ValueChanged += (_, _) =>
            {
                if (updating) return;
                float strength = (float)slider.Value / 100;
                current = index switch { 0 => current with { Smoothness = strength }, 1 => current with { Lightening = strength }, 2 => current with { Sharpness = strength }, _ => current with { Redness = strength } };
                values[index].Text = ((int)slider.Value) + "%"; SettingsChanged?.Invoke(current);
            };
            stack.Children.Add(row);
        }
        surface.Child = stack; Content = surface;
        Visibility = Visibility.Collapsed; LoginMotion.Opacity(this, 0);
    }
    internal void Update(BeautySettings value)
    {
        current = value; updating = true;
        float[] strengths = [value.Smoothness, value.Lightening, value.Sharpness, value.Redness];
        for (int i = 0; i < 4; ++i) { sliders[i].Value = strengths[i] * 100; values[i].Text = (int)Math.Round(strengths[i] * 100) + "%"; }
        updating = false;
    }
}
