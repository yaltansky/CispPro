if object_id('projects_pivots_resources') is not null drop proc projects_pivots_resources
go
-- exec projects_pivots_resources 1000, -1
create proc projects_pivots_resources
	@mol_id int,
	@folder_id int
as
begin

	set nocount on;

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

    -- @ids
        declare @ids as app_pkids
        insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'prj'

    -- final
        select
            project_name = p.name,
            resource_name = rs.name,
            month_name = concat(year(x.d_doc), '-', right(concat('00', month(x.d_doc)), 2)),
            week_name = isnull(datepart(iso_week, x.d_doc), '-'),
            x.d_doc,
            task_name = t.name,
            executor_name = mols.name,
            x.limit_q, x.limit_v,
            x.plan_q, x.plan_v,
            x.fact_q, x.fact_v
        from projects_resources_az x
            join projects p on p.project_id = x.project_id
            join projects_resources rs on rs.resource_id = x.resource_id
            left join projects_tasks t on t.task_id = x.task_id
            left join mols on mols.mol_id = x.mol_id
        where x.project_id in (select id from @ids)

end
go
