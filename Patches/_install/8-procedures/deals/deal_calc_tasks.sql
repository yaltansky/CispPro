if object_id('deal_calc_tasks') is not null drop procedure deal_calc_tasks
go
create proc deal_calc_tasks
	@mol_id int,
	@deal_id int = null,	
	@ids app_pkids readonly,
	@tid int = null	
as
begin
	
	set nocount on;

	declare @local_tid int

	if @tid is null
	begin
		exec tracer_init 'deal_calc_tasks', @trace_id = @tid out, @echo = 0
		set @local_tid = @tid
	end

-- @deals		
	declare @deals as app_pkids

	if @deal_id is not null insert into @deals values(@deal_id)
	else insert into @deals select id from @ids
	
-- remove duplicates (TEMP)
	delete t
	from projects_tasks t
		join (
			select t.project_id, t.name, min(t.task_id) as task_id
			from projects_tasks t
				join projects p on p.project_id = t.project_id and p.type_id = 3
			group by t.project_id, t.name
			having count(*) > 1
		) tt on tt.project_id = t.project_id and t.name = tt.name and t.task_id <> tt.task_id
	where t.project_id in (select id from @deals)

-- defaults
	declare @FINAL_NAME varchar(50) = 'Окончательный расчет';

exec tracer_log @tid, 'Calc projects_tasks.durations'
    declare @duration int

	update x
	set @duration = 
			isnull(
				nullif(
					case
						when meta.option_key = 'duration_manufacture' then d.duration_manufacture
						when meta.option_key = 'duration_delivery' then d.duration_delivery
						when meta.option_key = 'delivery_days_shipping' then d.delivery_days_shipping
						when meta.option_key = 'duration_reserveshipping' then d.duration_reserveshipping
					end
				, 0)					 
			, 1),
		duration = @duration,
		duration_input = @duration,
		duration_id = 3
	from projects_tasks x
		join deals d on d.deal_id = x.project_id
			join @deals i on i.id = d.deal_id
		join deals_meta_tasks meta on meta.task_name = x.name

exec tracer_log @tid, 'Check binds (deals_budgets.task_id)'
	update x
	set task_id = t.task_id
	from deals_budgets x
		join projects_tasks t on t.project_id = x.deal_id and t.name = x.task_name
	where x.deal_id in (select id from @deals)
		and t.is_deleted  = 0

	update x
	set task_id = t.task_id
	from deals_budgets x
		join projects_tasks t on t.project_id = x.deal_id and t.name = @final_name
	where x.deal_id in (select id from @deals)
		and not exists(select 1 from projects_tasks where project_id = x.deal_id and task_id = x.task_id and is_deleted = 0)
		
exec tracer_log @tid, 'Recalc projects tasks from DEALS.SPEC_DATE'
    update x set d_today = d.spec_date
    from projects x
        join deals d on d.deal_id = x.project_id
            join @deals i on i.id = d.deal_id

	-- place deals (as projects) into temp node of tree
	declare @tree_id int = (select top 1 tree_id from trees where type_id = 2 and name = @mol_id and parent_id is null)
	if @tree_id is null begin
		insert into trees(type_id, name) values(2, @mol_id)
		set @tree_id = @@identity
	end

	delete from trees where parent_id = @tree_id
	insert into trees(type_id, parent_id, name, obj_type, obj_id)
	select 2, @tree_id, concat('deal:', id), 'prj', id
	from @deals

    exec project_tasks_calc @tree_id = @tree_id, @mol_id = -25

-- task_name, task_date
	update x
	set task_name = t.name,
		task_date = dateadd(d, isnull(x.date_lag,0), t.d_to)
	from deals_budgets x
		join @deals i on i.id = x.deal_id
		join deals d on d.deal_id = x.deal_id
		join projects_tasks t on t.task_id = x.task_id

-- для НДС task_date = max(task_date) + 1
	update x
	set task_date = tmax.task_date + 1,
		date_lag = 1
	from deals_budgets x
		join @deals i on i.id = x.deal_id
		join bdr_articles a on a.article_id = x.article_id and short_name ='НДС'
		join (
			select deal_id, max(task_date) task_date
			from deals_budgets db
				join bdr_articles a on a.article_id = db.article_id
			where isnull(a.short_name, '') <> 'НДС'
			group by deal_id
		) tmax on tmax.deal_id = x.deal_id

	if @local_tid is not null
	begin
		exec tracer_close @local_tid
		exec tracer_view @local_tid
	end

end
go
