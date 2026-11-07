//
//  MainWindow.Verification.Presets.cs
//  FaceNow
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/FaceNow-Windows
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

using FaceNow.Windows.Studio.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private async Task VerifyReferenceModesAsync()
    {
        Check(Model.IsPreview && Model.Session is null, "Preset verification requires isolated UI preview.");
        await Model.StartLandingAsync(); await Task.Delay(500); root.UpdateLayout();
        Check(tabs.Keys.SequenceEqual(new[] { "charx", "clothx", "vibex", "dimx", "free" }), "Generation modes must appear in the configured tab order.");
        foreach (var (mode, items) in new[] { ("charx", Model.CharacterReferences), ("clothx", Model.ClothingReferences),
                     ("vibex", Model.StyleReferences), ("dimx", Model.SummonReferences) })
        {
            var peer = FrameworkElementAutomationPeer.CreatePeerForElement(tabs[mode])!;
            ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => items.All(item => item.IsUpload || item.IsPromptOnly || item.Thumbnail is not null || item.HasError), 60);
            Check(items.All(item => !item.HasError), "Reference thumbnails failed: " + string.Join("; ", items.Where(item => item.HasError).Select(item => item.Name + ": " + item.Error)));
            Check(referenceScrollers[mode].Visibility == Visibility.Visible, "The selected mode did not show its own list.");
            foreach (var item in items.Where(item => item.IsPromptOnly))
            {
                await ClickReferenceAsync(item);
                Check(item.Thumbnail is null && !item.IsLoading && !item.HasError, "A prompt-only preset tried to load an image.");
                Check(Model.ReferenceContext(item).ReferencePath is null, "A prompt-only preset retained an image condition.");
            }
            await ClickReferenceAsync(items.First(item => !item.IsUpload && !item.IsPromptOnly));
            await SaveScreenshotAsync("presets-" + mode);
        }
        Model.SelectedMode = "dimx";
        ResizeWindow(1180, 800); await Task.Delay(250); root.UpdateLayout();
        Check(tabs.Values.All(tab => tab.ActualWidth > 0 && tab.TransformToVisual(root).TransformPoint(new()).X + tab.ActualWidth <= root.ActualWidth),
            "The five mode tabs do not fit the minimum window.");
        await SaveScreenshotAsync("presets-dimx-minimum");
        Model.Prompt = "User-owned free prompt / 用户自己填写"; Model.SelectedMode = "free";
        await Model.SubmitPromptAsync();
        Check(Model.Prompt == "User-owned free prompt / 用户自己填写" && Model.Session is null && Model.Cameras.Count == 0,
            "Preset verification changed free text or started capture/generation.");
    }
}
