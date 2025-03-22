if object_id('project_tasks_calc_resources') is not null drop procedure project_tasks_calc_resources
go
create proc project_tasks_calc_resources
	@tree_id int = null, 
	@resource_id int = null,
	@d_from datetime = null,
	@d_to datetime = null	
as
begin

	set nocount on;

	create table #projects(project_id int primary key)

	if @tree_id is not null begin
        declare @node hierarchyid; select @node = node from trees where tree_id = @tree_id
	    insert into #projects select obj_id from trees where node.IsDescendantOf(@node) = 1 and obj_type = 'PRJ' and obj_id is not null
    end

    else
        insert into #projects select project_id from projects p
        where type_id = 1 and status_id between 0 and 4
            and exists(
                select 1 from projects_tasks_resources r
                    join projects_tasks pt on pt.task_id = r.task_id
                where pt.project_id = p.project_id
                )

	delete from projects_resources_charts where 
			project_id in (select project_id from #projects)
		and (@resource_id is null or resource_id = @resource_id)
		and (@d_from is null or d_doc >= @d_from)
		and (@d_to is null or d_doc <= @d_to)

	;with dates as (
		select t.task_id, d.day_date
		from projects_tasks t
			cross apply (
                select day_date = cast(day_date as date) from calendar where type = 0
                    and (@d_from is null or day_date >= @d_from)
                    and (@d_to is null or day_date <= @d_to)
                ) d 
		where t.project_id in (select project_id from #projects)
            and exists(select 1 from projects_tasks_resources where task_id = t.task_id)
			and t.is_deleted = 0
			and (d.day_date between cast(t.d_from as date) and cast(t.d_to as date))
		)

		, dates_count as (
			select task_id, count(*) as c_days from dates group by task_id
		)

		, chart as (
            select 
                t.project_id, rt.resource_id, rt.task_id, rt.id as task_resource_id, d.day_date,
                case
                    when r.aggregation_id = 1 then rt.quantity / dc.c_days
                    else rt.quantity
                end as quantity
            from projects_tasks_resources rt
                join projects_tasks t on t.task_id = rt.task_id
                    join dates as d on d.task_id = t.task_id
                    join dates_count as dc on dc.task_id = t.task_id
                join projects_resources r on r.resource_id = rt.resource_id		
            where t.project_id in (select project_id from #projects)
                and (@resource_id is null or rt.resource_id = @resource_id)
                and (@d_from is null or d.day_date >= @d_from)
                and (@d_to is null or d.day_date <= @d_to)
                and (t.duration > 0)
		)
		insert into projects_resources_charts(project_id, resource_id, task_id, task_resource_id, d_doc, quantity)
		select project_id, resource_id, task_id, task_resource_id, day_date, quantity
		from chart
	
    exec drop_temp_table '#projects'

end
GO
