if object_id('projects_resources_search') is not null drop proc projects_resources_search
go
create proc projects_resources_search
	@tree_id int = null,
	@search varchar(32) = null,
	@type_id int = null,
	@mol_id int = null,
	@context varchar(max) = null
as
begin

	set nocount on;

	declare @result table(resource_id int)

	set @search = '%' + replace(@search, ' ', '%') + '%'

-- @tree_id
	if @tree_id is not null	
		insert into @result(resource_id)
		select distinct resource_id from projects_resources_limits where tree_id = @tree_id
	else 
	begin
		-- @context
			declare @ids app_pkids
			declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
			declare @buffer as app_pkids

		-- Очередь сменных заданий
		if @context = 'MfrJobsQueue'
		begin
			insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mco')
			
			if exists(select 1 from @buffer)
				insert into @ids
				select distinct os.resource_id from mfr_plans_jobs_queues q
					join @buffer i on i.id = q.detail_id
					join sdocs_mfr_contents c on c.content_id = q.content_id
					join sdocs_mfr_opers o on o.oper_id = q.oper_id
						join sdocs_mfr_drafts_opers o2 on o2.draft_id = c.draft_id and o2.number = o.number
							join sdocs_mfr_drafts_opers_resources os on os.oper_id = o2.oper_id
		end

		insert into @result(resource_id)
		select resource_id
		from projects_resources
		where (@search is null or name like @search)
			and (@type_id is null or type_id = @type_id)
			and (not exists(select 1 from @ids)
				or resource_id in (select id from @ids)
				)
	end

-- + parents
	;with tree as (
		select parent_id, resource_id from projects_resources where resource_id in (select resource_id from @result)
		union all
		select x.parent_id, x.resource_id
		from projects_resources x
			inner join tree on tree.parent_id = x.resource_id
		)
		insert into @result select resource_id from tree 
		where resource_id  not in (select resource_id from @result)


-- result
	select	
		l.TREE_ID,
		x.RESOURCE_ID,
		x.NAME,
		X.TYPE_ID,
		X.TYPE_NAME,
		x.AGGREGATION_ID,
		x.AGGREGATION_NAME,
		x.DISTRIBUTION_ID,
		x.DISTRIBUTION_NAME,
		x.DESCRIPTION,
		PRICE = isnull(l.PRICE, x.PRICE),
		LIMIT_Q = isnull(l.LIMIT_Q, x.LIMIT_Q),
		x.PARENT_ID, x.HAS_CHILDS, x.LEVEL_ID, x.IS_DELETED, x.SORT_ID,
		x.MOL_ID, x.ADD_DATE
	from v_projects_resources x
		left join projects_resources_limits l on l.tree_id = @tree_id and l.resource_id = x.resource_id
	where x.resource_id in (select resource_id from @result)
		and x.resource_id <> 0 -- empty resource
	order by x.node
end
GO

drop proc projects_resources_calc
go

create proc projects_resources_calc
as
begin
	exec tree_calc_nodes 'projects_resources', 'resource_id', @sortable = 0
end
GO
