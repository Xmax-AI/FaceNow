using FaceNow.App.Controls;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private const string SignedInMessage = "Signed in successfully";
    private bool signInToastVisible;
    private string? displayedToastError;

    private void UpdateToast()
    {
        if (closing || closed) return;
        string? error = string.IsNullOrEmpty(Model.Error) ? null : Model.Error;
        bool changed = error != displayedToastError;
        displayedToastError = error;
        if (changed && error is not null) signInToastVisible = false;
        toast.Update(signInToastVisible ? SignedInMessage : error,
            signInToastVisible ? ToastStyle.Success : ToastStyle.Error, announce: changed && error is not null);
    }

    private void ShowSignInToast()
    {
        if (closing || closed || accountRepository?.HasVerifiedSession != true) return;
        RefreshAccountUi();
        signInToastVisible = true;
        toast.Update(SignedInMessage, ToastStyle.Success, announce: true);
    }

    private void DismissSignInToast()
    {
        if (!signInToastVisible) return;
        signInToastVisible = false; UpdateToast();
    }

    private void ToastDismissed()
    {
        if (signInToastVisible) DismissSignInToast();
        else Model.ClearError();
    }
}
