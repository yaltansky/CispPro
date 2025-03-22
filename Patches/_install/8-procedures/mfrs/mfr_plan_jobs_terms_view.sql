if object_id('mfr_plan_jobs_terms_view') is not null drop proc mfr_plan_jobs_terms_view
go
-- exec mfr_plan_jobs_terms_view 1000
create proc mfr_plan_jobs_terms_view
	@mol_id int,	
	-- filter
	@status_id int = null,
	@search nvarchar(max) = null,
	@folder_id int = null,
	@buffer_operation int = null, 
	-- sorting, paging
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	--
	@rowscount int = null out,
	@trace bit = 0
as
begin

  set nocount on;
	set transaction isolation level read uncommitted;

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfjT'

-- @search_ids	
	declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)

	if exists(select 1 from @search_ids) set @search = null
	else set @search = '%' + replace(@search, ' ', '%') + '%'		

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (1=1)'

		, case 
			when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') 
		  end		
		
		, case when @search is not null then ' and (x.note like @search)' end
		)

	declare @today datetime = dbo.today()
	declare @fields_base nvarchar(max) = N'		
		@mol_id int,		
		@search nvarchar(max),
		@ids app_pkids readonly,
		@search_ids app_pkids readonly
	'

	declare @inner nvarchar(max) = N''
		+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.term_id ' else '' end
		+ case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.term_id' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from v_mfr_plans_jobs_terms x ' + @inner + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @search,
            @ids, @search_ids,
            @rowscount out

				if @trace = 1 print @sql

		-- @order_by
			declare @order_by nvarchar(50) = N' order by x.term_id'
			if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

			declare @subquery nvarchar(max) = N'(select x.* from v_mfr_plans_jobs_terms x
				' + @inner + @where
				+' ) x ' + @order_by

			-- @sql
			set @sql = N'select x.* from ' + @subquery

			-- optimize on fetch
			if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

			set @fields = @fields_base + ', @offset int, @fetchrows int'

		if @trace = 1 print @sql
		
		exec sp_executesql @sql, @fields,
				@mol_id, @search,
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
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''MFJT'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''MFJT'', x.term_id, @mol_id from v_mfr_plans_jobs_terms x '
				+ @inner + @where
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @search,
				@ids, @search_ids,
				@buffer_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''MFJT''
					and obj_id in (select term_id from v_mfr_plans_jobs_terms x ' + @where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @search,
				@ids, @search_ids,
				@buffer_id
		end
	end -- buffer_operation

end
go
