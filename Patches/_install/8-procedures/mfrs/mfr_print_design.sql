if object_id('mfr_print_design') is not null drop proc mfr_print_design
go
-- exec mfr_print_design 700, @plan_id = 0, @place_id = 1
create proc mfr_print_design
	@mol_id int,
	@plan_id int = null,
	@folder_id int = null, -- папка планов
	@place_id int = null,
	@d_doc datetime = null
as
begin

	set nocount on;

	-- @plans
		declare @plans as app_pkids

		if @folder_id is not null set @plan_id = null

		if @plan_id = 0 
			insert into @plans select plan_id
			from mfr_plans where status_id = 1
		
		else if @plan_id is not null
			insert into @plans select @plan_id
		
		else
			insert into @plans
			exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfp'

	-- reglament access
		declare @objects as app_objects; insert into @objects	exec mfr_getobjects @mol_id = @mol_id
		declare @subjects as app_pkids;	insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
		
	-- dates
		set @d_doc = isnull(@d_doc, dbo.today())
		declare @period_id int = dbo.date2period(@d_doc)
		declare @d_from datetime = dateadd(d, -datepart(d, @d_doc)+1, @d_doc)
		declare @d_to datetime = dateadd(m, 1, @d_from) - 1

		declare @result table(
			RowId int identity,
			MfrNumber varchar(100),
			MfrPriority int,			
			AgentName varchar(250),
			Group1Name varchar(250),
			Group2Name varchar(250),
			ProductName varchar(250),
			ItemName varchar(250),
			OperName varchar(100),
			DateTo date,
			DateToPredict date,
			DateToFact date,
			PeriodFrom date,
			PeriodTo date,
			PlanHours float,
			FactHours float,
			PlanQ float,
			FactQ float
			)

		insert into @result(
			MfrNumber, MfrPriority,
			AgentName,			
			Group1Name, Group2Name, ProductName,
			ItemName, OperName,
			DateTo, DateToPredict, DateToFact,
			PlanHours, FactHours,
			PlanQ,
			FactQ
			)
		select
			MfrNumber, MfrPriority,
			AgentName,			
			Group1Name = PlaceName,
			Group2Name = ExecutorName,
			ProductName,
			ItemName, OperName,
			DateTo, DateToPredict, DateToFact,
			PlanHours, FactHours,
			PlanQ,
			case when DateToFact is not null then 1 end
		from (
			select 
				mfr.subject_id,
				mfr.plan_id,
				x.place_id,
				MfrNumber = mfr.number,
				MfrPriority = mfr.priority_id,
				AgentName = mfr.agent_name,
				ProductName = p2.name,
				PlaceName = concat(pl.name, ' ', pl.note),
				ItemName = p2.name,
				OperName = x.name,
				DateTo = x.d_to,
				DateToPredict = x.d_to_predict,
				DateToFact = x.d_to_fact,
				ExecutorName = mols.name,
				PlanHours = isnull(je.plan_duration_wk * dur1.factor / dur_h.factor, 0),
				FactHours = isnull(je.duration_wk * dur2.factor / dur_h.factor, 0),
				PlanQ = x.plan_q				
			from mfr_sdocs_opers x
				join mfr_sdocs mfr on mfr.doc_id = x.mfr_doc_id
				join mfr_plans_jobs_details jd on jd.oper_id = x.oper_id
					join mfr_plans_jobs j on j.plan_job_id = jd.plan_job_id
					join mfr_plans_jobs_executors je on je.detail_id = jd.id
						join mols on mols.mol_id = je.mol_id
						left join projects_durations dur1 on dur1.duration_id = je.plan_duration_wk_id
						left join projects_durations dur2 on dur2.duration_id = je.duration_wk_id
						join projects_durations dur_h on dur_h.duration_id = 2
				join products p on p.product_id = x.product_id
				join products p2 on p2.product_id = jd.item_id
				join mfr_places pl on pl.place_id = x.place_id
			) v
		where
			-- reglament access
			subject_id in (select id from @subjects)
			-- conditions
			and plan_id in (select id from @plans)
			and (
					-- Факт(до) в периоде
					DateToFact between @d_from and @d_to
					-- или (План в периоде и (Факт >= От или Пусто))
					or (DateTo <= @d_to and isnull(DateToFact, @d_from) >= @d_from)
				)
			and (@place_id is null or place_id = @place_id)

	update @result set PeriodFrom = @d_from, PeriodTo = @d_to

	select top 200 * from @result

end
go
