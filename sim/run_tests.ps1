[CmdletBinding()]
param([string[]]$TestName)

$ErrorActionPreference = 'Stop'
$simRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $simRoot
$sourceRoot = Join-Path $repoRoot 'src\user_source\hdl_source'

$modelsimCandidates = [System.Collections.Generic.List[string]]::new()
if ($env:MODELSIM_BIN) {
    $modelsimCandidates.Add($env:MODELSIM_BIN)
}
$vsimCommand = Get-Command 'vsim.exe' -ErrorAction SilentlyContinue
if ($vsimCommand) {
    $modelsimCandidates.Add((Split-Path -Parent $vsimCommand.Source))
}
# Known installation detected on the baseline machine. It is only a fallback;
# the repository and RTL source paths above remain fully location-independent.
$modelsimCandidates.Add('D:\modelism10.4\win64')

$modelsimBin = $null
foreach ($candidate in ($modelsimCandidates | Select-Object -Unique)) {
    if ((Test-Path -LiteralPath (Join-Path $candidate 'vlib.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'vlog.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'vsim.exe') -PathType Leaf)) {
        $modelsimBin = $candidate
        break
    }
}
if (-not $modelsimBin) {
    throw ('ModelSim not found. Put vsim.exe/vlog.exe/vlib.exe on PATH or set ' +
           'MODELSIM_BIN to their directory. Checked: ' +
           (($modelsimCandidates | Select-Object -Unique) -join ', '))
}

$vlib = Join-Path $modelsimBin 'vlib.exe'
$vlog = Join-Path $modelsimBin 'vlog.exe'
$vsim = Join-Path $modelsimBin 'vsim.exe'

foreach ($tool in @($vlib, $vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required simulator executable not found: $tool"
    }
}
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "RTL source directory not found: $sourceRoot"
}

$tests = @(
    [pscustomobject]@{
        Name = 'video timing'; Top = 'tb_video_timing'; Marker = 'VIDEO_TIMING_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'SD\color_bar.v'),
            (Join-Path $sourceRoot 'SD\video_timing_data.v'),
            (Join-Path $simRoot 'tb_video_timing.v')
        )
        IncludeDir = (Join-Path $sourceRoot 'SD')
    },
    [pscustomobject]@{
        Name = 'bmp read'; Top = 'tb_bmp_read'; Marker = 'BMP_READ_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'SD\bmp_read.v'),
            (Join-Path $sourceRoot 'sd_sector_buffer.v'),
            (Join-Path $sourceRoot 'bmp_pixel_decoder.v'),
            (Join-Path $simRoot 'tb_bmp_read.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'i2s loopback'; Top = 'tb_i2s_loopback'; Marker = 'I2S_LOOPBACK_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'hdmi_audio_tone_i2s_64fs.v'),
            (Join-Path $sourceRoot 'I2S_receiver.v'),
            (Join-Path $simRoot 'tb_i2s_loopback.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'key debounce'; Top = 'tb_key_press_debounce'; Marker = 'KEY_DEBOUNCE_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'SD\sd_card_bmp.v'),
            (Join-Path $simRoot 'tb_key_press_debounce.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'debug status'; Top = 'tb_debug_status'; Marker = 'DEBUG_STATUS_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'debug_status.v'),
            (Join-Path $simRoot 'tb_debug_status.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'osd overlay'; Top = 'tb_osd_overlay'; Marker = 'OSD_OVERLAY_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'osd_status_cdc.v'),
            (Join-Path $sourceRoot 'osd_overlay.v'),
            (Join-Path $simRoot 'tb_osd_overlay.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'video adjust'; Top = 'tb_video_adjust'; Marker = 'VIDEO_ADJUST_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'display_adjust_control.v'),
            (Join-Path $sourceRoot 'video_adjust.v'),
            (Join-Path $simRoot 'tb_video_adjust.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'video fade'; Top = 'tb_video_fade'; Marker = 'VIDEO_FADE_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'video_fade.v'),
            (Join-Path $simRoot 'tb_video_fade.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'fade transition'; Top = 'tb_fade_transition'; Marker = 'FADE_TRANSITION_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'fade_transition_cdc.v'),
            (Join-Path $sourceRoot 'fade_transition_ctrl.v'),
            (Join-Path $simRoot 'tb_fade_transition.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'write ack'; Top = 'tb_write_ack'; Marker = 'WRITE_ACK_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'sd_sector_buffer.v'),
            (Join-Path $sourceRoot 'bmp_pixel_decoder.v'),
            (Join-Path $sourceRoot 'image_scaler.v'),
            (Join-Path $sourceRoot 'frame_completion_guard.v'),
            (Join-Path $sourceRoot 'debug_status.v'),
            (Join-Path $sourceRoot 'SD\bmp_read.v'),
            (Join-Path $sourceRoot 'SD\sd_card_bmp.v'),
            (Join-Path $sourceRoot 'SD\frame_fifo_write.v'),
            (Join-Path $sourceRoot 'fade_transition_cdc.v'),
            (Join-Path $sourceRoot 'fade_transition_ctrl.v'),
            (Join-Path $simRoot 'tb_write_ack.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'memory arbitration'; Top = 'tb_memory_arbitration'; Marker = 'MEMORY_ARBITRATION_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'IP\afifo_16_32_256.v'),
            (Join-Path $sourceRoot 'IP\afifo_32_16_256.v'),
            (Join-Path $sourceRoot 'SD\frame_fifo_write.v'),
            (Join-Path $sourceRoot 'SD\frame_fifo_read.v'),
            (Join-Path $simRoot 'models\frame_fifo_write_baseline.v'),
            (Join-Path $simRoot 'tb_memory_arbitration.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'image scaling'; Top = 'tb_image_scaling'; Marker = 'IMAGE_SCALING_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'debug_status.v'),
            (Join-Path $sourceRoot 'sd_sector_buffer.v'),
            (Join-Path $sourceRoot 'bmp_pixel_decoder.v'),
            (Join-Path $sourceRoot 'image_scaler.v'),
            (Join-Path $sourceRoot 'frame_completion_guard.v'),
            (Join-Path $sourceRoot 'SD\bmp_read.v'),
            (Join-Path $sourceRoot 'SD\sd_card_bmp.v'),
            (Join-Path $sourceRoot 'IP\afifo_16_32_256.v'),
            (Join-Path $sourceRoot 'IP\afifo_32_16_256.v'),
            (Join-Path $sourceRoot 'SD\frame_fifo_write.v'),
            (Join-Path $sourceRoot 'SD\frame_fifo_read.v'),
            (Join-Path $sourceRoot 'SD\frame_read_write.v'),
            (Join-Path $sourceRoot 'fade_transition_cdc.v'),
            (Join-Path $sourceRoot 'fade_transition_ctrl.v'),
            (Join-Path $simRoot 'tb_image_scaling.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'bmp stream'; Top = 'tb_bmp_stream'; Marker = 'BMP_STREAM_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'sd_sector_buffer.v'),
            (Join-Path $sourceRoot 'bmp_pixel_decoder.v'),
            (Join-Path $sourceRoot 'SD\bmp_read.v'),
            (Join-Path $simRoot 'tb_bmp_stream.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'frame completion'; Top = 'tb_frame_completion'; Marker = 'FRAME_COMPLETION_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'frame_completion_guard.v'),
            (Join-Path $simRoot 'tb_frame_completion.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'scaler control'; Top = 'tb_scaler_control'; Marker = 'SCALER_CONTROL_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'image_scaler.v'),
            (Join-Path $simRoot 'tb_scaler_control.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'audio wave capture'; Top = 'tb_audio_wave_capture'; Marker = 'AUDIO_WAVE_CAPTURE_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'audio_wave_capture.v'),
            (Join-Path $simRoot 'tb_audio_wave_capture.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'audio wave overlay'; Top = 'tb_audio_wave_overlay'; Marker = 'AUDIO_WAVE_OVERLAY_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'audio_wave_overlay.v'),
            (Join-Path $sourceRoot 'video_adjust.v'),
            (Join-Path $sourceRoot 'video_fade.v'),
            (Join-Path $sourceRoot 'osd_overlay.v'),
            (Join-Path $simRoot 'tb_audio_wave_overlay.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'audio wave link'; Top = 'tb_audio_wave_link'; Marker = 'AUDIO_WAVE_LINK_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'hdmi_audio_tone_i2s_64fs.v'),
            (Join-Path $sourceRoot 'I2S_receiver.v'),
            (Join-Path $sourceRoot 'audio_wave_capture.v'),
            (Join-Path $simRoot 'tb_audio_wave_link.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'audio wave video'; Top = 'tb_audio_wave_video'; Marker = 'AUDIO_WAVE_VIDEO_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'audio_wave_capture.v'),
            (Join-Path $sourceRoot 'audio_wave_overlay.v'),
            (Join-Path $sourceRoot 'video_active_position.v'),
            (Join-Path $sourceRoot 'SD\color_bar.v'),
            (Join-Path $sourceRoot 'SD\video_timing_data.v'),
            (Join-Path $sourceRoot 'SD\video_delay.v'),
            (Join-Path $simRoot 'tb_audio_wave_video.v')
        )
        IncludeDir = (Join-Path $sourceRoot 'SD')
    },
    [pscustomobject]@{
        Name = 'dynamic subtitle'; Top = 'tb_dynamic_subtitle'; Marker = 'DYNAMIC_SUBTITLE_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'dynamic_subtitle_overlay.v'),
            (Join-Path $simRoot 'tb_dynamic_subtitle.v')
        )
        IncludeDir = @($sourceRoot, $simRoot)
    },
    [pscustomobject]@{
        Name = 'subtitle composition'; Top = 'tb_subtitle_composition'; Marker = 'SUBTITLE_COMPOSITION_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'dynamic_subtitle_overlay.v'),
            (Join-Path $sourceRoot 'audio_wave_capture.v'),
            (Join-Path $sourceRoot 'audio_wave_overlay.v'),
            (Join-Path $sourceRoot 'video_active_position.v'),
            (Join-Path $sourceRoot 'video_adjust.v'),
            (Join-Path $sourceRoot 'video_fade.v'),
            (Join-Path $sourceRoot 'osd_overlay.v'),
            (Join-Path $sourceRoot 'SD\color_bar.v'),
            (Join-Path $sourceRoot 'SD\video_timing_data.v'),
            (Join-Path $sourceRoot 'SD\video_delay.v'),
            (Join-Path $simRoot 'tb_subtitle_composition.v')
        )
        IncludeDir = @($sourceRoot, $simRoot, (Join-Path $sourceRoot 'SD'))
    },
    [pscustomobject]@{
        Name = 'sd scan timing'; Top = 'tb_sd_scan_timing'; Marker = 'SD_SCAN_TIMING_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'sd_sector_buffer.v'),
            (Join-Path $sourceRoot 'bmp_pixel_decoder.v'),
            (Join-Path $sourceRoot 'image_scaler.v'),
            (Join-Path $sourceRoot 'frame_completion_guard.v'),
            (Join-Path $sourceRoot 'SD\bmp_read.v'),
            (Join-Path $simRoot 'models\bmp_read_scan_baseline.v'),
            (Join-Path $sourceRoot 'fade_transition_cdc.v'),
            (Join-Path $sourceRoot 'fade_transition_ctrl.v'),
            (Join-Path $simRoot 'tb_sd_scan_timing.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'image melody'; Top = 'tb_image_melody'; Marker = 'IMAGE_MELODY_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'image_melody_pcm.v'),
            (Join-Path $simRoot 'tb_image_melody.v')
        )
        IncludeDir = @($sourceRoot, $simRoot)
    },
    [pscustomobject]@{
        Name = 'image audio cdc'; Top = 'tb_image_audio_cdc'; Marker = 'IMAGE_AUDIO_CDC_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'image_audio_cdc.v'),
            (Join-Path $simRoot 'tb_image_audio_cdc.v')
        )
        IncludeDir = $null
    },
    [pscustomobject]@{
        Name = 'image audio link'; Top = 'tb_image_audio_link'; Marker = 'IMAGE_AUDIO_LINK_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'debug_status.v'),
            (Join-Path $sourceRoot 'sd_sector_buffer.v'),
            (Join-Path $sourceRoot 'bmp_pixel_decoder.v'),
            (Join-Path $sourceRoot 'image_scaler.v'),
            (Join-Path $sourceRoot 'frame_completion_guard.v'),
            (Join-Path $sourceRoot 'SD\bmp_read.v'),
            (Join-Path $sourceRoot 'SD\sd_card_bmp.v'),
            (Join-Path $sourceRoot 'fade_transition_cdc.v'),
            (Join-Path $sourceRoot 'fade_transition_ctrl.v'),
            (Join-Path $sourceRoot 'image_audio_cdc.v'),
            (Join-Path $sourceRoot 'image_melody_i2s.v'),
            (Join-Path $sourceRoot 'I2S_receiver.v'),
            (Join-Path $sourceRoot 'audio_wave_capture.v'),
            (Join-Path $simRoot 'tb_image_audio_link.v')
        )
        IncludeDir = $sourceRoot
    },
    [pscustomobject]@{
        Name = 'image audio video'; Top = 'tb_image_audio_video'; Marker = 'IMAGE_AUDIO_VIDEO_TEST_PASS'
        Sources = @(
            (Join-Path $sourceRoot 'image_audio_cdc.v'),
            (Join-Path $sourceRoot 'image_melody_i2s.v'),
            (Join-Path $sourceRoot 'I2S_receiver.v'),
            (Join-Path $sourceRoot 'audio_wave_capture.v'),
            (Join-Path $sourceRoot 'audio_wave_overlay.v'),
            (Join-Path $sourceRoot 'dynamic_subtitle_overlay.v'),
            (Join-Path $sourceRoot 'video_active_position.v'),
            (Join-Path $sourceRoot 'video_adjust.v'),
            (Join-Path $sourceRoot 'video_fade.v'),
            (Join-Path $sourceRoot 'osd_overlay.v'),
            (Join-Path $sourceRoot 'SD\color_bar.v'),
            (Join-Path $sourceRoot 'SD\video_timing_data.v'),
            (Join-Path $sourceRoot 'SD\video_delay.v'),
            (Join-Path $simRoot 'tb_image_audio_video.v')
        )
        IncludeDir = @($sourceRoot, (Join-Path $sourceRoot 'SD'))
    },
    [pscustomobject]@{
        Name='playback interval'; Top='tb_playback_interval'; Marker='PLAYBACK_INTERVAL_TEST_PASS'
        Sources=@((Join-Path $sourceRoot 'playback_interval_control.v'),(Join-Path $sourceRoot 'SD\sd_card_bmp.v'),(Join-Path $simRoot 'tb_playback_interval.v'))
        IncludeDir=$null
    },
    [pscustomobject]@{
        Name='presentation control'; Top='tb_presentation_control'; Marker='PRESENTATION_CONTROL_TEST_PASS'
        Sources=@((Join-Path $sourceRoot 'presentation_control.v'),(Join-Path $sourceRoot 'video_adjust.v'),(Join-Path $simRoot 'tb_presentation_control.v'))
        IncludeDir=$null
    },
    [pscustomobject]@{
        Name='interaction osd'; Top='tb_interaction_osd'; Marker='INTERACTION_OSD_TEST_PASS'
        Sources=@((Join-Path $sourceRoot 'osd_status_cdc.v'),(Join-Path $sourceRoot 'osd_overlay.v'),(Join-Path $simRoot 'tb_interaction_osd.v'))
        IncludeDir=$null
    }
)

# New integrated fixtures use the exact previous real scan/audio/video source
# sets, plus the presentation wrappers. No old fixture/assertion is removed.
$audioLinkSources = ($tests | Where-Object Name -eq 'image audio link').Sources | Where-Object { $_ -ne (Join-Path $simRoot 'tb_image_audio_link.v') }
$audioVideoSources = ($tests | Where-Object Name -eq 'image audio video').Sources | Where-Object { $_ -ne (Join-Path $simRoot 'tb_image_audio_video.v') }
$tests += [pscustomobject]@{
    Name='interaction link'; Top='tb_interaction_link'; Marker='INTERACTION_LINK_TEST_PASS'
    Sources=@($audioLinkSources)+@((Join-Path $sourceRoot 'presentation_control.v'),(Join-Path $simRoot 'tb_interaction_link.v'))
    IncludeDir=$sourceRoot
}
$tests += [pscustomobject]@{
    Name='presentation video'; Top='tb_presentation_video'; Marker='PRESENTATION_VIDEO_TEST_PASS'
    Sources=@($audioVideoSources)+@((Join-Path $sourceRoot 'presentation_control.v'),(Join-Path $sourceRoot 'presentation_overlay.v'),(Join-Path $simRoot 'tb_presentation_video.v'))
    IncludeDir=@($sourceRoot,(Join-Path $sourceRoot 'SD'))
}

$tests += [pscustomobject]@{
    Name='melody status';Top='tb_melody_status';Marker='MELODY_STATUS_TEST_PASS'
    Sources=@((Join-Path $sourceRoot 'image_melody_i2s.v'),(Join-Path $sourceRoot 'melody_status_cdc.v'),
        (Join-Path $simRoot 'models\image_melody_showcase_baseline.v'),(Join-Path $simRoot 'tb_melody_status.v'))
    IncludeDir=$sourceRoot
}
$tests += [pscustomobject]@{
    Name='scene notice';Top='tb_scene_notice';Marker='SCENE_NOTICE_TEST_PASS'
    Sources=@((Join-Path $sourceRoot 'scene_notice.v'),(Join-Path $simRoot 'tb_scene_notice.v'));IncludeDir=$null
}
$tests += [pscustomobject]@{
    Name='music panel';Top='tb_music_panel';Marker='MUSIC_PANEL_TEST_PASS'
    Sources=@((Join-Path $sourceRoot 'image_melody_rom.v'),(Join-Path $sourceRoot 'subtitle_font_rom.v'),
        (Join-Path $sourceRoot 'showcase_music_overlay.v'),(Join-Path $sourceRoot 'showcase_ui.v'),
        (Join-Path $simRoot 'tb_music_panel.v'));IncludeDir=$null
}


$tests += [pscustomobject]@{
    Name='showcase video';Top='tb_showcase_video';Marker='SHOWCASE_VIDEO_TEST_PASS'
    Sources=@($audioVideoSources)+@((Join-Path $sourceRoot 'presentation_control.v'),
        (Join-Path $sourceRoot 'melody_status_cdc.v'),(Join-Path $sourceRoot 'scene_notice.v'),
        (Join-Path $sourceRoot 'showcase_music_overlay.v'),(Join-Path $sourceRoot 'showcase_ui.v'),
        (Join-Path $sourceRoot 'showcase_presentation.v'),(Join-Path $simRoot 'tb_showcase_video.v'))
    IncludeDir=@($sourceRoot,(Join-Path $sourceRoot 'SD'))
}

$tests += [pscustomobject]@{
    Name='showcase commit';Top='tb_showcase_commit';Marker='SHOWCASE_COMMIT_TEST_PASS'
    Sources=@($audioLinkSources)+@((Join-Path $sourceRoot 'presentation_control.v'),
        (Join-Path $sourceRoot 'scene_notice.v'),(Join-Path $simRoot 'tb_showcase_commit.v'))
    IncludeDir=$sourceRoot
}

$compactSources=@(($tests | Where-Object {$_.Top -eq 'tb_showcase_video'}).Sources |
    Where-Object {$_ -ne (Join-Path $simRoot 'tb_showcase_video.v')})
foreach($compact in @(
    @{Name='compact notice';Top='tb_compact_notice';Marker='COMPACT_NOTICE_TEST_PASS'},
    @{Name='compact layout';Top='tb_compact_layout';Marker='COMPACT_LAYOUT_TEST_PASS'}
)) {
    $tests += [pscustomobject]@{
        Name=$compact.Name;Top=$compact.Top;Marker=$compact.Marker
        Sources=$compactSources+@((Join-Path $simRoot ($compact.Top+'.v')))
        IncludeDir=@($sourceRoot,(Join-Path $sourceRoot 'SD'))
    }
}

foreach($uiTest in @(
    @{Name='transparent osd';Top='tb_transparent_osd';Marker='TRANSPARENT_OSD_TEST_PASS'},
    @{Name='bottom scroll';Top='tb_bottom_scroll';Marker='BOTTOM_SCROLL_TEST_PASS'}
)) {
    $uiSources=$compactSources+@((Join-Path $simRoot ($uiTest.Top+'.v')))
    if($uiTest.Top -eq 'tb_transparent_osd'){$uiSources+=@((Join-Path $simRoot 'models\showcase_ui_compact_baseline.v'),
        (Join-Path $simRoot 'models\showcase_ui_pre_palette.v'))}
    $tests += [pscustomobject]@{
        Name=$uiTest.Name;Top=$uiTest.Top;Marker=$uiTest.Marker;Sources=$uiSources
        IncludeDir=@($sourceRoot,(Join-Path $sourceRoot 'SD'))
    }
}

# Added observers do not replace, filter or weaken any historical fixture.
$tests += [pscustomobject]@{
    Name='playback progress';Top='tb_playback_progress';Marker='PLAYBACK_PROGRESS_TEST_PASS'
    Sources=@((Join-Path $sourceRoot 'SD\sd_card_bmp.v'),(Join-Path $sourceRoot 'playback_interval_control.v'),
        (Join-Path $sourceRoot 'osd_status_cdc.v'),(Join-Path $sourceRoot 'playback_progress_overlay.v'),
        (Join-Path $simRoot 'tb_playback_progress.v'));IncludeDir=$sourceRoot
}
$tests += [pscustomobject]@{
    Name='playback progress exact';Top='tb_playback_progress_exact';Marker='PLAYBACK_PROGRESS_TEST_PASS'
    Sources=($tests | Where-Object Name -eq 'playback progress').Sources;IncludeDir=$sourceRoot
}
$transitionSources=@('frame_completion_guard.v','fade_transition_cdc.v','fade_transition_ctrl.v',
    'video_fade.v','picture_transition.v','image_audio_cdc.v','image_melody_i2s.v') | ForEach-Object {Join-Path $sourceRoot $_}
$tests += [pscustomobject]@{
    Name='picture transitions';Top='tb_picture_transitions';Marker='PICTURE_TRANSITIONS_TEST_PASS'
    Sources=@($transitionSources)+@((Join-Path $simRoot 'tb_picture_transitions.v'));IncludeDir=$sourceRoot
}
$tests += [pscustomobject]@{
    Name='advanced video';Top='tb_advanced_video';Marker='ADVANCED_VIDEO_TEST_PASS'
    Sources=@(($compactSources+@($transitionSources)+@((Join-Path $sourceRoot 'SD\sd_card_bmp.v'),
        (Join-Path $sourceRoot 'playback_interval_control.v'),(Join-Path $sourceRoot 'playback_progress_overlay.v'),
        (Join-Path $simRoot 'tb_advanced_video.v'))) | Select-Object -Unique)
    IncludeDir=@($sourceRoot,(Join-Path $sourceRoot 'SD'))
}

$recoverySources=@('SD\sd_card_bmp.v','SD\bmp_read.v','sd_sector_buffer.v','bmp_pixel_decoder.v',
    'image_scaler.v','frame_completion_guard.v','debug_status.v','playback_interval_control.v',
    'IP\afifo_16_32_256.v','IP\afifo_32_16_256.v','SD\frame_fifo_read.v','SD\frame_fifo_write.v',
    'SD\frame_read_write.v','fade_transition_cdc.v','fade_transition_ctrl.v','video_fade.v',
    'picture_transition.v','image_audio_cdc.v','image_melody_i2s.v') | ForEach-Object {Join-Path $sourceRoot $_}
$tests += [pscustomobject]@{
    Name='playback recovery';Top='tb_playback_recovery';Marker='PLAYBACK_RECOVERY_TEST_PASS'
    Sources=@($recoverySources)+@((Join-Path $simRoot 'tb_playback_recovery.v'));IncludeDir=$sourceRoot
}
$tests += [pscustomobject]@{
    Name='playback error osd';Top='tb_playback_error_osd';Marker='PLAYBACK_ERROR_OSD_TEST_PASS'
    Sources=@($compactSources)+@((Join-Path $simRoot 'tb_playback_error_osd.v'));IncludeDir=@($sourceRoot,$simRoot)
}

$progressSceneSources=@('SD\sd_card_bmp.v','SD\bmp_read.v','sd_sector_buffer.v','bmp_pixel_decoder.v',
    'image_scaler.v','frame_completion_guard.v','debug_status.v','playback_interval_control.v',
    'fade_transition_cdc.v','fade_transition_ctrl.v','video_fade.v','picture_transition.v',
    'osd_status_cdc.v','playback_progress_display.v') | ForEach-Object {Join-Path $sourceRoot $_}
foreach($progressTop in 'tb_progress_commit_sync','tb_progress_commit_shift'){
    $tests += [pscustomobject]@{
        Name=if($progressTop -eq 'tb_progress_commit_sync'){'progress commit sync'}else{'progress commit shifted'}
        Top=$progressTop;Marker='PROGRESS_COMMIT_SYNC_TEST_PASS'
        Sources=@($progressSceneSources)+@((Join-Path $simRoot 'tb_progress_commit_sync.v'));IncludeDir=$sourceRoot
    }
}
$tests += [pscustomobject]@{
    Name='osd progress full raster';Top='tb_osd_progress_polish';Marker='OSD_PROGRESS_POLISH_TEST_PASS'
    Sources=@(($progressSceneSources+$compactSources+@((Join-Path $sourceRoot 'playback_progress_overlay.v'),
        (Join-Path $simRoot 'tb_progress_commit_sync.v'),(Join-Path $simRoot 'tb_osd_progress_polish.v'))) | Select-Object -Unique)
    IncludeDir=@($sourceRoot,(Join-Path $sourceRoot 'SD'),$simRoot)
}
$tests += [pscustomobject]@{
    Name='two alternating transitions';Top='tb_two_transitions';Marker='TWO_TRANSITIONS_TEST_PASS'
    Sources=@($progressSceneSources)+@((Join-Path $simRoot 'tb_progress_commit_sync.v'),(Join-Path $simRoot 'tb_two_transitions.v'))
    IncludeDir=$sourceRoot
}
$tests += [pscustomobject]@{
    Name='tourism video';Top='tb_tourism_video';Marker='TOURISM_VIDEO_TEST_PASS'
    Sources=@(($progressSceneSources+$compactSources+@((Join-Path $sourceRoot 'playback_progress_overlay.v'),
        (Join-Path $simRoot 'tb_progress_commit_sync.v'),(Join-Path $simRoot 'tb_tourism_video.v'))) | Select-Object -Unique)
    IncludeDir=@($sourceRoot,(Join-Path $sourceRoot 'SD'),$simRoot)
}
$tests += [pscustomobject]@{
    Name='tourism input compatibility';Top='tb_tourism_input_gate';Marker='TOURISM_INPUT_GATE_TEST_PASS'
    Sources=@((Join-Path $sourceRoot 'SD\bmp_read.v'),(Join-Path $sourceRoot 'sd_sector_buffer.v'),
        (Join-Path $sourceRoot 'bmp_pixel_decoder.v'),(Join-Path $simRoot 'tb_tourism_input_gate.v'))
    IncludeDir=$sourceRoot
}

if ($TestName) {
    $tests = @($tests | Where-Object { $_.Name -in $TestName })
    if ($tests.Count -eq 0) { throw 'No matching tests selected' }
}

$buildRoot = Join-Path $simRoot 'build'
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
$results = @()
$startedAt = Get-Date -Format o

foreach ($test in $tests) {
    $safeName = $test.Top
    $caseDir = Join-Path $buildRoot $safeName
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    Push-Location $caseDir
    try {
        $library = Join-Path $caseDir 'work'
        if (-not (Test-Path -LiteralPath $library)) {
            & $vlib $library | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "vlib failed for $($test.Name)" }
        }

        $compileArgs = @('-sv', '-work', 'work')
        if ($test.IncludeDir) {
            foreach ($includePath in @($test.IncludeDir)) {
                $compileArgs += "+incdir+$includePath"
            }
        }
        $compileArgs += $test.Sources
        # sd_card_bmp now instantiates the interval controller. Keep all old
        # protocol fixtures and their original one-second default unchanged.
        if (($test.Sources -contains (Join-Path $sourceRoot 'SD\sd_card_bmp.v')) -and
            ($test.Sources -notcontains (Join-Path $sourceRoot 'playback_interval_control.v'))) {
            $compileArgs += (Join-Path $sourceRoot 'playback_interval_control.v')
        }
        $compileLog = Join-Path $caseDir 'compile.log'
        $compileOutput = & $vlog @compileArgs 2>&1 | Tee-Object -FilePath $compileLog
        $compileExit = $LASTEXITCODE

        if ($compileExit -ne 0) {
            $results += [pscustomobject]@{ Name=$test.Name; Passed=$false; Detail='compile failed' }
            Write-Host "FAIL $($test.Name) (compile)"
            continue
        }

        $runLog = Join-Path $caseDir 'run.log'
        $runOutput = & $vsim -c "work.$($test.Top)" -do 'run -all; quit -f' 2>&1 | Tee-Object -FilePath $runLog
        $runExit = $LASTEXITCODE
        $joined = ($runOutput | Out-String)
        $passed = ($runExit -eq 0) -and $joined.Contains($test.Marker)
        $results += [pscustomobject]@{
            Name=$test.Name; Passed=$passed
            Detail=if ($passed) { $test.Marker } else { "run failed or PASS marker absent (exit=$runExit)" }
        }
        if ($passed) { Write-Host "PASS $($test.Name)" } else { Write-Host "FAIL $($test.Name)" }
        $transparentFaults=switch($test.Top){
            'tb_transparent_osd' {@('OPAQUE_TOP','FADE_FLASH','TOP_OUTLINE','TOP_WHITE')}
            'tb_bottom_scroll' {@('SCROLL_RESTART')}
            default {@()}
        }
        if($passed){foreach($fault in $transparentFaults){
            $faultOutput=& $vsim -c "work.$($test.Top)" "+INJECT_$fault" -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir "negative_$fault.log")
            $faultText=$faultOutput | Out-String
            $caught=$faultText.Contains('TRANSPARENT_CHECKER_REJECT') -and -not $faultText.Contains($test.Marker)
            $results += [pscustomobject]@{Name="negative transparent $fault";Passed=$caught;Detail='actual old-RTL/outline/scroll fault must be rejected'}
            if($caught){Write-Host "PASS negative transparent $fault"}else{Write-Host "FAIL negative transparent $fault"}
        }}
        $compactFaults = switch($test.Top) {
            'tb_compact_notice' {@('HINT_STUCK','PROMPT_FLICKER')}
            'tb_compact_layout' {@('CENTRE_PLATE','SUB_SHADOW')}
            default {@()}
        }
        if($passed) {foreach($fault in $compactFaults) {
            $faultOutput=& $vsim -c "work.$($test.Top)" "+INJECT_$fault" -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir "negative_$fault.log")
            $faultText=$faultOutput | Out-String
            $caught=$faultText.Contains('COMPACT_CHECKER_REJECT') -and -not $faultText.Contains($test.Marker)
            $results += [pscustomobject]@{Name="negative compact $fault";Passed=$caught;Detail='compact checker must reject injected fault'}
            if($caught){Write-Host "PASS negative compact $fault"}else{Write-Host "FAIL negative compact $fault"}
        }}
        $showcaseFaults = switch ($test.Top) {
            'tb_melody_status' { @('VIS_STEP','VIS_MELODY') }
            'tb_scene_notice' { @('NOTICE_EARLY') }
            'tb_showcase_video' { @('VIS_HIDDEN') }
            default { @() }
        }
        if ($passed) { foreach ($fault in $showcaseFaults) {
            $faultOutput = & $vsim -c "work.$($test.Top)" "+INJECT_$fault" -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir "negative_$fault.log")
            $faultText=$faultOutput | Out-String
            $caught=$faultText.Contains('SHOWCASE_CHECKER_REJECT') -and -not $faultText.Contains($test.Marker)
            $results += [pscustomobject]@{Name="negative showcase $fault";Passed=$caught;Detail='injected showcase fault must be rejected'}
            if ($caught) { Write-Host "PASS negative showcase $fault" } else { Write-Host "FAIL negative showcase $fault" }
        } }
        $interactionFault = switch ($test.Top) {
            'tb_playback_interval' { 'INTERVAL' }
            'tb_presentation_control' { 'PRESET' }
            'tb_interaction_osd' { 'OSD_STATUS' }
            'tb_presentation_video' { 'LAYER' }
            'tb_interaction_link' { 'AUTO_BUSY' }
            default { $null }
        }
        if ($passed -and $interactionFault) {
            $faultOutput = & $vsim -c "work.$($test.Top)" "+INJECT_$interactionFault" -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir "negative_$interactionFault.log")
            $faultText = $faultOutput | Out-String
            $caught = $faultText.Contains('INTERACTION_CHECKER_REJECT') -and -not $faultText.Contains($test.Marker)
            $results += [pscustomobject]@{ Name="negative interaction $interactionFault"; Passed=$caught; Detail='injected interaction fault must be rejected' }
            if ($caught) { Write-Host "PASS negative interaction $interactionFault" } else { Write-Host "FAIL negative interaction $interactionFault" }
        }
        if ($passed -and $test.Top -eq 'tb_image_audio_link') {
            $faultOutput = & $vsim -c "work.$($test.Top)" '+INJECT_AUDIO_BINDING' -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir 'negative_BINDING.log')
            $faultText = $faultOutput | Out-String
            $caught = $faultText.Contains('IMAGE_AUDIO_CHECKER_REJECT') -and -not $faultText.Contains($test.Marker)
            $results += [pscustomobject]@{ Name='negative image BINDING'; Passed=$caught; Detail='wrong melody binding must be rejected' }
            if ($caught) { Write-Host 'PASS negative image BINDING (checker rejected fault)' }
            else { Write-Host 'FAIL negative image BINDING' }
        }
        if ($passed -and $test.Top -eq 'tb_image_melody') {
            $faultOutput = & $vsim -c "work.$($test.Top)" '+INJECT_MELODY_PITCH' -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir 'negative_PITCH.log')
            $faultText = $faultOutput | Out-String
            $caught = $faultText.Contains('IMAGE_AUDIO_CHECKER_REJECT') -and -not $faultText.Contains($test.Marker)
            $results += [pscustomobject]@{ Name='negative melody PITCH'; Passed=$caught; Detail='wrong pitch must be rejected' }
            if ($caught) { Write-Host 'PASS negative melody PITCH (checker rejected fault)' }
            else { Write-Host 'FAIL negative melody PITCH' }
        }
        $advancedFaults=switch($test.Top){
            'tb_playback_progress' {@('PROGRESS_DESYNC','PROGRESS_LAYER')}
            'tb_picture_transitions' {@('EARLY_COMMIT','MASK_LEAK')}
            'tb_advanced_video' {@('VIDEO_ALIGNMENT')}
            default {@()}
        }
        if($passed){foreach($advancedFault in $advancedFaults){
            $faultOutput=& $vsim -c "work.$($test.Top)" "+INJECT_$advancedFault" -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir "negative_$advancedFault.log")
            $faultText=$faultOutput | Out-String
            $caught=$faultText.Contains('ADVANCED_CHECKER_REJECT') -and !$faultText.Contains($test.Marker)
            $results += [pscustomobject]@{Name="negative advanced $advancedFault";Passed=$caught;Detail='new feature fault must be detected'}
            Write-Host "$(if($caught){'PASS'}else{'FAIL'}) negative advanced $advancedFault"
        }}
        if($passed -and $test.Top -eq 'tb_progress_commit_sync'){
            foreach($polishFault in 'HOLD_DROP','RESET_AT_COMMIT','STALE_BAR'){
                $faultOutput=& $vsim -c "work.$($test.Top)" "+INJECT_$polishFault" -do 'run -all; quit -f' 2>&1 |
                    Tee-Object -FilePath (Join-Path $caseDir "negative_$polishFault.log")
                $faultText=$faultOutput | Out-String
                $caught=$faultText.Contains('POLISH_CHECKER_REJECT') -and !$faultText.Contains($test.Marker)
                $results += [pscustomobject]@{Name="negative polish $polishFault";Passed=$caught;Detail='visual lifecycle fault must be rejected'}
                Write-Host "$(if($caught){'PASS'}else{'FAIL'}) negative polish $polishFault"
            }
        }
        $recoveryFaults=switch($test.Top){
            'tb_playback_recovery' {@('BAD_COMMIT','BAD_SKIP','RECOVERY_DEADLOCK','READY_CANCEL_RACE')}
            'tb_playback_error_osd' {@('ERROR_PLATE','ERROR_GLYPH')}
            default {@()}
        }
        $tourismFaults=switch($test.Top){
            'tb_two_transitions' {@('ALTERNATE','EARLY_ALTERNATE','FAILED_ALTERNATE')}
            'tb_tourism_video' {@('SCENE_TEXT')}
            'tb_tourism_input_gate' {@('INPUT_ACCEPT')}
            default {@()}
        }
        if($passed){foreach($tourismFault in $tourismFaults){
            $faultOutput=& $vsim -c "work.$($test.Top)" "+INJECT_$tourismFault" -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir "negative_$tourismFault.log")
            $faultText=$faultOutput | Out-String
            $caught=$faultText.Contains('CHECKER_REJECT') -and !$faultText.Contains($test.Marker)
            $results += [pscustomobject]@{Name="negative tourism $tourismFault";Passed=$caught;Detail='independent checker rejects incorrect effect/event/text'}
            Write-Host "$(if($caught){'PASS'}else{'FAIL'}) negative tourism $tourismFault"
        }}
        if($passed){foreach($recoveryFault in $recoveryFaults){
            $faultOutput=& $vsim -c "work.$($test.Top)" "+INJECT_$recoveryFault" -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir "negative_$recoveryFault.log")
            $faultText=$faultOutput | Out-String
            $caught=$faultText.Contains('RECOVERY_CHECKER_REJECT') -and !$faultText.Contains($test.Marker)
            $results += [pscustomobject]@{Name="negative recovery $recoveryFault";Passed=$caught;Detail='recovery checker must reject fault'}
            Write-Host "$(if($caught){'PASS'}else{'FAIL'}) negative recovery $recoveryFault"
        }}
        if ($passed -and $test.Top -eq 'tb_image_scaling') {
            foreach ($fault in @('PIXEL', 'COORD', 'COUNT')) {
                $negativeOutput = & $vsim -c "work.$($test.Top)" "+INJECT_$fault" -do 'run -all; quit -f' 2>&1 |
                    Tee-Object -FilePath (Join-Path $caseDir "negative_$fault.log")
                $negativeText = $negativeOutput | Out-String
                $caught = $negativeText.Contains('SCALING_CHECKER_REJECT') -and -not $negativeText.Contains($test.Marker)
                $results += [pscustomobject]@{ Name="negative $fault"; Passed=$caught; Detail='injected fault must be rejected' }
                if ($caught) { Write-Host "PASS negative $fault (checker rejected fault)" }
                else { Write-Host "FAIL negative $fault" }
            }
        }
        if ($passed -and $test.Top -eq 'tb_audio_wave_capture') {
            $faultOutput = & $vsim -c "work.$($test.Top)" '+INJECT_SIGN' -do 'run -all; quit -f' 2>&1 |
                Tee-Object -FilePath (Join-Path $caseDir 'negative_SIGN.log')
            $faultText = $faultOutput | Out-String
            $caught = $faultText.Contains('AUDIO_WAVE_CHECKER_REJECT') -and -not $faultText.Contains($test.Marker)
            $results += [pscustomobject]@{ Name='negative audio SIGN'; Passed=$caught; Detail='injected sign fault must be rejected' }
            if ($caught) { Write-Host 'PASS negative audio SIGN (checker rejected fault)' }
            else { Write-Host 'FAIL negative audio SIGN' }
        }
        if ($passed -and $test.Top -eq 'tb_dynamic_subtitle') {
            foreach ($fault in @('PIXEL', 'SCROLL')) {
                $faultOutput = & $vsim -c "work.$($test.Top)" "+INJECT_SUBTITLE_$fault" -do 'run -all; quit -f' 2>&1 |
                    Tee-Object -FilePath (Join-Path $caseDir "negative_$fault.log")
                $faultText = $faultOutput | Out-String
                $caught = $faultText.Contains('SUBTITLE_CHECKER_REJECT') -and -not $faultText.Contains($test.Marker)
                $results += [pscustomobject]@{ Name="negative subtitle $fault"; Passed=$caught; Detail='injected subtitle fault must be rejected' }
                if ($caught) { Write-Host "PASS negative subtitle $fault (checker rejected fault)" }
                else { Write-Host "FAIL negative subtitle $fault" }
            }
        }
        if ($passed -and $test.Top -eq 'tb_sd_scan_timing') {
            foreach ($fault in @('ADVANCE', 'BOUNDARY')) {
                $faultOutput = & $vsim -c "work.$($test.Top)" "+INJECT_SCAN_$fault" -do 'run -all; quit -f' 2>&1 |
                    Tee-Object -FilePath (Join-Path $caseDir "negative_$fault.log")
                $faultText = $faultOutput | Out-String
                $caught = $faultText.Contains('SD_SCAN_CHECKER_REJECT') -and -not $faultText.Contains($test.Marker)
                $results += [pscustomobject]@{ Name="negative scan $fault"; Passed=$caught; Detail='injected scan fault must be rejected' }
                if ($caught) { Write-Host "PASS negative scan $fault (checker rejected fault)" }
                else { Write-Host "FAIL negative scan $fault" }
            }
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host ''
Write-Host 'Regression summary:'
foreach ($result in $results) {
    $label = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    Write-Host "$label $($result.Name) - $($result.Detail)"
}

$record = [pscustomobject]@{
    StartedAt=$startedAt; FinishedAt=(Get-Date -Format o)
    Simulator=$vsim; SelectedTests=$TestName; Results=$results
    SourceHashes=@(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse | ForEach-Object {
        [pscustomobject]@{ Path=$_.FullName.Substring($sourceRoot.Length+1); SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
}
$record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $buildRoot 'regression_summary.json') -Encoding UTF8
if (($results | Where-Object { -not $_.Passed }).Count -ne 0) {
    exit 1
}
exit 0
