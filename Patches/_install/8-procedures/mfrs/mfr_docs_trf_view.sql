if object_id('mfr_docs_trf_view') is not null drop proc mfr_docs_trf_view
go
-- exec mfr_docs_trf_view 700, @filter_xml = '<f></f>', @trace = 1
create proc mfr_docs_trf_view
	@mol_id int,
	@filter_xml xml,
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

    -- parse filter
		declare
			@acc_register_id int,
			@subject_id int,
			@type_id int,
			@plan_id int,
			@status_id int,				
			@place_id int,	
			@place_to_id int,	
			@author_id int,
			@d_doc_from date,
			@d_doc_to date,			
			@folder_id int,
			@buffer_operation int,
			@search nvarchar(max),
			@extra_id int

		declare @handle_xml int; exec sp_xml_preparedocument @handle_xml output, @filter_xml
			select
				@acc_register_id = nullif(acc_register_id, 0),
				@subject_id = nullif(subject_id, 0),
				@type_id = nullif(type_id, 0),
				@plan_id = nullif(plan_id, 0),
				@status_id = @filter_xml.value('(/*/STATUS_ID/text())[1]', 'int'),
				@d_doc_from = nullif(d_doc_from, '1900-01-01'),
				@d_doc_to = nullif(d_doc_to, '1900-01-01'),				
				@place_id = nullif(place_id, 0),
				@place_to_id = nullif(place_to_id, 0),
				@author_id = nullif(author_id, 0),
				@folder_id = nullif(folder_id, 0),
				@buffer_operation = nullif(buffer_operation, 0),
				@search = search,
				@extra_id = nullif(ExtraId, 0)
			from openxml (@handle_xml, '/*', 2) with (
				ACC_REGISTER_ID INT,
				SUBJECT_ID INT,
				TYPE_ID INT,
				PLAN_ID INT,	
				STATUS_ID INT,
				D_DOC_FROM DATE,
				D_DOC_TO DATE,
				PLACE_ID INT,
				PLACE_TO_ID INT,
				AUTHOR_ID INT,
				Search VARCHAR(MAX),
				ExtraId INT,
				FOLDER_ID INT,
				BUFFER_OPERATION INT
				)
		exec sp_xml_removedocument @handle_xml

	if (@offset = 0 or @buffer_operation is not null)
		or not exists(select 1 from sdocs_cache where mol_id = @mol_id)
	begin
	-- select, then cache results		
		exec mfr_docs_trf_view;10
			@mol_id = @mol_id,			
			@acc_register_id = @acc_register_id,
			@subject_id = @subject_id,
			@type_id = @type_id,
			@plan_id = @plan_id,
			@status_id = @status_id,
			@d_doc_from = @d_doc_from,
			@d_doc_to = @d_doc_to,
			@place_id = @place_id,
			@place_to_id = @place_to_id,
			@author_id = @author_id,
			@folder_id = @folder_id,
			@buffer_operation = @buffer_operation,
			@search = @search,
			@extra_id = @extra_id,
			@sort_expression = @sort_expression,
			@offset = @offset,
			@fetchrows = @fetchrows,			
			@rowscount = @rowscount out,
			@trace = @trace
	end

	-- use cache
	else begin
		select x.*
		from v_mfr_sdocs_trf x
			join sdocs_cache xx on xx.mol_id = @mol_id and xx.doc_id = x.doc_id
		order by xx.id
		offset @offset rows fetch next @fetchrows rows only

		set @rowscount = (select count(*) from sdocs_cache where mol_id = @mol_id)
	end
end
GO
create proc mfr_docs_trf_view;10
	@mol_id int,
	-- filter	
	@acc_register_id int = null,
	@subject_id int = null,
	@type_id int = null,
	@plan_id int = null,
	@status_id int = null,	
	@d_doc_from datetime = null,
	@d_doc_to datetime = null,
	@place_id int = null,	
	@place_to_id int = null,	
	@author_id int = null,
	@folder_id int = null,
	@buffer_operation int = null,
	@search nvarchar(max) = null,
	@extra_id int = null,
	@sort_expression varchar(50) = null,	
	@offset int = 0,
	@fetchrows int = 30,	
	@cacheonly bit = 0,
	--
	@rowscount int out,
	@trace bit = 0
as
begin
	-- access
		declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
		create table #subjects(id int primary key); insert into #subjects select distinct obj_id from @objects where obj_type = 'SBJ'
		
		create table #ids(id int primary key)
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'MFTRF', @temp_table = '#ids'

	-- cast @search
        declare @initial_search varchar(max) = @search
		create table #search_ids(id int primary key); insert into #search_ids select distinct id from dbo.hashids(@search)
		if exists(select 1 from #search_ids) set @search = null
		else set @search = '%' + replace(replace(@search, ' ', '%'), '*', '%') + '%'		

		if @search is not null
			and not exists(select 1 from #search_ids)
		begin
			insert into #search_ids select doc_id from v_mfr_sdocs_trf where number = @initial_search
				and (@type_id is null or type_id = @type_id)

			if exists(select 1 from #search_ids) begin
				set @search = null
				set @type_id = null
			end
		end

		declare @today datetime = dbo.today()
		declare @month_from datetime = dateadd(d, -datepart(d, @today)+1, @today)
		declare @month_to datetime = dateadd(m, 1, @month_from) - 1

	-- prepare sql
		declare @sql nvarchar(max), @fields nvarchar(max)

		declare @where nvarchar(max) = concat(
			N' where (x.subject_id in (select id from #subjects) or x.subject_id is null) '
			
			, case when @acc_register_id is not null then concat(' and (x.acc_register_id = ', @acc_register_id, ')') end
			, case when @subject_id is not null then concat(' and (x.subject_id = ', @subject_id, ')') end
			, case when @type_id is not null then concat(' and (x.type_id = ', @type_id, ')') end
			
			, case 
				when @status_id = -2 then ' and (x.status_id = 0 and x.add_mol_id = @mol_id)'
				when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') 
				when @folder_id is null and @search is null then ' and (x.status_id != -1)'
			  end

			, case when @place_id is not null then concat(' and (x.place_id = ', @place_id, ')') end
			, case when @place_to_id is not null then concat(' and (x.place_to_id = ', @place_to_id, ')') end
			, case when @author_id is not null then concat(' and (x.add_mol_id = ', @author_id, ')') end
			
			, case when @d_doc_from is not null or @d_doc_to is not null then 
				' and (d_doc between isnull(@d_doc_from,0) and isnull(@d_doc_to,''2100-01-01''))' 
				end

			-- @search
			, case
				when @search is not null then 'and (
					x.content like @search
					or exists(
						select 1 from sdocs_products
						where doc_id = x.doc_id
							and product_id in (select product_id from products where name like @search)
						)
					)
					'
				end
			)

		declare @fields_base nvarchar(max) = N'
			@mol_id int,
			@today date,
			@month_from datetime,
			@month_to datetime,
			@d_doc_from datetime,
			@d_doc_to datetime,			
			@search nvarchar(max)
		'

		declare @inner nvarchar(max) = N''
			+ case when @folder_id is null then '' else ' join #ids ids on ids.id = x.doc_id ' end
			+ case when exists(select 1 from #search_ids) then 'join #search_ids i2 on i2.id = x.doc_id' else '' end
			
		if @buffer_operation is not null
		begin
			set @rowscount = -1 -- dummy

			declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

			if @buffer_operation = 1
			begin
				-- add to buffer
				set @sql = N'
					delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''MFTRF'';
					insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
					select @buffer_id, ''MFTRF'', x.doc_id, @mol_id from v_mfr_sdocs_trf x '
					+ @inner + @where
				set @fields = @fields_base + ', @buffer_id int'

				exec sp_executesql @sql, @fields,
					@mol_id, @today, @month_from, @month_to, @d_doc_from, @d_doc_to,
					@search,
					@buffer_id
			end

			else if @buffer_operation = 2
			begin
				-- remove from buffer
				set @sql = N'
					delete from objs_folders_details
					where folder_id = @buffer_id
						and obj_type = ''MFTRF''
						and obj_id in (select doc_id from sdocs x ' + @where + ')'
				set @fields = @fields_base + ', @buffer_id int'
				
				exec sp_executesql @sql, @fields,
					@mol_id, @today, @month_from, @month_to, @d_doc_from, @d_doc_to,
					@search,
					@buffer_id
			end
		end

		else 
		begin
			-- @rowscount
			if @cacheonly = 0
			begin
				set @sql = N'select @rowscount = count(*) from v_mfr_sdocs_trf x ' + @inner + @where
				set @fields = @fields_base + ', @rowscount int out'

				exec sp_executesql @sql, @fields,
					@mol_id, @today, @month_from, @month_to, @d_doc_from, @d_doc_to,
					@search,
					@rowscount out
			end
			
			-- @order_by
			declare @order_by nvarchar(100) = N' order by x.d_doc'
			if @extra_id = 3 set @sort_expression = null
			if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

			delete from sdocs_cache where mol_id = @mol_id

			declare @subquery nvarchar(max) = N'
                (
                    select x.* from v_mfr_sdocs_trf x '
                + @inner + @where
                +' ) x ' + @order_by

			-- cache
			if isnull(@rowscount,0) < 5000 or @cacheonly = 1
			begin			
				declare @sql_cache nvarchar(max) = N'
					insert into sdocs_cache(mol_id, doc_id)
					select @mol_id, x.doc_id
					from ' + @subquery
				set @fields = @fields_base

				exec sp_executesql @sql_cache, @fields,
					@mol_id, @today, @month_from, @month_to, @d_doc_from, @d_doc_to,
					@search
			end

			if @cacheonly = 0
			begin
				-- @sql
				set @sql = N'select x.* from ' + @subquery

				-- optimize on fetch
				if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

				set @fields = @fields_base + ', @offset int, @fetchrows int'

				if @trace = 1 print '@sql: ' + @sql + char(10)

				exec sp_executesql @sql, @fields,
					@mol_id, @today, @month_from, @month_to, @d_doc_from, @d_doc_to, 
					@search,
					@offset, @fetchrows
			end

		end -- if

	exec drop_temp_table '#subjects,#ids,#search_ids'
end
go
