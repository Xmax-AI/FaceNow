//
//  GenerationPrompts.cs
//  FaceNow
//

namespace FaceNow.Core.Product;

/// <summary>Provides regional default prompts for the built-in generation modes.</summary>
public static class GenerationPrompts
{
    public static string ForMode(
        string mode,
        ProductProfile? profile = null
    ) => ((profile ?? ProductProfile.Current).IsOverseas, mode) switch
    {
        (true, "charx") => "Become the character in the reference image",
        (true, "clothx") => "Keep the character and background unchanged, only replace clothing with the reference‑image outfit.",
        (true, "vibex") => "The character from the reference image recreates the actions in the video. Preserve all appearance details of the reference character exactly, and keep the original background from the reference image unchanged.",
        (true, "dimx") => "Summon / Add a Subject: Keep all existing subjects in the original video. Add the subject from the reference image without replacing any existing subject. Summon the reference character onto the shoulder or hand of the person in the video.",
        (false, "charx") => "视频中人物替换成参考图中角色",
        (false, "clothx") => "视频中人物衣服替换成参考图中衣服",
        (false, "vibex") => "参考图角色重现视频动作，角色全部外观细节保留，保留并使用参考图的背景",
        (false, "dimx") => "召唤新增任务：保留原视频中已有的主体，额外加入参考图中的主体，不替换任何原有主体。把参考图角色召唤到视频人物的肩膀上或者手上",
        _ => ""
    };
}
