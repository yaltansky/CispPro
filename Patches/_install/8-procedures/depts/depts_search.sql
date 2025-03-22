if object_id('depts_search') is not null drop proc depts_search
go
create proc depts_search
	@subject_id int,
	@search varchar(250) = null,
	@show_deleted int = null
as
begin

	set nocount on;

	declare @result table (dept_id int, node hierarchyid)

	if @search is null
	begin
		insert into @result
			select dept_id, node
			from depts
			where subject_id = @subject_id and parent_id is null
	end
	
	else begin
		declare @id int

		if dbo.hashid(@search) is not null
		begin
			set @id = dbo.hashid(@search)
			set @search = null
		end

		set @search = '%' + replace(@search, ' ', '%') + '%'

		insert into @result
			select dept_id, node
			from depts
			where subject_id = @subject_id
				and (@id is null or dept_id = @id)
				and (@search is null or name like @search)
				and (
					(@show_deleted is null) -- показать все
					or (@show_deleted = 1 and is_deleted = 0) -- показать действующие
					or (@show_deleted = -1 and is_deleted = 1) -- показать удалённые
					)

		-- get all parents
		insert into @result(dept_id, node)
			select distinct x.dept_id, x.node
			from depts x
				inner join @result r on r.node.IsDescendantOf(x.node) = 1
			where x.has_childs = 1
				and x.is_deleted = 0
	end

	select		
		x.SUBJECT_ID,
		x.DEPT_ID,
		x.NAME,
		x.SHORT_NAME,
		x.CHIEF_ID,
		CHIEF_NAME = mols.name,
		x.RESOURCE_ID,
		RESOURCE_NAME = r.name,
		-- node
		x.NODE_ID,
		x.PARENT_ID, 
		x.HAS_CHILDS,
		x.LEVEL_ID,
		x.SORT_ID,
		x.IS_DELETED
	from depts x
		left join mols on mols.mol_id = x.chief_id
        left join projects_resources r on r.resource_id = x.resource_id
	where x.dept_id in (select dept_id from @result)
		and x.is_deleted = 0
	order by x.node
end
GO
