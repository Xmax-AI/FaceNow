//
//  MainViewModel.Effects.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using FaceNow.Core.Media;
using FaceNow.Windows.Media;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed partial class MainViewModel
{
    private readonly GenerationEffectsController effects = new();
    public BeautySettings Beauty => effects.Settings;
    public bool BeautyApplying => effects.IsApplying && Active;
    public void SetBeauty(BeautySettings value) => effects.Update(value);
    private void EffectsChanged() => dispatcher.InvokeAsync(() => { Changed(nameof(Beauty)); Changed(nameof(BeautyApplying)); });
}
