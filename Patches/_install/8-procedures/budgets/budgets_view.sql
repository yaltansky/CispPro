if object_id('budgets_view') is not null drop proc budgets_view
go
/*
	declare @r int
	exec budgets_view @mol_id = 700, @rowscount = @r out
*/
create proc budgets_view
	@mol_id int,
	-- filter		
	@type_id int = null,
	@subject_id int = null,	
	@period_id varchar(16) = null,
	@status_id int = null,	
	@author_id int = null,
	@folder_id int = null,
	@buffer_operation int = null, 
		-- 1 add rows to buffer
		-- 2 remove rows from buffer
	@search nvarchar(100) = null,
	@extra_id int = null,
	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	--
	@rowscount int = null out
as
begin

    set nocount on;

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin,Projects.Admin')

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids
	insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'bdg'

-- @search_ids	
	declare @search_text nvarchar(100)
	declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)

	if exists(select 1 from @search_ids)
		set @search = null
	else begin		
		set @search_text = @search
		set @search_text = '"' + replace(@search_text, '"', '*') + '"'				
		set @search = '%' + replace(@search, ' ', '%') + '%'		
	end

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (1 = 1)'
		-- @is_admin
		, case
			when @is_admin = 1 then ''
			else ' and (
				@mol_id in (x.mol_id)
				or exists(select 1 from budgets_shares where budget_id = x.budget_id and mol_id = @mol_id and a_read = 1)
				)'
		  end
		, case when @type_id is not null then concat(' and (x.type_id = ', @type_id, ')') end
		, case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end
        , case when @period_id is not null then concat(' and (x.period_id = ', @period_id, ')') end
		, case 
			when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')')
			when @extra_id is null then ' and (x.status_id <> -1)'
		  end
		, case when @author_id is not null then concat(' and (x.mol_id = ', @author_id, ')') end
		, case when @search is not null then ' and (contains(x.content, @search_text) or x.content like @search)' end
		-- @extra_id
		, case
			when exists(select 1 from @ids) then ''
			when @extra_id = 1 then ' and (x.status_id <> -1 and x.main_id is null)'
			when @extra_id = -1 then ' and (x.status_id = -1)'
			when @extra_id = -2 then ' and (x.main_id is not null)'
		  end
		  )

	declare @fields_base nvarchar(max) = N'		
		@mol_id int,		
		@extra_id int,
		@search nvarchar(100),
		@search_text nvarchar(100),
		@ids app_pkids readonly,
		@search_ids app_pkids readonly
	'

	declare @inner nvarchar(max) = N'
		join budgets_statuses statuses on statuses.status_id = x.status_id
		left join budgets bm on bm.budget_id = x.main_id
		left join subjects subj on subj.subject_id = x.subject_id
		left join periods per on per.period_id = x.period_id
		left join projects on projects.project_id = x.project_id
		left join mols m1 on m1.mol_id = x.mol_id
		'
		+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.budget_id ' else '' end
		+ case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.budget_id' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from budgets x ' + @inner + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @extra_id, @search, @search_text,
            @ids, @search_ids,
            @rowscount out
	
		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.budget_id'
		if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

		declare @subquery nvarchar(max) = N'
            (
                SELECT
					X.BUDGET_ID,
					X.TYPE_ID,
					X.STATUS_ID,
					X.SUBJECT_ID,
					X.PERIOD_ID,
					X.PROJECT_ID,
					X.MOL_ID,
					SUBJECT_NAME = SUBJ.SHORT_NAME,
					PERIOD_NAME = PER.NAME,
					STATUS_NAME = STATUSES.NAME,
					X.NAME,
					MAIN_NAME = BM.NAME,
					PROJECT_NAME = PROJECTS.NAME,
					MOL_NAME = M1.NAME,
					X.NOTE,
					X.ADD_DATE,
					X.UPDATE_DATE
                FROM BUDGETS X 
				'
            + @inner + @where
            +' ) x ' + @order_by

        -- @sql
        set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

        print '@sql: ' + @sql + char(10)

        exec sp_executesql @sql, @fields,
            @mol_id, @extra_id, @search, @search_text,
            @ids, @search_ids,
            @offset, @fetchrows

	end

	else begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

		if @buffer_operation = 1
		begin
			-- add to buffer
			set @sql = N'
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''BDG'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''BDG'', x.budget_id, @mol_id from budgets x '
				+ @inner + @where
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @extra_id, @search, @search_text,
				@ids, @search_ids,
				@buffer_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''BDG''
					and obj_id in (select budget_id from budgets x ' + @where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @extra_id, @search, @search_text,
				@ids, @search_ids,
				@buffer_id
		end
	end -- buffer_operation

end
go
