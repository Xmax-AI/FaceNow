//
//  MainWindow.Modal.cs
//  FaceNow
//

using FaceNow.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private ModalView? modalView;
    private Control? modalPreviousFocus;

    private void ShowModal(ModalView view)
    {
        ClosePopups();
        modalPreviousFocus = FocusManager.GetFocusedElement(root.XamlRoot) as Control;
        modalView = view;
        view.DismissRequested += async () => await CloseModalAsync(view);
        scroller.IsHitTestVisible = false;
        root.Children.Add(view);
    }

    private async Task<bool> CloseModalAsync(ModalView view)
    {
        if (modalView != view || view.IsDismissing)
            return false;
        bool dismissed = false;
        try
        {
            await view.SetPresentedAsync(false);
        }
        finally
        {
            if (modalView == view)
            {
                var previous = modalPreviousFocus;
                DisposeModal();
                dismissed = true;
                if (!closing && previous is { IsLoaded: true, IsEnabled: true })
                    previous.Focus(FocusState.Programmatic);
            }
        }
        return dismissed;
    }

    private void DisposeModal()
    {
        if (modalView is not { } view)
            return;
        modalView = null;
        modalPreviousFocus = null;
        view.Dispose();
        root.Children.Remove(view);
        scroller.IsHitTestVisible = true;
    }
}
