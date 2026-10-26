function equalized = equalizeGrid(grid, channel, refs)
%EQUALIZEGRID 第8步：撤销每个频率位置的信道幅度/相位变化。
% Z[k,m]=Y[k,m]/H[k]。本模型整帧用同一个SSS频率响应。
% 评价导频在本步骤不参与H拟合；保存均衡前后EVM作数值观察。

equalized.values = grid.values./channel.H;
equalized.frequency_bins = refs.frequency_bins;
receivedBefore = grid.values(refs.eval_rows,2:301);
receivedAfter = equalized.values(refs.eval_rows,2:301);
reference = refs.pilots(refs.eval_rows,2:301);
equalized.heldout_pilot_evm_before = sqrt(sum(abs(receivedBefore-reference).^2,'all')/sum(abs(reference).^2,'all'));
equalized.heldout_pilot_evm_after = sqrt(sum(abs(receivedAfter-reference).^2,'all')/sum(abs(reference).^2,'all'));
equalized.summary = struct('grid_size',size(equalized.values), ...
    'heldout_pilot_evm_before',equalized.heldout_pilot_evm_before, ...
    'heldout_pilot_evm_after',equalized.heldout_pilot_evm_after);
end
