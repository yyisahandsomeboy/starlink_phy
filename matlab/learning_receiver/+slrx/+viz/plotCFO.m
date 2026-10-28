function [fig, info] = plotCFO(context, options)
%PLOTCFO 运算说明、同参考诊断和后续EVAL证据分开；从已保存时间轴计算。
info=slrx.diag.cfoMetrics(context);available=find([info.rounds.available]);
fig=slrx.viz.newFigure('CFO：复数旋转、真实时间轴与参考诊断',options.show_figures);fig.Position=[30 30 1650 1080];
layout=tiledlayout(fig,2,3,'TileSpacing','compact');layout.OuterPosition=[0 .12 1 .82];
if isempty(available),ax=nexttile(layout);axis(ax,'off');text(ax,.05,.5,'尚无取帧数据，CFO观测不可用');return;end
selected=available(end);
if isfield(options,'cfo_round')&&~isempty(options.cfo_round)
    assert(ismember(options.cfo_round,available),'slrx:CFORound','所选轮次尚无取帧数据');selected=options.cfo_round;
end
menu=uicontrol(fig,'Style','popupmenu','Units','normalized','Position',[.02 .956 .33 .03], ...
    'String',compose('第%d轮CFO观测',available),'Value',find(available==selected), ...
    'Tag','slrx-cfo-round','Callback',@redraw);
redraw(menu,[]);
    function redraw(control,~)
        pass=available(control.Value);d=info.rounds(pass);
        delete(findall(layout,'Type','axes'));
        for p=1:2
            ax=nexttile(layout,p);
            if numel(d.points)<p,axis(ax,'off');text(ax,.05,.5,'没有合适的非零参考采样');continue;end
            point=d.points(p);a=point.before;b=point.after;
            quiver(ax,0,0,real(a),imag(a),0,'LineWidth',1.5,'DisplayName','补偿前');hold(ax,'on');
            quiver(ax,0,0,real(b),imag(b),0,'LineWidth',1.5,'DisplayName','补偿后');
            arc=linspace(angle(a),angle(a)+point.principal_applied_phase_rad,60);
            plot(ax,.6*abs(a)*cos(arc),.6*abs(a)*sin(arc),'k:','HandleVisibility','off');
            axis(ax,'equal');grid(ax,'on');limit=max(abs([a b]))*1.4;axis(ax,[-limit limit -limit limit]);
            xlabel(ax,'I / 归一化幅度');ylabel(ax,'Q / 归一化幅度');legend(ax,'Location','best');
            title(ax,sprintf(['运算示例：帧内第%d点，t=%.6fus\n累计a=%.4frad；图示主值夹角=%.2f°\n' ...
                '|z| %.8g → %.8g'],point.frame_index_1based,point.time_us,point.applied_phase_rad, ...
                point.principal_applied_phase_rad*180/pi,point.magnitude_before,point.magnitude_after),'FontSize',10);
        end
        ax=nexttile(layout,3);plot(ax,d.time_us,d.applied_phase_rad,'LineWidth',1.3);grid(ax,'on');
        xlabel(ax,'实际帧内时间 / us（含SFO取样调整）');ylabel(ax,'施加的累计角a / rad');
        title(ax,sprintf('施加的变换，不是估计误差\nf=%.9gHz；%s；每点Δa≈%.7grad\n首/末=%.6g / %.6grad', ...
            d.cfo_hz,d.rotation_direction,d.phase_increment_rad,d.first_last_phase_rad));
        for g=1:2
            ax=nexttile(layout,g+3);hold(ax,'on');group=d.reference_groups(g);
            for family=unique(group.family)
                index=group.family==family;
                plot(ax,group.time_us(index),group.before.phase_rad(index),'o','Color',[.05 .35 .8], ...
                    'DisplayName',sprintf('前/族%d',family),'MarkerSize',4);
                plot(ax,group.time_us(index),group.after.phase_rad(index),'s','Color',[.85 .3 .05], ...
                    'DisplayName',sprintf('后/族%d',family),'MarkerSize',4);
                plot(ax,group.time_us(index),group.before.fitted_phase_rad(index),'--','Color',[.05 .35 .8],'HandleVisibility','off');
                plot(ax,group.time_us(index),group.after.fitted_phase_rad(index),'--','Color',[.85 .3 .05],'HandleVisibility','off');
            end
            grid(ax,'on');xlabel(ax,'实际参考块中心时间 / us');ylabel(ax,'分结构/族展开参考相位 / rad');legend(ax,'Location','best','FontSize',8);
            title(ax,sprintf(['%s同参考诊断（非独立）\n斜率代理 %.5g → %.5g Hz；显示门限=%d/%d\n' ...
                '去趋势RMS %.4g → %.4grad'],group.name,group.before.frequency_hz,group.after.frequency_hz, ...
                group.before.proxy_available,group.after.proxy_available,group.before.residual_rms_rad,group.after.residual_rms_rad),'FontSize',10);
        end
        ax=nexttile(layout,6);axis(ax,'off');lines={sprintf('第%d轮实际施加CFO = %.9f Hz',pass,d.cfo_hz), ...
            sprintf('模长相对误差=%.3g；运算一致性误差=%.3g',d.magnitude_relative_error,d.operation_relative_error), ...
            'PSS/SSS参与原CFO估计，相关增强不是独立验证。', ...
            '64点块不跨CP/结构；PSS按128重复段内半块分族。', ...
            '斜率仅在近似稳定参考信道、相位无混叠时解释。', ...
            '去趋势残差可保持不变，不能要求补偿后必然降低。'};
        records=info.heldout.records((pass-1)*3+(1:3));
        if any([records.available])
            lines{end+1}=sprintf('后续EVAL EVM（FFT/均衡/跟踪）= %s %%',mat2str(100*[records.calibrated_evm],5));
            lines{end+1}='这些阶段均已补偿CFO，且包含其他处理；不是仅CFO的因果对照。';
        else,lines{end+1}='本步尚无FFT/EVAL；后续阶段补充验证，不提前运行。';end
        text(ax,0,1,strjoin(lines,newline),'VerticalAlignment','top','FontSize',10,'Interpreter','none');
        sgtitle(layout,sprintf('第%d轮：输入z → 施加exp(ja) → 已知参考诊断 → 后续留出观测；不以旋转公式证明估计正确',pass),'FontSize',12);
        previous=fig.UserData;fig.UserData=struct('diagnostic','cfo','selected_round',pass,'info',info);
        if isstruct(previous)&&isfield(previous,'teaching_notes'),fig.UserData.teaching_notes=previous.teaching_notes;end
    end
end
