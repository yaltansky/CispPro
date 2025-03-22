if object_id('agents_view') is not null drop proc agents_view
go
/*
	declare @r int
	exec agents_view 700, @rowscount = @r out
*/
create proc agents_view
	@mol_id int,
	
	-- filter		
	@status_id int = null,
	@group_id int = null,	
	@category_id int = null,
	@has_dadata bit = null,
	@member_id int = null,
	@folder_id int = null,
	@buffer_operation int = null, 
		-- 1 add rows to buffer
		-- 2 remove rows from buffer
	@search nvarchar(100) = null,

	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	
	--
	@rowscount int out
as
begin

    set nocount on;

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids
	insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'A'

-- cast @search
	declare @agent_id int
		
	if dbo.hashid(@search) is not null
	begin
		set @agent_id = dbo.hashid(@search)
		set @search = null
	end
	else begin
		set @search = '%' + replace(@search, ' ', '%') + '%'
	end

	declare @where nvarchar(max) = concat(' where
			(@agent_id is null or x.agent_id = @agent_id)'
		, case when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') end
		, case when @category_id is not null then concat(' and (x.category_id = ', @category_id, ')') end
		-- @group_id
		, case
			when @group_id <> 0 then concat(' and exists(select 1 from agents_groups where agent_id = x.agent_id and group_id = ', @group_id, ')')
			when @group_id = 0 then ' and not exists(select 1 from agents_groups where agent_id = x.agent_id)'
		  end
		-- @has_dadata
		, case
			when @has_dadata = 1 then ' and (x.dadata_hid is not null)'
			when @has_dadata = 0 then ' and (x.dadata_hid is null)'
		  end
		-- @member_id
		, case
			when @member_id is not null then concat(' and exists(select 1 from agents_mols where agent_id = x.agent_id and mol_id = ', @member_id, ')')
		  end
		-- @search
		, case
			when @search is null 
				and @status_id is null 
				and @folder_id is null
				then ' and (x.status_id in (1))'
			when @search is not null then ' and (x.name like @search or x.name_print like @search or x.inn like @search)'
		  end
		  )

	declare @fields_base nvarchar(max) = N'		
		@mol_id int,
		@agent_id int,
		@status_id int,		
		@search nvarchar(100),
		@ids app_pkids readonly
	'

	declare @inner nvarchar(max) = 
		case when @folder_id is not null then ' join @ids ids on ids.id = x.agent_id ' else '' end
		
	declare @sql nvarchar(max), @fields nvarchar(max)

	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from v_agents x ' + @inner + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @agent_id, @status_id, @search,
            @ids,
            @rowscount out

		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.name'
		if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

		declare @subquery nvarchar(max) = N'
            (select * from v_agents x '
            + @inner + @where
            +' ) x ' + @order_by

        -- @sql
        set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

        -- print '@sql: ' + @sql + char(10)

        exec sp_executesql @sql, @fields,
            @mol_id, @agent_id, @status_id, @search,
            @ids,
            @offset, @fetchrows

	end

	else begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

		if @buffer_operation = 1
		begin
			-- add to buffer
			set @sql = N'
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''A'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''A'', x.agent_id, @mol_id from v_agents x '
				+ @inner + @where
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @agent_id, @status_id, @search,
				@ids,
				@buffer_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''A''
					and obj_id in (select agent_id from v_agents x ' + @where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @agent_id, @status_id, @search,
				@ids,
				@buffer_id
		end
	end -- buffer_operation

end
go
