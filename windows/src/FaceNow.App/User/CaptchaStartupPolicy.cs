//
//  CaptchaStartupPolicy.cs
//  FaceNow
//

namespace FaceNow.App.User;

internal enum CaptchaStartupIssue
{
    RuntimeMissing, ApplicationFilesMissing, AccessDenied, InUse, UnsupportedRuntime, Unknown
}

/// <summary>Interprets WebView2 startup failures independently of their COM or managed exception projection.</summary>
internal static class CaptchaStartupPolicy
{
    internal const string DownloadUrl = "https://developer.microsoft.com/microsoft-edge/webview2/#download";
    internal const string ApplicationFilesMessage = "The verification component is incomplete. Reinstall FaceNow and try again.";

    internal static CaptchaStartupIssue Classify(
        Exception error
    )
    {
        if (error is DllNotFoundException or BadImageFormatException)
            return CaptchaStartupIssue.ApplicationFilesMissing;
        return unchecked((uint)error.HResult) switch
        {
            0x80070002 or 0x80070645 => CaptchaStartupIssue.RuntimeMissing,
            0x80070005 or 0x80070050 or 0x800700B7 => CaptchaStartupIssue.AccessDenied,
            0x8007139F => CaptchaStartupIssue.InUse,
            0x80004002 or 0x80004001 => CaptchaStartupIssue.UnsupportedRuntime,
            _ => CaptchaStartupIssue.Unknown
        };
    }

    internal static string Message(
        CaptchaStartupIssue issue
    ) => issue switch
    {
        CaptchaStartupIssue.RuntimeMissing => "Install Microsoft Edge WebView2 Runtime to complete security verification.",
        CaptchaStartupIssue.ApplicationFilesMissing => ApplicationFilesMessage,
        CaptchaStartupIssue.AccessDenied => "Security verification cannot access its data folder. Check your Windows permissions or contact your administrator.",
        CaptchaStartupIssue.InUse => "Close other FaceNow windows, then try security verification again.",
        CaptchaStartupIssue.UnsupportedRuntime => "Update Microsoft Edge WebView2 Runtime, then restart FaceNow and try again.",
        _ => "Security verification could not be started. Restart FaceNow and try again."
    };
}
