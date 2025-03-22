if object_id('app_registry_view') is not null drop proc app_registry_view
go
create proc app_registry_view
	@parent_id int = null,
	@search varchar(max) = null
as
begin
	set nocount on;

	set @search = '%' + @search + '%'

	declare @result table (
		id int primary key,
		node hierarchyid
		)

	if @parent_id is not null
		insert into @result(id)
		select id
		from app_registry
		where parent_id = @parent_id
	
	else begin

		if @search is not null 
			insert into @result(id, node)
			select a.id, a.node
			from app_registry a
			where (
				a.name like @search
				or a.registry_id like @search
				or a.val_string like @search
				or a.note like @search
				)
				and a.is_deleted = 0		

		else
		    insert into @result(id, node)
			select a.id, a.node
			from app_registry a
			where parent_id is null
			and is_deleted = 0

		-- add parents
		insert into @result(id, node)
		select distinct x.id, x.node
		from app_registry x
			join @result r on r.node.IsDescendantOf(x.node) = 1
		where x.has_childs = 1
			and x.is_deleted = 0
			and not exists(select 1 from @result where id = x.id)

	end

	-- final
	select a.*, NODE_ID = a.id
	from app_registry a
		join @result r on r.id	= a.id
	order by a.node
end
go
