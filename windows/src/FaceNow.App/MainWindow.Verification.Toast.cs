//
//  MainWindow.Verification.Toast.cs
//  FaceNow
//

using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Windows.Foundation;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private async Task VerifySignInToastAsync()
    {
        Check(signInToastVisible && toast.Message == SignedInMessage && toast.NotificationStyle == ToastStyle.Success,
            "Explicit successful login did not show its success notification.");
        await Task.Delay(450);
        root.UpdateLayout();
        var origin = toast.TransformToVisual(root).TransformPoint(new Point());
        Check(Math.Abs(origin.Y - 32) < 1 && Math.Abs(origin.X + toast.ActualWidth / 2 - root.ActualWidth / 2) < 1,
            "Toast is not centered 32 points below the content top.");
        Check(toast.ActualWidth <= 560 && Math.Abs(toast.ActualHeight - 48) < 1,
            $"The compact success toast has incorrect dimensions: {toast.ActualWidth} x {toast.ActualHeight}.");
        await SaveScreenshotAsync("toast-signed-in");
        await SaveScreenshotAsync("toast-signed-in-detail", toast, 2);

        // Background profile/credit refreshes must neither repeat success nor extend its four-second interval.
        for (int i = 0; i < 5; i++)
        {
            await Task.Delay(450);
            RefreshUi();
            await accountRepository!.RefreshCreditsAsync();
        }
        await UntilAsync(() => toast.Message is null && !signInToastVisible, 3);
        await accountRepository!.RestoreAsync();
        RefreshUi();
        Check(
            toast.Message is null,
            "Restoring a saved account repeated the interactive sign-in notification."
        );

        const string longError = "Unable to connect. Check your connection and try again. If the connection remains unavailable, return to the account menu and try again later.";
        Model.ReportError(new InvalidOperationException(longError));
        Check(
            toast.NotificationStyle == ToastStyle.Error && !signInToastVisible,
            "Errors did not use the shared error toast."
        );
        foreach (var (width, height, name) in new[] { (1180, 800, "minimum"), (1360, 890, "default"), (1920, 1080, "wide") })
        {
            ResizeWindow(width, height);
            await Task.Delay(200);
            root.UpdateLayout();
            Check(
                toast.ActualWidth <= 560 && toast.ActualHeight >= 48,
                "Wrapped toast exceeded its size bounds."
            );
            await SaveScreenshotAsync("toast-error-" + name, toast, 2);
        }
        ShowSignInToast();
        Check(toast.NotificationStyle == ToastStyle.Success, "Success did not replace a previous error.");
        toast.Dismiss();
        Check(
            toast.Message == longError && toast.NotificationStyle == ToastStyle.Error,
            "Dismissing success lost the existing error."
        );
        await UntilAsync(() => Model.Error.Length == 0 && toast.Message is null, 6);

        await Task.Delay(100);
        ShowSignInToast();
        await Task.Delay(450);
        Check(toast.Visibility == Visibility.Visible && toast.Message == SignedInMessage,
            "An interrupted dismissal hid a newer notification.");
        Model.ReportError(new InvalidOperationException("A new error takes priority."));
        Check(
            !signInToastVisible && toast.NotificationStyle == ToastStyle.Error,
            "A new error failed to replace success."
        );
        Model.ClearError();
        await UntilAsync(() => toast.Visibility == Visibility.Collapsed, 2);
        ResizeWindow(1360, 890);
    }
}
