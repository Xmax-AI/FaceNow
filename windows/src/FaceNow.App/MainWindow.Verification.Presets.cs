//
//  MainWindow.Verification.Presets.cs
//  FaceNow
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
        await Model.StartLandingAsync();
        await Task.Delay(500);
        root.UpdateLayout();
        Check(
            tabs.Keys.SequenceEqual(new[] { "charx", "clothx", "vibex", "dimx", "free" }),
            "Generation modes must appear in the configured tab order."
        );
        double toolbarTop = sessionControls.TransformToVisual(root).TransformPoint(default).Y;
        double videoTop = videoRow.TransformToVisual(root).TransformPoint(default).Y;
        double listHeight = referenceArea.ActualHeight;
        foreach (var (mode, items) in new[] { ("charx", Model.CharacterReferences), ("clothx", Model.ClothingReferences),
                     ("vibex", Model.StyleReferences), ("dimx", Model.SummonReferences) })
        {
            var peer = FrameworkElementAutomationPeer.CreatePeerForElement(tabs[mode])!;
            ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(
                () => Model.SelectedMode == mode && items.All(item => item.IsUpload || item.IsPromptOnly || item.Thumbnail is not null || item.HasError),
                60
            );
            Check(
                items.All(item => !item.HasError),
                "Reference thumbnails failed: " + string.Join(
                "; ",
                items.Where(item => item.HasError).Select(item => item.Name + ": " + item.Error)
            )
            );
            Check(
                referenceScrollers[mode].Visibility == Visibility.Visible,
                "The selected mode did not show its own list."
            );
            ArrangePage();
            root.UpdateLayout();
            Check(Math.Abs(sessionControls.TransformToVisual(root).TransformPoint(default).Y - toolbarTop) < 1 &&
                Math.Abs(videoRow.TransformToVisual(root).TransformPoint(default).Y - videoTop) < 1 &&
                Math.Abs(referenceArea.ActualHeight - listHeight) < 1,
                $"Switching to {mode} moved the session layout or resized the reference list.");
            foreach (var item in items.Where(item => item.IsPromptOnly))
            {
                await ClickReferenceAsync(item);
                Check(
                    item.Thumbnail is null && !item.IsLoading && !item.HasError,
                    "A prompt-only preset tried to load an image."
                );
                Check(
                    Model.ReferenceContext(item).ReferencePath is null,
                    "A prompt-only preset retained an image condition."
                );
            }
            await ClickReferenceAsync(items.First(item => !item.IsUpload && !item.IsPromptOnly));
            await SaveScreenshotAsync("presets-" + mode);
        }
        Model.SelectedMode = "dimx";
        ResizeWindow(1180, 800);
        await Task.Delay(250);
        root.UpdateLayout();
        Check(tabs.Values.All(tab => tab.ActualWidth > 0 && tab.TransformToVisual(root).TransformPoint(new()).X + tab.ActualWidth <= root.ActualWidth),
            "The five mode tabs do not fit the minimum window.");
        await SaveScreenshotAsync("presets-dimx-minimum");
        Model.Prompt = "User-owned free prompt / 用户自己填写";
        Model.SelectedMode = "free";
        await Model.SubmitPromptAsync();
        Check(Model.Prompt == "User-owned free prompt / 用户自己填写" && Model.Session is null && Model.Cameras.Count == 0,
            "Preset verification changed free text or started capture/generation.");

        Model.SelectedMode = "charx";
        var list = referenceScrollers["charx"];
        // Force the existing presets to wrap past the viewport even on wide displays.
        list.Width = 320;
        root.UpdateLayout();
        double pageOffset = scroller.VerticalOffset;
        Check(list.ScrollableHeight > 0, "Overflowing references must be scrollable.");
        list.ChangeView(null, list.ScrollableHeight, null, disableAnimation: true);
        await UntilAsync(() => list.VerticalOffset > 0 && Math.Abs(list.VerticalOffset - list.ScrollableHeight) < 1);
        Check(Math.Abs(scroller.VerticalOffset - pageOffset) < 1 && Math.Abs(referenceArea.ActualHeight - listHeight) < 1,
            "Scrolling references moved the outer page or resized the list.");
        list.ClearValue(FrameworkElement.WidthProperty);
    }
}
