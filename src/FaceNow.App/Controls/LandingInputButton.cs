//
//  LandingInputButton.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using FaceNow.App.User;
using Microsoft.UI.Text;

namespace FaceNow.App.Controls;

/// <summary>The translucent device selectors on the home canvas.</summary>
internal sealed class LandingInputButton : Pill
{
    internal LandingInputButton(string label)
    {
        FontFamily = LoginTypography.Font;
        FontSize = 13;
        FontWeight = FontWeights.Normal;
        Height = 32;
        MaxWidth = 280;
        LabelMaxWidth = 237;
        Padding = new(15, 0, 13, 0);
        ContentSpacing = 7;
        ExtraChevron = true;
        Translucent = true;
        Text = label;
    }
}
