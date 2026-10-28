//
//  GenerationMode.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Uses the same generation modes and preset reference assets as Web X-Lab.
enum GenerationMode: String, CaseIterable, Identifiable, Sendable {

    /// Replaces the live character using a selected reference image.
    case charx

    /// Applies virtual clothing and requests face restoration.
    case clothx

    /// Applies the visual style of a reference image.
    case vibex

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
        case .free: GenerationStrings.modeFreePrompt
        }
    }

    /// The default generation prompt, or a per-reference override when present.
    var prompt: String {
        switch self {
        case .charx: "视频中角色替换成参考图中角色"
        case .clothx: "视频中人物衣服替换成参考图中衣服"
        case .vibex: "视频风格变为参考图指定的风格"
        case .free: ""
        }
    }

    /// Whether the selected mode requests the clothing workflow's face restoration.
    var faceRestoration: Bool { self == .clothx }

    /// The built-in versioned references offered for this mode.
    var presets: [GenerationReference] {
        switch self {
        case .charx:
            [
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetClassicalGirl,
                    image: "removed-preset-1.png",
                    reference: "charx_real_image1.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetClassicalBoy,
                    image: "charx_image2.jpeg",
                    reference: "charx_real_image2.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetModernGirl,
                    image: "charx_image3.png",
                    reference: "charx_real_image3.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetModernBoy,
                    image: "charx_image4.png",
                    reference: "charx_real_image4.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetBlondeGirl,
                    image: "charx_image5.png",
                    reference: "charx_real_image5.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetCurlyHairedBoy,
                    image: "charx_image6.png",
                    reference: "charx_real_image6.jpeg"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetAnimeBoy,
                    image: "charx_image7.png",
                    reference: "charx_real_image7.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetAnimeGirl,
                    image: "charx_image8.png",
                    reference: "charx_real_image8.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.removedLegacyPreset,
                    image: "removed-preset-6.png",
                    reference: "removed-legacy-preset.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetBronzeFigure,
                    image: "removed-preset-2.png",
                    reference: "charx_real_image10.jpeg"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.removedLegacyPreset,
                    image: "removed-preset-3.png",
                    reference: "removed-legacy-preset.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.removedLegacyPreset,
                    image: "removed-legacy-preset.png",
                    reference: "removed-preset-7.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.preset3DKangaroo,
                    image: "charx_image13.jpg",
                    reference: "charx_real_image13.jpeg"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetMechaGirl,
                    image: "charx_image14.png",
                    reference: "charx_real_image14.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.removedLegacyPreset,
                    image: "removed-legacy-preset.png",
                    reference: "removed-preset-8.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetSpecialOps,
                    image: "charx_image16.jpeg",
                    reference: "charx_real_image16.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetHumanoidRobot,
                    image: "charx_image17.png",
                    reference: "charx_real_image17.jpg"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetChillCapybara,
                    image: "charx_image18.jpeg",
                    reference: "charx_real_image18.jpg"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetGentlePanda,
                    image: "charx_image19.png",
                    reference: "charx_real_image19.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetCuteHamster,
                    image: "charx_image20.png",
                    reference: "charx_real_image20.jpg"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetIllustratedGirl,
                    image: "charx_image21.png",
                    reference: "charx_real_image21.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetCartoonBoy,
                    image: "charx_image22.jpeg",
                    reference: "charx_real_image22.jpeg"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.removedLegacyPreset,
                    image: "removed-legacy-preset.png",
                    reference: "removed-legacy-preset.png"
                ),
                .preset(
                    .charx,
                    version: "20260909",
                    name: GenerationStrings.presetCorporateCow,
                    image: "charx_image24.jpeg",
                    reference: "charx_real_image24.jpeg"
                ),
            ]
        case .clothx:
            [
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetGildedGoddess,
                    image: "clothx_image1.png",
                    reference: "clothx_real_image1.jpg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetMonochromeVanguard,
                    image: "clothx_image2.png",
                    reference: "clothx_real_image2.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetSilverFantasyRobe,
                    image: "clothx_image3.png",
                    reference: "clothx_real_image3.jpeg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetNavySailorOutfit,
                    image: "clothx_image4.png",
                    reference: "clothx_real_image4.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetLongCoatSet,
                    image: "clothx_image5.png",
                    reference: "clothx_real_image5.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetPinkAcademy,
                    image: "clothx_image6.png",
                    reference: "clothx_real_image6.jpeg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetBronzeWarriorArmor,
                    image: "clothx_image7.png",
                    reference: "clothx_real_image7.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetVintageBrown,
                    image: "clothx_image8.png",
                    reference: "clothx_real_image8.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetBlackCollarAcademy,
                    image: "clothx_image9.png",
                    reference: "clothx_real_image9.jpeg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetBluePlaidAcademy,
                    image: "clothx_image10.png",
                    reference: "clothx_real_image10.jpeg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetBlackPinafore,
                    image: "clothx_image11.png",
                    reference: "clothx_real_image11.jpeg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetCoffeeCardigan,
                    image: "clothx_image12.png",
                    reference: "clothx_real_image12.jpeg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetLilacSlipDress,
                    image: "clothx_image13.png",
                    reference: "clothx_real_image13.jpeg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetMagentaTechwear,
                    image: "clothx_image14.png",
                    reference: "clothx_real_image14.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetLuxurySuit,
                    image: "clothx_image15.png",
                    reference: "clothx_real_image15.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetNavyOfficewear,
                    image: "clothx_image16.png",
                    reference: "clothx_real_image16.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetBurgundyStripes,
                    image: "clothx_image17.png",
                    reference: "clothx_real_image17.jpeg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetLightBlueSportswear,
                    image: "clothx_image18.png",
                    reference: "clothx_real_image18.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetSilverCasualwear,
                    image: "clothx_image19.png",
                    reference: "clothx_real_image19.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetBritishBrownPlaid,
                    image: "clothx_image20.png",
                    reference: "clothx_real_image20.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetBlueAndWhiteRetro,
                    image: "clothx_image21.png",
                    reference: "clothx_real_image21.jpeg"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetAllDenimOutfit,
                    image: "clothx_image22.png",
                    reference: "clothx_real_image22.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetGrayEveningwear,
                    image: "clothx_image23.png",
                    reference: "clothx_real_image23.png"
                ),
                .preset(
                    .clothx,
                    version: "20260909",
                    name: GenerationStrings.presetBlackClassicalRobe,
                    image: "clothx_image24.png",
                    reference: "clothx_real_image24.png"
                ),
            ]
        case .vibex:
            [
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetAmericanCartoon,
                    image: "vibex_image1.jpg",
                    reference: "vibex_real_image1.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.preset3DCartoon,
                    image: "vibex_image2.jpg",
                    reference: "vibex_real_image2.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetSchoolAnime,
                    image: "vibex_image3.jpg",
                    reference: "vibex_real_image3.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetUrbanAnime,
                    image: "vibex_image4.jpg",
                    reference: "vibex_real_image4.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetJapaneseAnime,
                    image: "vibex_image5.jpg",
                    reference: "vibex_real_image5.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetRealisticAnimals,
                    image: "vibex_image9.png",
                    reference: "vibex_real_image9.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetDesignerToy,
                    image: "vibex_image10.png",
                    reference: "vibex_real_image10.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetAnthropomorphic,
                    image: "vibex_image15.jpeg",
                    reference: "vibex_real_image15.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetSurrealism,
                    image: "vibex_image17.png",
                    reference: "vibex_real_image17.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetDisneyStyle,
                    image: "vibex_image18.png",
                    reference: "vibex_real_image18.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetCelShading,
                    image: "vibex_image19.png",
                    reference: "vibex_real_image19.png"
                ),
                .preset(
                    .vibex,
                    version: "20260911",
                    name: GenerationStrings.presetJapaneseAnimation,
                    image: "vibex_image21.png",
                    reference: "vibex_real_image21.png"
                ),
            ]
        case .free: []
        }
    }
}
