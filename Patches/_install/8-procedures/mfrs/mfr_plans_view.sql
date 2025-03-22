if object_id('mfr_plans_view') is not null drop proc mfr_plans_view
go
-- exec mfr_plans_view 700
create proc mfr_plans_view
	@mol_id int,	
	-- filter
	@status_id int = null,
	@d_from datetime = null,
	@d_to datetime = null,
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
	@rowscount int = null out
as
begin

    set nocount on;
	set transaction isolation level read uncommitted;

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin')

-- access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids
	insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfp'

-- @search_ids	
	declare @search_text nvarchar(100)
	declare @search_ids as app_pkids; insert into @search_ids select id from dbo.hashids(@search)

	if exists(select 1 from @search_ids)
		set @search = null
	else begin		
		set @search = '%' + replace(@search, ' ', '%') + '%'		
	end

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (1=1)'		
		, case 
			when @folder_id is not null then ''
			when @status_id = 1000 then '' -- all statuses
			when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') 
			else ' and (x.status_id = 1)'
		  end
		, case when @d_from is not null then ' and (x.d_to >= @d_from)' end
		, case when @d_to is not null then ' and (x.d_to <= @d_to)' end
		, case
			when @search is not null then ' and (x.number like @search or x.note like @search)'
		  end
		)

	declare @fields_base nvarchar(max) = N'		
		@mol_id int,
		@d_from datetime,
		@d_to datetime,
		@search nvarchar(100),
		@ids app_pkids readonly,
		@search_ids app_pkids readonly,
		@subjects app_pkids readonly
	'

	declare @inner nvarchar(max) = N'
		join subjects subj on subj.subject_id = x.subject_id
			join @subjects sx on sx.id = subj.subject_id
		join mfr_plans_statuses s on s.status_id = x.status_id
		'
		+ case when exists(select 1 from @ids) then ' join @ids i on i.id = x.plan_id ' else '' end
		+ case when exists(select 1 from @search_ids) then 'join @search_ids i2 on i2.id = x.plan_id' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from mfr_plans x ' + @inner + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @d_from, @d_to, @search,
            @ids, @search_ids, @subjects,
            @rowscount out
	
		-- @order_by
		declare @order_by nvarchar(50) = N' order by x.plan_id'
		if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

		declare @subquery nvarchar(max) = N'
            (
                SELECT X.*,
					SUBJECT_NAME = SUBJ.NAME,
					STATUS_NAME = S.NAME,
					SDOCS_COUNT = (SELECT COUNT(*) FROM MFR_SDOCS WHERE PLAN_ID = X.PLAN_ID AND STATUS_ID <> -1)
                FROM MFR_PLANS X
			'
            + @inner + @where
            +' ) x ' + @order_by

        -- @sql
        set @sql = N'select x.* from ' + @subquery

        -- optimize on fetch
        if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

        set @fields = @fields_base + ', @offset int, @fetchrows int'

		print @sql

        exec sp_executesql @sql, @fields,
            @mol_id, @d_from, @d_to, @search,
            @ids, @search_ids, @subjects,
            @offset, @fetchrows

	end

	else begin
		set @rowscount = -1 -- dummy

		declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

		if @buffer_operation = 1
		begin
			-- add to buffer
			set @sql = N'
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''MFC'';
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, ''MFC'', x.plan_id, @mol_id from mfr_plans x '
				+ @inner + @where
			set @fields = @fields_base + ', @buffer_id int'

			exec sp_executesql @sql, @fields,
				@mol_id, @d_from, @d_to, @search,
				@ids, @search_ids, @subjects,
				@buffer_id
		end

		else if @buffer_operation = 2
		begin
			-- remove from buffer
			set @sql = N'
				delete from objs_folders_details
				where folder_id = @buffer_id
					and obj_type = ''MFC''
					and obj_id in (select plan_id from mfr_plans x ' + @where + ')'
			set @fields = @fields_base + ', @buffer_id int'
			
			exec sp_executesql @sql, @fields,
				@mol_id, @d_from, @d_to, @search,
				@ids, @search_ids, @subjects,
				@buffer_id
		end
	end -- buffer_operation

end
go
