//
//  LoginTypography.cs
//  FaceNow
//

using System.Runtime.CompilerServices;
using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace FaceNow.App.User;

/// <summary>
/// Provides the shared login font and aligns the phone country prefix with the editor.
/// </summary>
internal static class LoginTypography
{
    // The bundled variable font's name table declares "DM Sans 9pt"; "DM Sans" falls back to Segoe UI.
    internal static readonly FontFamily Font = new("ms-appx:///Assets/DMSans.ttf#DM Sans 9pt");

    internal static TextBlock Text(
        string text = "",
        double size = 13,
        string color = "#111318"
    )
    {
        var label = Theme.Text(text, size, color);
        label.FontFamily = Font;
        return label;
    }

    private static readonly ConditionalWeakTable<TextBlock, TranslateTransform> prefixOffsets = new();

    internal static void CenterCountryCode(
        TextBlock label
    )
    {
        if (prefixOffsets.TryGetValue(label, out _))
            return;
        var offset = new TranslateTransform();
        prefixOffsets.Add(label, offset);
        label.Padding = new(0);
        label.VerticalAlignment = VerticalAlignment.Center;
        label.RenderTransform = offset;
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
