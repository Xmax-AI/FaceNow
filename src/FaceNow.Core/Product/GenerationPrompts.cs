namespace FaceNow.Core.Product;

/// <summary>Regional generation defaults match the macOS product; free text stays user owned.</summary>
public static class GenerationPrompts
{
    public static string ForMode(string mode, ProductProfile? profile = null) => ((profile ?? ProductProfile.Current).IsOverseas, mode) switch
    {
        (true, "charx") => "Become the character in the reference image",
        (true, "clothx") => "Keep the character and background unchanged, only replace clothing with the reference‑image outfit.",
        (true, "vibex") => "The reference character performs the motions from the video.",
        (false, "charx") => "视频中角色替换成参考图中角色",
        (false, "clothx") => "视频中人物衣服替换成参考图中衣服",
        (false, "vibex") => "参考图角色重现视频动作，角色全部外观细节保留，保留并使用参考图的背景",
        _ => ""
    };
}
