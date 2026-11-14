//
//  GenerationMode.swift
//  FaceNow
//

import Foundation

/// Uses the same generation modes and preset reference assets as Web X-Lab.
enum GenerationMode: String, CaseIterable, Identifiable, Sendable {

    /// Replaces the live character using a selected reference image.
    case charx

    /// Applies virtual clothing using the selected reference configuration.
    case clothx

    /// Applies the visual style of a reference image.
    case vibex

    /// Adds a summoned subject while preserving the existing video subjects.
    case dimx

    /// Uses the user's free-form prompt and optional uploaded reference.
    case free

    /// The identity used to associate this value with its displayed or pending state.
    var id: String { rawValue }

    /// The mode name displayed by the generation tabs.
    var title: String {
        switch self {
        case .charx: GenerationStrings.modeCharacterSwap
        case .clothx: GenerationStrings.modeVirtualTryOn
        case .vibex: GenerationStrings.modeStyleTransfer
        case .dimx: GenerationStrings.modeSummon
        case .free: GenerationStrings.modeFreePrompt
        }
    }

    /// The default Chinese prompt for style transfer.
    private static let vibexChinesePrompt = "参考图角色重现视频动作，角色全部外观细节保留，保留并使用参考图的背景"

    /// The default English prompt for style transfer.
    private static let vibexEnglishPrompt =
        "The character from the reference image recreates the actions in the video. "
        + "Preserve all appearance details of the reference character exactly, "
        + "and keep the original background from the reference image unchanged."

    /// The Chinese style presets include the final punctuation used in the Web catalog.
    private static let vibexPresetPrompt = regionalPrompt(
        chinese: vibexChinesePrompt + "。",
        english: vibexEnglishPrompt
    )

    /// The regional default prompt used when an uploaded reference has no preset override.
    var prompt: String {
        switch self {
        case .charx:
            Self.regionalPrompt(
                chinese: "视频中人物替换成参考图中角色",
                english: "Become the character in the reference image"
            )
        case .clothx:
            Self.regionalPrompt(
                chinese: "视频中人物衣服替换成参考图中衣服",
                english:
                    "Keep the character and background unchanged, only replace clothing with the reference‑image outfit."
            )
        case .vibex:
            Self.regionalPrompt(
                chinese: Self.vibexChinesePrompt,
                english: Self.vibexEnglishPrompt
            )
        case .dimx:
            Self.regionalPrompt(
                chinese: "召唤新增任务：保留原视频中已有的主体，额外加入参考图中的主体，不替换任何原有主体。把参考图角色召唤到视频人物的肩膀上或者手上",
                english:
                    "Summon / Add a Subject: Keep all existing subjects in the original video. Add the subject from the reference image without replacing any existing subject. Summon the reference character onto the shoulder or hand of the person in the video."
            )
        case .free: ""
        }
    }

    /// Uses FaceNow's selection of X2.1 Playground references in workbook order.
    var presets: [GenerationReference] {
        switch self {
        case .charx:
            [
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxCandyGirl,
                    reference: "charx_image21.png",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxCuteGirl,
                    reference: "charx_image2.jpeg",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxSuitedGuy,
                    reference: "charx_image22.png",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxShortHairedCoolGirl,
                    reference: "charx_image23.jpeg",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxDreamyGirl,
                    reference: "charx_image24.png",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxAnimeGirl,
                    reference: "charx_image25.jpeg",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxCorporateCow,
                    reference: "charx_image13.jpeg",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxMechaGirl,
                    reference: "charx_image14.png",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxHumanoidRobot,
                    reference: "charx_image16.png",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxSpecialOps,
                    reference: "charx_real_image17.jpeg",
                    prompt: prompt
                ),
                .preset(
                    .charx,
                    version: "20261030",
                    name: GenerationStrings.presetCharxCuteHamster,
                    reference: "charx_image18.png",
                    prompt: prompt
                ),
            ]
        case .clothx:
            [
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxPinkAcademy,
                    reference: "clothx_image1.png",
                    prompt: Self.regionalPrompt(
                        chinese: "视频中人物衣服替换成参考图中衣服",
                        english:
                            "Keep the character and background unchanged, only replace clothing with the reference‑image outfit."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxBlackCollarAcademy,
                    reference: "clothx_image2.png",
                    prompt: Self.regionalPrompt(
                        chinese: "视频中人物衣服替换成参考图中衣服",
                        english:
                            "Keep the character and background unchanged, only replace clothing with the reference‑image outfit."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxMonochromeVanguard,
                    reference: "clothx_real_image3.png",
                    prompt: Self.regionalPrompt(
                        chinese: "视频中人物衣服替换成参考图中衣服",
                        english:
                            "Keep the character and background unchanged, only replace clothing with the reference‑image outfit."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxVintageBrown,
                    reference: "clothx_real_image4.png",
                    prompt: Self.regionalPrompt(
                        chinese: "视频中人物衣服替换成参考图中衣服",
                        english:
                            "Keep the character and background unchanged, only replace clothing with the reference‑image outfit."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxSilverFantasyRobe,
                    reference: "clothx_image5.png",
                    prompt: Self.regionalPrompt(
                        chinese: "视频中人物衣服替换成参考图中衣服",
                        english:
                            "Keep the character and background unchanged, only replace clothing with the reference‑image outfit."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxTopReplacement,
                    reference: "clothx_image6.png",
                    prompt: Self.regionalPrompt(
                        chinese: "将参考图的上衣穿到视频人物身上，其他保持不变",
                        english:
                            "Keep the character and background unchanged, only replace the upper-body clothes with the reference‑image outfit."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxTopReplacement2,
                    reference: "clothx_image7.png",
                    prompt: Self.regionalPrompt(
                        chinese: "将参考图的上衣穿到视频人物身上，其他保持不变",
                        english:
                            "Keep the character and background unchanged, only replace the upper-body clothes with the reference‑image outfit."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxBottomsReplacement2,
                    reference: "clothx_image8.png",
                    prompt: Self.regionalPrompt(
                        chinese: "将参考图的下装穿到视频人物身上，其他保持不变",
                        english:
                            "Put the bottoms from the reference image on the video character. Keep everything else unchanged."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxBottomsReplacement,
                    reference: "clothx_real_image9.png",
                    prompt: Self.regionalPrompt(
                        chinese: "将参考图的下装穿到视频人物身上，其他保持不变",
                        english:
                            "Put the bottoms from the reference image on the video character. Keep everything else unchanged."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxNavySailorOutfit,
                    reference: "clothx_real_image10.png",
                    prompt: Self.regionalPrompt(
                        chinese: "视频中人物衣服替换成参考图中衣服",
                        english:
                            "Keep the character and background unchanged, only replace clothing with the reference‑image outfit."
                    ),
                    faceRestoration: true
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxBaseballCap,
                    reference: "clothx_image11.jpeg",
                    prompt: Self.regionalPrompt(
                        chinese: "将参考图棒球帽应用到视频角色身上",
                        english: "Apply the cap from the reference image to the video character."
                    ),
                    faceRestoration: false
                ),
                .preset(
                    .clothx,
                    version: "20261030",
                    name: GenerationStrings.presetClothxSunglasses,
                    reference: "clothx_image12.jpeg",
                    prompt: Self.regionalPrompt(
                        chinese: "将参考图眼镜应用到视频角色身上",
                        english: "Apply the glasses from the reference image to the video character."
                    ),
                    faceRestoration: false
                ),
            ]
        case .vibex:
            [
                .preset(
                    .vibex,
                    version: "20261030",
                    name: GenerationStrings.presetVibexAmericanCartoon,
                    reference: "vibex_real_image1.png",
                    prompt: Self.vibexPresetPrompt
                ),
                .preset(
                    .vibex,
                    version: "20261030",
                    name: GenerationStrings.presetVibexPhotorealisticPortrait,
                    reference: "vibex_real_image2.png",
                    prompt: Self.vibexPresetPrompt
                ),
                .preset(
                    .vibex,
                    version: "20261030",
                    name: GenerationStrings.presetVibexHellMeme,
                    reference: "vibex_real_image3.png",
                    prompt: Self.vibexPresetPrompt
                ),
                .preset(
                    .vibex,
                    version: "20261030",
                    name: GenerationStrings.presetVibexSentaiTokusatsu,
                    reference: "vibex_real_image4.png",
                    prompt: Self.vibexPresetPrompt
                ),
                .preset(
                    .vibex,
                    version: "20261030",
                    name: GenerationStrings.presetVibexRealisticAnimals,
                    reference: "vibex_real_image5.png",
                    prompt: Self.vibexPresetPrompt
                ),
                .preset(
                    .vibex,
                    version: "20261030",
                    name: GenerationStrings.presetVibex3dCartoon,
                    reference: "vibex_real_image6.png",
                    prompt: Self.vibexPresetPrompt
                ),
                .preset(
                    .vibex,
                    version: "20261030",
                    name: GenerationStrings.presetVibexDesignerToy,
                    reference: "vibex_real_image7.png",
                    prompt: Self.vibexPresetPrompt
                ),
                .preset(
                    .vibex,
                    version: "20261030",
                    name: GenerationStrings.presetVibexSurrealism,
                    reference: "vibex_real_image8.png",
                    prompt: Self.vibexPresetPrompt
                ),
            ]
        case .dimx:
            [
                .promptPreset(
                    .dimx,
                    id: "dimx-little-dog",
                    name: GenerationStrings.presetDimxLittleDog,
                    prompt: Self.regionalPrompt(
                        chinese: "召唤一只小狗到人的肩膀上",
                        english: "Summon a small dog onto the person's shoulder."
                    )
                ),
                .promptPreset(
                    .dimx,
                    id: "dimx-little-mouse",
                    name: GenerationStrings.presetDimxLittleMouse,
                    prompt: Self.regionalPrompt(
                        chinese: "召唤一只小老鼠到人物肩膀上",
                        english: "Summon a little mouse onto the person's shoulder."
                    )
                ),
                .preset(
                    .dimx,
                    version: "20261030",
                    name: GenerationStrings.presetDimxPenguinPlushie,
                    reference: "dimx_image3.png",
                    prompt: Self.regionalPrompt(
                        chinese: "召唤新增任务：保留原视频中已有的主体，额外加入参考图中的主体，不替换任何原有主体。把参考图的小动物召唤到视频人物的肩膀上",
                        english:
                            "Summon / Add a Subject: Keep all existing subjects in the original video. Add the subject from the reference image without replacing any existing subject. Summon the small animal from the reference image onto the shoulder of the person in the video."
                    )
                ),
                .preset(
                    .dimx,
                    version: "20261030",
                    name: GenerationStrings.presetDimxFluffyBunny,
                    reference: "dimx_image4.png",
                    prompt: Self.regionalPrompt(
                        chinese: "召唤新增任务：保留原视频中已有的主体，额外加入参考图中的主体，不替换任何原有主体。把参考图的小动物召唤到视频人物的肩膀上",
                        english:
                            "Summon / Add a Subject: Keep all existing subjects in the original video. Add the subject from the reference image without replacing any existing subject. Summon the small animal from the reference image onto the shoulder of the person in the video."
                    )
                ),
                .preset(
                    .dimx,
                    version: "20261030",
                    name: GenerationStrings.presetDimxCreamKitten,
                    reference: "dimx_image5.png",
                    prompt: Self.regionalPrompt(
                        chinese: "召唤新增任务：保留原视频中已有的主体，额外加入参考图中的主体，不替换任何原有主体。把参考图的小动物召唤到视频人物的肩膀上",
                        english:
                            "Summon / Add a Subject: Keep all existing subjects in the original video. Add the subject from the reference image without replacing any existing subject. Summon the small animal from the reference image onto the shoulder of the person in the video."
                    )
                ),
                .preset(
                    .dimx,
                    version: "20261030",
                    name: GenerationStrings.presetDimxCowPlushie,
                    reference: "dimx_image7.png",
                    prompt: Self.regionalPrompt(
                        chinese: "召唤新增任务：保留原视频中已有的主体，额外加入参考图中的主体，不替换任何原有主体。把参考图的小动物召唤到视频人物的肩膀上",
                        english:
                            "Summon / Add a Subject: Keep all existing subjects in the original video. Add the subject from the reference image without replacing any existing subject. Summon the small animal from the reference image onto the shoulder of the person in the video."
                    )
                ),
                .preset(
                    .dimx,
                    version: "20261030",
                    name: GenerationStrings.presetDimxHelloKitty,
                    reference: "dimx_image8.png",
                    prompt: Self.regionalPrompt(
                        chinese: "召唤新增任务：保留原视频中已有的主体，额外加入参考图中的主体，不替换任何原有主体。把参考图的小动物召唤到视频人物的肩膀上",
                        english:
                            "Summon / Add a Subject: Keep all existing subjects in the original video. Add the subject from the reference image without replacing any existing subject. Summon the small animal from the reference image onto the shoulder of the person in the video."
                    )
                ),
            ]
        case .free: []
        }
    }

    /// Mirrors Playground's regional built-in prompts; user-authored prompts bypass this selection.
    private static func regionalPrompt(
        chinese: String,
        english: String
    ) -> String {
        #if OVERSEA
            return english
        #else
            return chinese
        #endif
    }
}
