//
//  GenerationStrings.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
#if canImport(Localization)
    import Localization
#endif

/// Provides module-owned English defaults and stable localization keys for page presentation.
enum GenerationStrings {

    /// Closes the result overlay without changing the active beauty effect.
    static var beautyClose: String {
        Localization.string(
            "beauty.close",
            table: "Generation",
            defaultValue: "Close beauty controls"
        )
    }

    /// Result beauty control or recoverable effect status.
    static var beauty: String {
        Localization.string(
            "controls.beauty",
            table: "Generation",
            defaultValue: "Beauty"
        )
    }

    /// Result beauty control or recoverable effect status.
    static var beautyDescription: String {
        Localization.string(
            "beauty.description",
            table: "Generation",
            defaultValue: "Applies to generated results"
        )
    }

    /// Result beauty control or recoverable effect status.
    static var beautySmoothness: String {
        Localization.string(
            "beauty.smoothness",
            table: "Generation",
            defaultValue: "Smoothing"
        )
    }

    /// Result beauty control or recoverable effect status.
    static var beautyLightening: String {
        Localization.string(
            "beauty.lightening",
            table: "Generation",
            defaultValue: "Brightening"
        )
    }

    /// Result beauty control or recoverable effect status.
    static var beautySharpness: String {
        Localization.string(
            "beauty.sharpness",
            table: "Generation",
            defaultValue: "Sharpening"
        )
    }

    /// Result beauty control or recoverable effect status.
    static var beautyRedness: String {
        Localization.string(
            "beauty.redness",
            table: "Generation",
            defaultValue: "Rosiness"
        )
    }

    /// Result beauty control or recoverable effect status.
    static var beautyReset: String {
        Localization.string(
            "beauty.reset",
            table: "Generation",
            defaultValue: "Reset to default"
        )
    }

    /// Result beauty control or recoverable effect status.
    static var beautyApplying: String {
        Localization.string(
            "beauty.applying",
            table: "Generation",
            defaultValue: "Applying…"
        )
    }

    /// Result beauty control or recoverable effect status.
    static var beautyUnavailable: String {
        Localization.string(
            "beauty.unavailable",
            table: "Generation",
            defaultValue: "Beauty is unavailable and has been turned off. Generation will continue."
        )
    }

    /// Displayed text in Modules/FNGeneration/GenerationRepository.swift.
    static var errorThePreviousSessionIsStillStoppingPleaseTryAgain: String {
        Localization.string(
            "error.the_previous_session_is_still_stopping_please_try_again",
            table: "Generation",
            defaultValue: "The previous session is still stopping. Please try again in a moment."
        )
    }

    /// Displayed text in Modules/FNGeneration/GenerationRepository.swift.
    static var errorConnectAPhysicalCameraAndSelectItFromThe: String {
        Localization.string(
            "error.connect_a_physical_camera_and_select_it_from_the",
            table: "Generation",
            defaultValue: "Connect a physical camera and select it from the camera list."
        )
    }

    /// Displayed text in Modules/FNGeneration/GenerationRepository.swift.
    static var errorUnableToDecodeReferenceImagePleaseChooseASupported: String {
        Localization.string(
            "error.unable_to_decode_reference_image_please_choose_a_supported",
            table: "Generation",
            defaultValue: "Unable to decode reference image; please choose a supported image file"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var modeCharacterSwap: String {
        Localization.string(
            "mode.character_swap",
            table: "Generation",
            defaultValue: "Character Swap"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var modeVirtualTryOn: String {
        Localization.string(
            "mode.virtual_try_on",
            table: "Generation",
            defaultValue: "Virtual Try-On"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var modeStyleTransfer: String {
        Localization.string(
            "mode.style_transfer",
            table: "Generation",
            defaultValue: "Style Transfer"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var modeFreePrompt: String {
        Localization.string(
            "mode.free_prompt",
            table: "Generation",
            defaultValue: "Free Prompt"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetClassicalGirl: String {
        Localization.string(
            "preset.classical_girl",
            table: "Generation",
            defaultValue: "Classical Girl"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetClassicalBoy: String {
        Localization.string(
            "preset.classical_boy",
            table: "Generation",
            defaultValue: "Classical Boy"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetModernGirl: String {
        Localization.string(
            "preset.modern_girl",
            table: "Generation",
            defaultValue: "Modern Girl"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetModernBoy: String {
        Localization.string(
            "preset.modern_boy",
            table: "Generation",
            defaultValue: "Modern Boy"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBlondeGirl: String {
        Localization.string(
            "preset.blonde_girl",
            table: "Generation",
            defaultValue: "Blonde Girl"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetCurlyHairedBoy: String {
        Localization.string(
            "preset.curly_haired_boy",
            table: "Generation",
            defaultValue: "Curly-Haired Boy"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetAnimeBoy: String {
        Localization.string(
            "preset.anime_boy",
            table: "Generation",
            defaultValue: "Anime Boy"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetAnimeGirl: String {
        Localization.string(
            "preset.anime_girl",
            table: "Generation",
            defaultValue: "Anime Girl"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var removedLegacyPreset: String {
        Localization.string(
            "preset.alien_kitty",
            table: "Generation",
            defaultValue: "removed preset"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBronzeFigure: String {
        Localization.string(
            "preset.bronze_figure",
            table: "Generation",
            defaultValue: "Bronze Figure"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var removedLegacyPreset: String {
        Localization.string(
            "preset.3d_cow",
            table: "Generation",
            defaultValue: "removed preset"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var removedLegacyPreset: String {
        Localization.string(
            "preset.3d_milk_frog",
            table: "Generation",
            defaultValue: "removed preset 1"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var preset3DKangaroo: String {
        Localization.string(
            "preset.3d_kangaroo",
            table: "Generation",
            defaultValue: "3D Kangaroo"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetMechaGirl: String {
        Localization.string(
            "preset.mecha_girl",
            table: "Generation",
            defaultValue: "Mecha Girl"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var removedLegacyPreset: String {
        Localization.string(
            "preset.mecha_warrior",
            table: "Generation",
            defaultValue: "removed preset 8"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetSpecialOps: String {
        Localization.string(
            "preset.special_ops",
            table: "Generation",
            defaultValue: "Special Ops"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetHumanoidRobot: String {
        Localization.string(
            "preset.humanoid_robot",
            table: "Generation",
            defaultValue: "Humanoid Robot"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetChillCapybara: String {
        Localization.string(
            "preset.chill_capybara",
            table: "Generation",
            defaultValue: "Chill Capybara"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetGentlePanda: String {
        Localization.string(
            "preset.gentle_panda",
            table: "Generation",
            defaultValue: "Gentle Panda"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetCuteHamster: String {
        Localization.string(
            "preset.cute_hamster",
            table: "Generation",
            defaultValue: "Cute Hamster"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetIllustratedGirl: String {
        Localization.string(
            "preset.illustrated_girl",
            table: "Generation",
            defaultValue: "Illustrated Girl"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetCartoonBoy: String {
        Localization.string(
            "preset.cartoon_boy",
            table: "Generation",
            defaultValue: "Cartoon Boy"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var removedLegacyPreset: String {
        Localization.string(
            "preset.business_milk_frog",
            table: "Generation",
            defaultValue: "removed preset 6"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetCorporateCow: String {
        Localization.string(
            "preset.corporate_cow",
            table: "Generation",
            defaultValue: "Corporate Cow"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetGildedGoddess: String {
        Localization.string(
            "preset.gilded_goddess",
            table: "Generation",
            defaultValue: "Gilded Goddess"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetMonochromeVanguard: String {
        Localization.string(
            "preset.monochrome_vanguard",
            table: "Generation",
            defaultValue: "Monochrome Vanguard"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetSilverFantasyRobe: String {
        Localization.string(
            "preset.silver_fantasy_robe",
            table: "Generation",
            defaultValue: "Silver Fantasy Robe"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetNavySailorOutfit: String {
        Localization.string(
            "preset.navy_sailor_outfit",
            table: "Generation",
            defaultValue: "Navy Sailor Outfit"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetLongCoatSet: String {
        Localization.string(
            "preset.long_coat_set",
            table: "Generation",
            defaultValue: "Long Coat Set"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetPinkAcademy: String {
        Localization.string(
            "preset.pink_academy",
            table: "Generation",
            defaultValue: "Pink Academy"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBronzeWarriorArmor: String {
        Localization.string(
            "preset.bronze_warrior_armor",
            table: "Generation",
            defaultValue: "Bronze Warrior Armor"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetVintageBrown: String {
        Localization.string(
            "preset.vintage_brown",
            table: "Generation",
            defaultValue: "Vintage Brown"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBlackCollarAcademy: String {
        Localization.string(
            "preset.black_collar_academy",
            table: "Generation",
            defaultValue: "Black-Collar Academy"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBluePlaidAcademy: String {
        Localization.string(
            "preset.blue_plaid_academy",
            table: "Generation",
            defaultValue: "Blue Plaid Academy"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBlackPinafore: String {
        Localization.string(
            "preset.black_pinafore",
            table: "Generation",
            defaultValue: "Black Pinafore"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetCoffeeCardigan: String {
        Localization.string(
            "preset.coffee_cardigan",
            table: "Generation",
            defaultValue: "Coffee Cardigan"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetLilacSlipDress: String {
        Localization.string(
            "preset.lilac_slip_dress",
            table: "Generation",
            defaultValue: "Lilac Slip Dress"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetMagentaTechwear: String {
        Localization.string(
            "preset.magenta_techwear",
            table: "Generation",
            defaultValue: "Magenta Techwear"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetLuxurySuit: String {
        Localization.string(
            "preset.luxury_suit",
            table: "Generation",
            defaultValue: "Luxury Suit"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetNavyOfficewear: String {
        Localization.string(
            "preset.navy_officewear",
            table: "Generation",
            defaultValue: "Navy Officewear"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBurgundyStripes: String {
        Localization.string(
            "preset.burgundy_stripes",
            table: "Generation",
            defaultValue: "Burgundy Stripes"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetLightBlueSportswear: String {
        Localization.string(
            "preset.light_blue_sportswear",
            table: "Generation",
            defaultValue: "Light Blue Sportswear"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetSilverCasualwear: String {
        Localization.string(
            "preset.silver_casualwear",
            table: "Generation",
            defaultValue: "Silver Casualwear"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBritishBrownPlaid: String {
        Localization.string(
            "preset.british_brown_plaid",
            table: "Generation",
            defaultValue: "British Brown Plaid"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBlueAndWhiteRetro: String {
        Localization.string(
            "preset.blue_and_white_retro",
            table: "Generation",
            defaultValue: "Blue and White Retro"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetAllDenimOutfit: String {
        Localization.string(
            "preset.all_denim_outfit",
            table: "Generation",
            defaultValue: "All-Denim Outfit"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetGrayEveningwear: String {
        Localization.string(
            "preset.gray_eveningwear",
            table: "Generation",
            defaultValue: "Gray Eveningwear"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetBlackClassicalRobe: String {
        Localization.string(
            "preset.black_classical_robe",
            table: "Generation",
            defaultValue: "Black Classical Robe"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetAmericanCartoon: String {
        Localization.string(
            "preset.american_cartoon",
            table: "Generation",
            defaultValue: "American Cartoon"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var preset3DCartoon: String {
        Localization.string(
            "preset.3d_cartoon",
            table: "Generation",
            defaultValue: "3D Cartoon"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetSchoolAnime: String {
        Localization.string(
            "preset.school_anime",
            table: "Generation",
            defaultValue: "School Anime"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetUrbanAnime: String {
        Localization.string(
            "preset.urban_anime",
            table: "Generation",
            defaultValue: "Urban Anime"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetJapaneseAnime: String {
        Localization.string(
            "preset.japanese_anime",
            table: "Generation",
            defaultValue: "Japanese Anime"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetRealisticAnimals: String {
        Localization.string(
            "preset.realistic_animals",
            table: "Generation",
            defaultValue: "Realistic Animals"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetDesignerToy: String {
        Localization.string(
            "preset.designer_toy",
            table: "Generation",
            defaultValue: "Designer Toy"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetAnthropomorphic: String {
        Localization.string(
            "preset.anthropomorphic",
            table: "Generation",
            defaultValue: "Anthropomorphic"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetSurrealism: String {
        Localization.string(
            "preset.surrealism",
            table: "Generation",
            defaultValue: "Surrealism"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetDisneyStyle: String {
        Localization.string(
            "preset.disney_style",
            table: "Generation",
            defaultValue: "Disney Style"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetCelShading: String {
        Localization.string(
            "preset.cel_shading",
            table: "Generation",
            defaultValue: "Cel Shading"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/Model/GenerationMode.swift.
    static var presetJapaneseAnimation: String {
        Localization.string(
            "preset.japanese_animation",
            table: "Generation",
            defaultValue: "Japanese Animation"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationReferenceButton.swift.
    static var controlsUploadYourOwnReferenceImage: String {
        Localization.string(
            "controls.upload_your_own_reference_image",
            table: "Generation",
            defaultValue: "Upload your own reference image"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationReferenceButton.swift.
    static var controlsUploadReferenceImage: String {
        Localization.string(
            "controls.upload_reference_image",
            table: "Generation",
            defaultValue: "Upload reference image"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationReferenceButton.swift.
    static var selected: String {
        Localization.string(
            "state.selected",
            table: "Common",
            defaultValue: "Selected"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationReferenceButton.swift.
    static var controlsUpload: String {
        Localization.string(
            "controls.upload",
            table: "Generation",
            defaultValue: "Upload"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationReferenceButton.swift.
    static var retry: String {
        Localization.string(
            "action.retry",
            table: "Common",
            defaultValue: "Retry"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsShowStatistics: String {
        Localization.string(
            "controls.show_statistics",
            table: "Generation",
            defaultValue: "Show statistics"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsAdjustRemotePlaybackVolume: String {
        Localization.string(
            "controls.adjust_remote_playback_volume",
            table: "Generation",
            defaultValue: "Adjust remote playback volume"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsRemoteVolume: String {
        Localization.string(
            "controls.remote_volume",
            table: "Generation",
            defaultValue: "Remote volume"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsFrameInterpolation: String {
        Localization.string(
            "controls.frame_interpolation",
            table: "Generation",
            defaultValue: "Frame interpolation"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsStopSession: String {
        Localization.string(
            "controls.stop_session",
            table: "Generation",
            defaultValue: "Stop Session"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsMuted: String {
        Localization.string(
            "controls.muted",
            table: "Generation",
            defaultValue: "Muted"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsStopping: String {
        Localization.string(
            "controls.stopping",
            table: "Generation",
            defaultValue: "Stopping…"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsHideStatisticsCollectionAndLoggingContinue: String {
        Localization.string(
            "controls.hide_statistics_collection_and_logging_continue",
            table: "Generation",
            defaultValue: "Hide statistics (collection and logging continue)"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var on: String {
        Localization.string(
            "state.on",
            table: "Common",
            defaultValue: "On"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var off: String {
        Localization.string(
            "state.off",
            table: "Common",
            defaultValue: "Off"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsSwitchingFrameInterpolation: String {
        Localization.string(
            "controls.switching_frame_interpolation",
            table: "Generation",
            defaultValue: "Switching frame interpolation…"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controls2FrameInterpolationIsOnClickToTurnOff: String {
        Localization.string(
            "controls.2_frame_interpolation_is_on_click_to_turn_off",
            table: "Generation",
            defaultValue: "2× frame interpolation is on. Click to turn off"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsFrameInterpolationIsOffClickToTurnOn: String {
        Localization.string(
            "controls.frame_interpolation_is_off_click_to_turn_on",
            table: "Generation",
            defaultValue: "Frame interpolation is off. Click to turn on"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationToolbarView.swift.
    static var controlsSwitching: String {
        Localization.string(
            "controls.switching",
            table: "Generation",
            defaultValue: "Switching"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationWorkspaceView.swift.
    static var controlsLocal: String {
        Localization.string(
            "controls.local",
            table: "Generation",
            defaultValue: "Preview"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationWorkspaceView.swift.
    static var controlsResult: String {
        Localization.string(
            "controls.result",
            table: "Generation",
            defaultValue: "AI Generation"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationWorkspaceView.swift.
    static var controlsDescribeHowYouWantTheVideoToChange: String {
        Localization.string(
            "controls.describe_how_you_want_the_video_to_change",
            table: "Generation",
            defaultValue: "Describe how you want the video to change"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationWorkspaceView.swift.
    static var controlsRemoveReference: String {
        Localization.string(
            "controls.remove_reference",
            table: "Generation",
            defaultValue: "Remove reference"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationWorkspaceView.swift.
    static var controlsSubmitPrompt: String {
        Localization.string(
            "controls.submit_prompt",
            table: "Generation",
            defaultValue: "Submit prompt"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationWorkspaceView.swift.
    static var controlsGenerating: String {
        Localization.string(
            "controls.generating",
            table: "Generation",
            defaultValue: "Generating…"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/View/GenerationWorkspaceView.swift.
    static var controlsWaitingForConnection: String {
        Localization.string(
            "controls.waiting_for_connection",
            table: "Generation",
            defaultValue: "Waiting for connection…"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsLaunchTiming: String {
        Localization.string(
            "statistics.launch_timing",
            table: "Generation",
            defaultValue: "Launch timing"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsSessionCreation: String {
        Localization.string(
            "statistics.session_creation",
            table: "Generation",
            defaultValue: "Session creation"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsTimeSpentCreatingTheServerSideGenerationSession: String {
        Localization.string(
            "statistics.time_spent_creating_the_server_side_generation_session",
            table: "Generation",
            defaultValue: "Time spent creating the server-side generation session"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsFromJoiningTheRTCChannelUntilTheConnectionSucceeds: String {
        Localization.string(
            "statistics.from_joining_the_rtc_channel_until_the_connection_succeeds",
            table: "Generation",
            defaultValue: "From joining the RTC channel until the connection succeeds"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsStreamPublication: String {
        Localization.string(
            "statistics.stream_publication",
            table: "Generation",
            defaultValue: "Stream publication"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsTimeSpentPublishingTheLocalMediaStreamToThe: String {
        Localization.string(
            "statistics.time_spent_publishing_the_local_media_stream_to_the",
            table: "Generation",
            defaultValue: "Time spent publishing the local media stream to the RTC channel"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsFirstFrameLatency: String {
        Localization.string(
            "statistics.first_frame_latency",
            table: "Generation",
            defaultValue: "First frame latency"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsFromGenerationSignalSubmissionToTheFirstDisplayReady: String {
        Localization.string(
            "statistics.from_generation_signal_submission_to_the_first_display_ready",
            table: "Generation",
            defaultValue: "From generation signal submission to the first display-ready result frame"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsTotalStartup: String {
        Localization.string(
            "statistics.total_startup",
            table: "Generation",
            defaultValue: "Total startup"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsFromStartingGenerationAfterCameraReadinessToTheFirst: String {
        Localization.string(
            "statistics.from_starting_generation_after_camera_readiness_to_the_first",
            table: "Generation",
            defaultValue:
                "From starting generation after camera readiness to the first display-ready result. Camera preparation is excluded; the total is measured directly, not added from stage durations."
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsUplinkVideoStatistics: String {
        Localization.string(
            "statistics.uplink_video_statistics",
            table: "Generation",
            defaultValue: "Uplink video statistics"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsUplinkResolution: String {
        Localization.string(
            "statistics.uplink_resolution",
            table: "Generation",
            defaultValue: "Uplink resolution"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsUplinkFrameRate: String {
        Localization.string(
            "statistics.uplink_frame_rate",
            table: "Generation",
            defaultValue: "Uplink frame rate"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsUplinkBitrate: String {
        Localization.string(
            "statistics.uplink_bitrate",
            table: "Generation",
            defaultValue: "Uplink bitrate"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsUplinkNetworkAndLatency: String {
        Localization.string(
            "statistics.uplink_network_and_latency",
            table: "Generation",
            defaultValue: "Uplink network and latency"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsUplinkPacketLoss: String {
        Localization.string(
            "statistics.uplink_packet_loss",
            table: "Generation",
            defaultValue: "Uplink packet loss"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsPacketLossFromThisSDKToTheRTCCloud: String {
        Localization.string(
            "statistics.packet_loss_from_this_sdk_to_the_rtc_cloud",
            table: "Generation",
            defaultValue: "Packet loss from this SDK to the RTC cloud, not local preview loss"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsUplinkNetworkQuality: String {
        Localization.string(
            "statistics.uplink_network_quality",
            table: "Generation",
            defaultValue: "Uplink network quality"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsUplinkRTT: String {
        Localization.string(
            "statistics.uplink_rtt",
            table: "Generation",
            defaultValue: "Uplink RTT"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsNotExposedByTheMacOSSDK: String {
        Localization.string(
            "statistics.not_exposed_by_the_macos_sdk",
            table: "Generation",
            defaultValue: "Not exposed by the macOS SDK"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsDownlinkVideoStatistics: String {
        Localization.string(
            "statistics.downlink_video_statistics",
            table: "Generation",
            defaultValue: "Downlink video statistics"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsDownlinkResolution: String {
        Localization.string(
            "statistics.downlink_resolution",
            table: "Generation",
            defaultValue: "Downlink resolution"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsDownlinkFrameRate: String {
        Localization.string(
            "statistics.downlink_frame_rate",
            table: "Generation",
            defaultValue: "Downlink frame rate"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsDownlinkBitrate: String {
        Localization.string(
            "statistics.downlink_bitrate",
            table: "Generation",
            defaultValue: "Downlink bitrate"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsDownlinkNetworkAndLatency: String {
        Localization.string(
            "statistics.downlink_network_and_latency",
            table: "Generation",
            defaultValue: "Downlink network and latency"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsPlaybackBufferDelay: String {
        Localization.string(
            "statistics.playback_buffer_delay",
            table: "Generation",
            defaultValue: "Playback buffer delay"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsDownlinkPacketLoss: String {
        Localization.string(
            "statistics.downlink_packet_loss",
            table: "Generation",
            defaultValue: "Downlink packet loss"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsDownlinkNetworkQuality: String {
        Localization.string(
            "statistics.downlink_network_quality",
            table: "Generation",
            defaultValue: "Downlink network quality"
        )
    }

    /// Displayed text in Modules/FNGeneration/MVVM/ViewModel/GenerationStatisticsViewModel.swift.
    static var statisticsVeryBad: String {
        Localization.string(
            "statistics.very_bad",
            table: "Generation",
            defaultValue: "Very bad"
        )
    }

    /// Display label for a diagnostic metric; the metric ID remains stable.
    static var statisticsRTCConnection: String {
        Localization.string(
            "statistics.rtc_connection",
            table: "Generation",
            defaultValue: "RTC connection"
        )
    }

    /// Display label for a diagnostic metric; the metric ID remains stable.
    static var statisticsRTTCloud: String {
        Localization.string(
            "statistics.rtt_cloud",
            table: "Generation",
            defaultValue: "RTT (cloud)"
        )
    }

    /// Display label for a diagnostic metric; the metric ID remains stable.
    static var statisticsE2ERTCEstimate: String {
        Localization.string(
            "statistics.e2e_rtc_estimate",
            table: "Generation",
            defaultValue: "E2E (RTC estimate)"
        )
    }

    /// Generation control state or interpolation label.
    static var controls2x: String {
        Localization.string(
            "controls.2x",
            table: "Generation",
            defaultValue: "2x"
        )
    }

    /// Complete message; preserve all format placeholders.
    static func outputFailed(
        message: String
    ) -> String {
        Localization.format(
            "message.virtual_camera_output_failed_error_localizeddescription",
            table: "Generation",
            defaultValue: "Virtual camera output failed: %@",
            arguments: [message]
        )
    }

    /// Localizes metric labels while keeping their existing identity values unchanged.
    static func statisticsTitle(
        _ id: String
    ) -> String {
        switch id {
        case "Launch timing": statisticsLaunchTiming
        case "Session creation": statisticsSessionCreation
        case "RTC connection": statisticsRTCConnection
        case "Stream publication": statisticsStreamPublication
        case "First frame latency": statisticsFirstFrameLatency
        case "Total startup": statisticsTotalStartup
        case "Uplink video statistics": statisticsUplinkVideoStatistics
        case "Uplink resolution": statisticsUplinkResolution
        case "Uplink frame rate": statisticsUplinkFrameRate
        case "Uplink bitrate": statisticsUplinkBitrate
        case "Uplink network and latency": statisticsUplinkNetworkAndLatency
        case "Uplink packet loss": statisticsUplinkPacketLoss
        case "Uplink network quality": statisticsUplinkNetworkQuality
        case "Uplink RTT": statisticsUplinkRTT
        case "Downlink video statistics": statisticsDownlinkVideoStatistics
        case "Downlink resolution": statisticsDownlinkResolution
        case "Downlink frame rate": statisticsDownlinkFrameRate
        case "Downlink bitrate": statisticsDownlinkBitrate
        case "Downlink network and latency": statisticsDownlinkNetworkAndLatency
        case "Playback buffer delay": statisticsPlaybackBufferDelay
        case "Downlink packet loss": statisticsDownlinkPacketLoss
        case "Downlink network quality": statisticsDownlinkNetworkQuality
        case "RTT (cloud)": statisticsRTTCloud
        case "E2E (RTC estimate)": statisticsE2ERTCEstimate
        default: id
        }
    }
    /// Complete display message; preserve the format placeholders.
    static func retryUpload(
        message: String
    ) -> String {
        Localization.format(
            "reference.retry_error",
            table: "Generation",
            defaultValue: "%@ — Click to retry",
            arguments: [message]
        )
    }

    /// Complete display message; preserve the format placeholders.
    static func percentage(
        value: Int
    ) -> String {
        Localization.format(
            "value.percentage",
            table: "Generation",
            defaultValue: "%lld%%",
            arguments: [Int64(value)]
        )
    }

    /// Complete display message; preserve the format placeholders.
    static func milliseconds(
        value: Double
    ) -> String {
        Localization.format(
            "statistics.milliseconds",
            table: "Generation",
            defaultValue: "%.1f ms",
            arguments: [value]
        )
    }

    /// Complete display message; preserve the format placeholders.
    static func metric(
        value: Int,
        unit: String
    ) -> String {
        Localization.format(
            "statistics.metric",
            table: "Generation",
            defaultValue: "%1$lld %2$@",
            arguments: [Int64(value), unit]
        )
    }

    /// Complete display message; preserve the format placeholders.
    static func resolution(
        width: Int,
        height: Int
    ) -> String {
        Localization.format(
            "statistics.resolution",
            table: "Generation",
            defaultValue: "%1$lld × %2$lld",
            arguments: [Int64(width), Int64(height)]
        )
    }

    /// Localized SDK network-quality display value; the SDK enum is unchanged.
    static var qualityUnknown: String {
        Localization.string("statistics.qualityUnknown", table: "Generation", defaultValue: "Unknown")
    }

    /// Localized SDK network-quality display value; the SDK enum is unchanged.
    static var qualityExcellent: String {
        Localization.string("statistics.qualityExcellent", table: "Generation", defaultValue: "Excellent")
    }

    /// Localized SDK network-quality display value; the SDK enum is unchanged.
    static var qualityGood: String {
        Localization.string("statistics.qualityGood", table: "Generation", defaultValue: "Good")
    }

    /// Localized SDK network-quality display value; the SDK enum is unchanged.
    static var qualityPoor: String {
        Localization.string("statistics.qualityPoor", table: "Generation", defaultValue: "Poor")
    }

    /// Localized SDK network-quality display value; the SDK enum is unchanged.
    static var qualityBad: String {
        Localization.string("statistics.qualityBad", table: "Generation", defaultValue: "Bad")
    }

    /// Localized SDK network-quality display value; the SDK enum is unchanged.
    static var qualityDown: String {
        Localization.string("statistics.qualityDown", table: "Generation", defaultValue: "Down")
    }

}
