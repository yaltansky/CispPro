if object_id('mfr_opers_layer_calc') is not null drop proc mfr_opers_layer_calc
go
-- exec mfr_opers_layer_calc 1000
create proc [mfr_opers_layer_calc]
	@mol_id int,
	@trace bit = 0
as
begin

	set nocount on;

	if dbo.isinrole(@mol_id, 'admin,mfr.admin') = 0
	begin
		raiserror('У Вас нет доступа для расчёта плана производства.', 16, 1)
		return
	end

begin
	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
		' @mol_id=', @mol_id
		)
	exec tracer_log @tid, @tid_msg
end -- prepare

	update x set d_to_predict = isnull(x.d_to_plan, xx.d_to_predict)
	from sdocs_mfr_milestones x
		join (
			select o.mfr_doc_id, o.milestone_id, max(o.d_to_predict) as d_to_predict
			from sdocs_mfr_opers o
				join sdocs_mfr mfr on mfr.doc_id = o.mfr_doc_id
					join mfr_plans pl on pl.plan_id = mfr.plan_id and pl.status_id = 1
			group by o.mfr_doc_id, o.milestone_id
		) xx on xx.mfr_doc_id = x.doc_id and xx.milestone_id = x.attr_id
	
-- close log
	exec tracer_close @tid
	if @trace = 1 exec tracer_view @tid
end
GO
