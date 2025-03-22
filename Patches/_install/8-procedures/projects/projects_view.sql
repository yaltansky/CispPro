if object_id('projects_view') is not null drop proc projects_view
go
-- exec projects_view 1000
create proc projects_view
	@mol_id int,
	
	-- filter		
	@subject_id int = null,
	@status_id int = null,	
	@theme_id int = null,	
		-- 1 - Куратор проектов
		-- 2 - Руководитель проектов
		-- 3 - Администратор проектов
		-- 4 - Участник проектов
	@chief_id int = null,
	@admin_id int = null,
	@executor_id int = null,
	@folder_id int = null,
	@buffer_operation int = null, 
		-- 1 add rows to buffer
		-- 2 remove rows from buffer
	@search nvarchar(100) = null,
	@extra_id int = null,
		-- 1 - Текушие проекты
		-- 2 - Головные проекты
		-- 3 - Архивные проекты
	
	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
    @rowscount int = null out
as
begin

    set nocount on;

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin,Projects.Admin')

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'prj'

-- cast @search
	declare @project_id int
	declare @search_text nvarchar(100)

	if dbo.hashid(@search) is not null
	begin
		set @project_id = dbo.hashid(@search)
		set @search = null
	end
	else begin		
		set @search_text = @search
		set @search_text = '"' + replace(@search_text, '"', '*') + '"'				
		set @search = '%' + replace(@search, ' ', '%') + '%'		
	end

	declare @projects table(project_id int primary key, theme_id int)
	if @theme_id is not null begin
		insert into @projects exec projects_counters;10 @mol_id = @mol_id
		delete from @ids
		insert into @ids select project_id from @projects where theme_id = @theme_id
	end

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(' where
			x.type_id in (1,2)
		and (@project_id is null or x.project_id = @project_id)
		and (@subject_id is null or x.subject_id = @subject_id)
		'
		-- @status_id
        , case 
            when nullif(@status_id, 1000) is not null then concat(' and (x.status_id = ', @status_id, ')')
          end
        -- @is_admin
		, case
			when @is_admin = 1 then ''
			else ' and (
				@mol_id in (x.curator_id, x.chief_id, x.admin_id)
				or exists(select 1 from projects_mols where project_id = x.project_id and mol_id = @mol_id)
				)'
		  end
		-- @chief_id
		, case
			when @chief_id is not null then concat(' and (x.chief_id = ', @chief_id, ')')
		  end
		-- @admin_id
		, case
			when @admin_id is not null then concat(' and (x.admin_id = ', @admin_id, ')')
		  end
		-- @executor_id
		, case
			when @executor_id is not null then concat(' and exists(select 1 from projects_mols where project_id = x.project_id and mol_id = ', @executor_id, ')')
		  end
		-- @search
		, case
			when @search is not null then ' and (x.content like @search)'
		  end
		-- @extra_id
		, case
			when @extra_id = -10 then ' and (x.status_id not in (-1,0,10) or (x.status_id = 0 and @mol_id in (x.chief_id, x.admin_id)))'
			when @extra_id = -20 then ' and (x.parent_id is null)'
		  end
		  )

	declare @fields_base nvarchar(max) = N'		
		@mol_id int,
		@project_id int,
		@subject_id int,		
		@extra_id int,
		@search nvarchar(100),
		@search_text nvarchar(100),
		@ids app_pkids readonly
	'

	declare @inner nvarchar(max) = N''
		+ case when @folder_id is not null then ' join @ids ids on ids.id = x.project_id ' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from v_projects x ' + @inner + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @project_id, @subject_id, @extra_id, @search, @search_text,
            @ids,
            @rowscount out

		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.project_id'
		if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

		declare @subquery nvarchar(max) = N'(
			select * from v_projects x '
            + @inner + @where
            +' ) x ' + @order_by

        -- @sql
        set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

        exec sp_executesql @sql, @fields,
            @mol_id, @project_id, @subject_id, @extra_id, @search, @search_text,
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
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''PRJ'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''PRJ'', x.project_id, @mol_id from v_projects x '
				+ @inner + @where
				+ ';select top 0 * from v_projects'
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @project_id, @subject_id, @extra_id, @search, @search_text,
				@ids,
				@buffer_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''PRJ''
					and obj_id in (select project_id from projects x ' + @where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @project_id, @subject_id, @extra_id, @search, @search_text,
				@ids,
				@buffer_id
		end
	end -- buffer_operation

end
go
