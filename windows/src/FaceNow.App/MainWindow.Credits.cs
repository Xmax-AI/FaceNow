//
//  MainWindow.Credits.cs
//  FaceNow
//

using FaceNow.App.User;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private void ShowCreditsWarning()
    {
        if (closing || closed || accountRepository?.HasInsufficientCredits != true)
            return;
        var card = new CreditsWarningCard(() =>
        {
            ClosePopups();
            OpenLink("https://platform.xmaxai.com/credits");
        });
        OpenPopup(Model.Active ? sessionCredits : homeCredits, card, 280, 15);
    }
}
