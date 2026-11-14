//
//  MainWindow.About.cs
//  FaceNow
//

using FaceNow.App.Home;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private static string PublicAppVersion => typeof(App).Assembly.GetName().Version?.ToString(3) ?? "1.2.0";

    private void ShowAbout()
    {
        if (modalView is not null || closing || Model.Active || Model.Busy)
            return;
        ShowModal(new AboutView { Contact = () => OpenLink("mailto:contact@xmaxai.com") });
    }
}
