if object_id('finance_reps_inputs2') is not null drop proc finance_reps_inputs2
go
-- exec finance_reps_inputs2 700, 8161
create proc [finance_reps_inputs2]
	@mol_id int,
	@folder_id int,
	@d_from datetime = null,
	@d_to datetime = null
as
begin

	set nocount on;

	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'fd'

-- access
	declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @budgets as app_pkids; insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
	declare @all_budgets bit =
		case 
			when exists(select 1 from @budgets where id = -1) 
				and not exists(select 1 from @budgets where id <> -1)
			then 1 
			else 0 
		end

	if @all_budgets = 0
	begin
		raiserror('Для данного отчёта необходим доступ ко всем бюджетам (в рамках субъекта учёта).', 16, 1)
		return
	end

-- #result
	create table #result(
		ACTIVE_TYPE VARCHAR(30),
		MFR_NAME VARCHAR(100),
		DIRECTION_NAME VARCHAR(100),
		MOL_NAME VARCHAR(50),
		D_DOC DATETIME,
		AGENT_NAME VARCHAR(250),
		DEAL_NAME VARCHAR(50),
		FINDOC_ID INT,
		DEAL_ID INT,
		PROJECT_ID INT,
		VALUE_IN DECIMAL(18,2)
		)

	insert into #result(
		active_type,
		mfr_name, direction_name, mol_name, d_doc, agent_name, deal_name,
		findoc_id, deal_id, project_id,
		value_in
		)
	select 
		case
			when p.TYPE_ID = 1 then '1.Проекты'
			else '2.Тек.деятельность'
		end,
		isnull(d.mfr_name,'-'),
		coalesce(dir.short_name, dir.name, '-'),
		coalesce(mols.name, m2.name, '-'),
		f.d_doc,
		ag.name,
		isnull(d.number, p.name),
		f.findoc_id,
		d.deal_id,
		p.project_id,
		f.value_rur
	from v_findocs f
		join @subjects s on s.id = f.subject_id
		join budgets b on b.budget_id = f.budget_id
			left join projects p on p.project_id = b.project_id
				left join mols m2 on m2.mol_id = p.chief_id
		left join deals d on d.budget_id = f.budget_id
			left join depts dir on dir.dept_id = d.direction_id
			left join mols on mols.mol_id = d.manager_id
		left join agents ag on ag.agent_id = f.agent_id
	where f.article_id = 24
		and f.findoc_id in (select id from @ids)

-- final
	select * from #result
	drop table #result
end
GO
