function names = stepFigures(key)
%STEPFIGURES 步骤到诊断图的关联；文件名集中于此，不加载任何数据。
switch key
    case '01_capture', names={'00_capture.png'};
    case '02_resampled', names={'00b_resampling.png'};
    case '03_sync', names={'01_sync_global.png','02_sync_local.png'};
    case {'04_frame_time','13a_frame_time'},names={'05_cfo.png','06_sfo.png','07_ofdm_symbol.png','08_cp_copy.png'};
    case {'05_without_cp','13b_without_cp'},names={'07_ofdm_symbol.png','08_cp_copy.png'};
    case {'06_fft_grid','13c_fft_grid'},names={'09_fft_grid.png','03_constellation_stages.png','11_pilot_evm.png'};
    case {'07_channel','13d_channel'},names={'10_channel.png'};
    case {'08_equalized','13e_equalized'},names={'10_channel.png','03_constellation_stages.png','11_pilot_evm.png'};
    case {'09_pilot_observations','13f_pilots'},names={'11_pilot_evm.png','12_pilot_cloud.png','13_pilot_errors.png'};
    case {'10_cardinality','13g_cardinality','14_decisions'},names={'04_conditional_models.png'};
    case {'11_tracking','13h_tracking'},names={'11b_tracking.png','03_constellation_stages.png','11_pilot_evm.png','13_pilot_errors.png'};
    case '12_refined_offsets',names={'05_cfo.png','06_sfo.png'};
    case '15_guard',names={'14_guard.png'};
    otherwise,names={};
end
end
