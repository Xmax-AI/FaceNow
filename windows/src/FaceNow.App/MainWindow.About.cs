//
//  MainWindow.About.cs
//  FaceNow
//

using FaceNow.App.Home;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private void ShowAbout()
    {
        if (modalView is not null || closing || Model.Active || Model.Busy)
            return;
        ShowModal(new AboutView { Contact = () => OpenLink("mailto:contact@xmaxai.com") });
    }
}
