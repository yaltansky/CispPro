if object_id('mfr_opers_view') is not null drop proc mfr_opers_view
go
/*
exec mfr_opers_view 1000, '<f>
	<PLAN_ID>0</PLAN_ID>
	<WORK_TYPE_ID>1</WORK_TYPE_ID>
	</f>'
	, @trace = 1
*/
create proc mfr_opers_view
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

	/*
	**
	** В данной процедуре акцент сделан на оптимизации.
	** 1. Большая часть полей - напрямую из таблицы.
	** 2. Позднее связываение - join после получение выборки
	**
	*/
	
    set nocount on;
	set transaction isolation level read uncommitted;

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin')

	-- pattern params
		declare @pkey varchar(50) = 'OPER_ID'
		declare @base_view varchar(50) = 'SDOCS_MFR_OPERS'
		declare @obj_type varchar(16) = 'MFO'

	-- parse filter
		declare 
			@plan_id int,
			@mfr_doc_id int,
			@product_id int,
			@status_id int,
			@work_type_id int,
			@place_id int,
			@resource_id int,
			@milestone_id int,
			@item_id int,
            @d_from_from date,
            @d_from_to date,
            @d_to_from date,
            @d_to_to date,
            @d_from_plan_from date,
            @d_from_plan_to date,
            @d_to_plan_from date,
            @d_to_plan_to date,
			@folder_id int,
			@buffer_operation int,
				-- 1 add rows to buffer
				-- 2 remove rows from buffer
				-- 99 build distinct PRODUCT_ID in buffer			
			@search nvarchar(max)

		declare @handle_xml int; exec sp_xml_preparedocument @handle_xml output, @filter_xml
			select
				@plan_id = plan_id,
				@mfr_doc_id = nullif(mfr_doc_id,0),
				@work_type_id = isnull(nullif(work_type_id,0), 1),
				@status_id = @filter_xml.value('(/*/STATUS_ID/text())[1]', 'int'),
				@place_id = nullif(place_id,0),
				@resource_id = nullif(resource_id,0),
				@milestone_id = nullif(milestone_id,0),
                @d_from_from = nullif(d_from_from, '1900-01-01'),
                @d_from_to = nullif(d_from_to, '1900-01-01'),
                @d_to_from = nullif(d_to_from, '1900-01-01'),
                @d_to_to = nullif(d_to_to, '1900-01-01'),
                @d_from_plan_from = nullif(d_from_plan_from, '1900-01-01'),
                @d_from_plan_to = nullif(d_from_plan_to, '1900-01-01'),
                @d_to_plan_from = nullif(d_to_plan_from, '1900-01-01'),
                @d_to_plan_to = nullif(d_to_plan_to, '1900-01-01'),
				@folder_id = nullif(folder_id,0),
				@buffer_operation = nullif(buffer_operation,0),
				@search = search
			from openxml (@handle_xml, '/*', 2) with (
				PLAN_ID INT,
				MFR_DOC_ID INT,
				WORK_TYPE_ID INT,
				PLACE_ID INT,
				RESOURCE_ID INT,
                MILESTONE_ID INT,
                D_FROM_FROM DATE,
                D_FROM_TO DATE,
                D_TO_FROM DATE,
                D_TO_TO DATE,
                D_FROM_PLAN_FROM DATE,
                D_FROM_PLAN_TO DATE,
                D_TO_PLAN_FROM DATE,
                D_TO_PLAN_TO DATE,
				FOLDER_ID INT,
				BUFFER_OPERATION INT,
				Search NVARCHAR(MAX)
				)
		exec sp_xml_removedocument @handle_xml

	-- @plans
		declare @plans as app_pkids
		if isnull(@plan_id, 0) = 0
			insert into @plans select plan_id from mfr_plans where status_id = 1
		else 
			insert into @plans select @plan_id

	-- #ids
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
        create table #ids(id int primary key)
        exec objs_folders_ids @folder_id = @folder_id, @obj_type = @obj_type, @temp_table = '#ids'
		
        declare @hasids as bit = case when exists(select 1 from #ids) then 1 else 0 end

        if @hasids = 1 begin
            set @work_type_id = null
        end

	-- @search_ids	
		set @search = '%' + replace(@search, ' ', '%') + '%'		

	-- prepare sql
		declare @sql nvarchar(max), @fields nvarchar(max)

		declare @where nvarchar(max) = concat(
			' where (d_from_plan is not null)'
			, case 
				when @mfr_doc_id is not null then concat(' and (x.mfr_doc_id = ', @mfr_doc_id, ')') 
				when @plan_id = 0 then 
					case
						when @hasids = 0 then ' and (mfr.status_id between 0 and 99)'
						else ''
					end
				when @plan_id is not null then concat(' and (mfr.plan_id = ', @plan_id, ')') 
			  end
			, case when @work_type_id is not null then concat(' and (isnull(x.work_type_id, 1) = ', @work_type_id, ')') end
			, case 
                when @status_id = -100 then ' and (x.status_id != 100)'
                when @status_id is not null then concat(' and (x.status_id = ', @status_id, ')') 
              end
			, case when @place_id is not null then concat(' and (x.place_id = ', @place_id, ')') end
			, case when @resource_id is not null then concat(' and (x.resource_id = ', @resource_id, ')') end
			, case when @milestone_id is not null then concat(' and (x.milestone_id = ', @milestone_id, ')') end			
            
            , case when @d_from_from is not null then ' and (x.d_from >= @d_from_from)' end
            , case when @d_from_to is not null then ' and (cast(x.d_from as date) <= @d_from_to)' end

            , case when @d_to_from is not null then ' and (x.d_to >= @d_to_from)' end
            , case when @d_to_to is not null then ' and (cast(x.d_to as date) <= @d_to_to)' end

            , case when @d_from_plan_from is not null then ' and (x.d_from_plan >= @d_from_plan_from)' end
            , case when @d_from_plan_to is not null then ' and (cast(x.d_from_plan as date) <= @d_from_plan_to)' end

            , case when @d_to_plan_from is not null then ' and (x.d_to_plan >= @d_to_plan_from)' end
            , case when @d_to_plan_to is not null then ' and (cast(x.d_to_plan as date) <= @d_to_plan_to)' end

			, case
				when @search is not null then ' and (
					concat(x.mfr_number, x.item_name, x.name) like @search 
					)'
			  end
			)

		declare @fields_base nvarchar(max) = N'		
			@mol_id int,
            @d_from_from date,
            @d_from_to date,
            @d_to_from date,
            @d_to_to date,
            @d_from_plan_from date,
            @d_from_plan_to date,
            @d_to_plan_from date,
            @d_to_plan_to date,
            @search nvarchar(max),
			@plans app_pkids readonly
		'
		
		declare @join nvarchar(max) = N'
			join sdocs mfr with(nolock) on mfr.doc_id = x.mfr_doc_id and mfr.ext_type_id is null
			'
			+ case when exists(select 1 from #ids) then ' join #ids i on i.id = x.oper_id ' else '' end			

		if @buffer_operation is  null
		begin
			-- @rowscount
			set @sql = N'select @rowscount = count(*) from (
				select x.*,
					place_name = pl.name
				from sdocs_mfr_opers x with(nolock)
					join mfr_places pl with(nolock) on pl.place_id = x.place_id
				) x ' + @join + @where
			set @fields = @fields_base + ', @rowscount int out'

			-- if @trace = 1 print concat('rowscount: ', @sql)

			exec sp_executesql @sql, @fields,
				@mol_id,
                @d_from_from, @d_from_to, @d_to_from, @d_to_to, @d_from_plan_from, @d_from_plan_to, @d_to_plan_from, @d_to_plan_to,
                @search, @plans,
				@rowscount out
		
			-- @order_by
			declare @order_by nvarchar(250) = N' ORDER BY X.D_FROM_PLAN'
			if @sort_expression is not null set @order_by = N' ORDER BY ' + @sort_expression
			set @order_by = @order_by + ' OFFSET @OFFSET ROWS FETCH NEXT @FETCHROWS ROWS ONLY'

            -- @subquery
                declare @subquery nvarchar(max) = N'(
                    SELECT X.* FROM (
                    SELECT X.*,
                        PLACE_NAME = PL.NAME
                    from sdocs_mfr_opers x with(nolock)
                        join mfr_places pl with(nolock) on pl.place_id = x.place_id
                    ) x'
                    + @join + @where + @order_by
                    +') x '
                    
			-- @sql
                set @sql = N'
                SELECT 
                    X.*,
                    C.ITEM_TYPE_ID,
                    ITEM_TYPE_NAME = IT.NAME,
                    RESOURCE_NAME = R.NAME,
                    STATUS_NAME = ST.NAME,
                    STATUS_CSS = ST.CSS,
                    STATUS_STYLE = ST.STYLE,
                    PLAN_HOURS = X.DURATION_WK * DUR.FACTOR / DUR_H.FACTOR,
                    C.UNIT_NAME
                FROM ' + @subquery + '
                    join sdocs_mfr_contents c with(nolock) on c.content_id = x.content_id
                        left join mfr_items_types it on it.type_id = c.item_type_id
                    left join mfr_resources r on r.resource_id = x.resource_id
                    left join mfr_items_statuses st on st.status_id = x.status_id
                    left join projects_durations dur on dur.duration_id = x.duration_wk_id				
                    join projects_durations dur_h on dur_h.duration_id = 2
                '
                
                if @sort_expression is not null
                    set @sql = @sql + ' order by ' + @sort_expression

                set @fields = @fields_base + ', @offset int, @fetchrows int'

                if @trace = 1 print @sql

                exec sp_executesql @sql, @fields,
                    @mol_id,
                    @d_from_from, @d_from_to, @d_to_from, @d_to_to, @d_from_plan_from, @d_from_plan_to, @d_to_plan_from, @d_to_plan_to,
                    @search, @plans,
                    @offset, @fetchrows
		end

		else begin
			set @rowscount = -1 -- dummy

			declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

			if @buffer_operation = 1
			begin
				-- add to buffer
				set @sql = N'
					delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''MFO'';
					;insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
					select @buffer_id, ''MFO'', x.oper_id, @mol_id from sdocs_mfr_opers x with(nolock)
					'
					+ @join + @where
					+ ';select top 0 * from sdocs_mfr_opers'
				set @fields = @fields_base + ', @buffer_id int'
				
				if @trace = 1 print concat(@sql, @fields)

				exec sp_executesql @sql, @fields,
					@mol_id,
                    @d_from_from, @d_from_to, @d_to_from, @d_to_to, @d_from_plan_from, @d_from_plan_to, @d_to_plan_from, @d_to_plan_to,
                    @search, @plans,
					@buffer_id
			end

			else if @buffer_operation = 2
			begin
				-- remove from buffer
				set @sql = N'
					delete from objs_folders_details
					where folder_id = @buffer_id
						and obj_type = ''MFO''
						and obj_id in (select oper_id from sdocs_mfr_opers x with(nolock) ' + @where + ')'
					+ ';select top 0 * from sdocs_mfr_opers'
				set @fields = @fields_base + ', @buffer_id int'
				
				if @trace = 1 print @sql

				exec sp_executesql @sql, @fields,
					@mol_id,
                    @d_from_from, @d_from_to, @d_to_from, @d_to_to, @d_from_plan_from, @d_from_plan_to, @d_to_plan_from, @d_to_plan_to,
                    @search, @plans,
					@buffer_id
			end
		end -- buffer_operation
end
go
