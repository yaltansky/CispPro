if object_id('mfr_plan_jobs_view') is not null drop proc mfr_plan_jobs_view
go
-- exec mfr_plan_jobs_view 700, @type_id = 4
create proc mfr_plan_jobs_view
	@mol_id int,	
	-- filter
	@plan_id int = null,
	@place_id int = null,
	@type_id int = null,
	@status_id int = null,
	@dates_id int = null, -- 0 по дате открытия, 1 по дате закрытия, 2 по дате удаления
	@d_from datetime = null,
	@d_to datetime = null,
	@item_id int = null,
	@oper_id int = null,
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

-- #subjects
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	create table #subjects(id int primary key); insert into #subjects select distinct obj_id from @objects where obj_type = 'sbj'

-- #ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	create table #ids(id int primary key)
	exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfj', @temp_table = '#ids'
	if @folder_id is not null set @type_id = null

-- #search_ids
	declare @search_param nvarchar(max) = @search
	create table #search_ids(id int primary key); insert into #search_ids select id from dbo.hashids(@search)

	if exists(select 1 from #search_ids) set @search = null
	else set @search = '%' + replace(replace(@search, ' ', '%'), '*', '%') + '%'		

-- smart search
	if @search is not null
		and not exists(select 1 from #search_ids)
	begin
		insert into #search_ids select plan_job_id from mfr_plans_jobs where number like @search
		
		if not exists(select 1 from #search_ids) 
			insert into #search_ids select plan_job_id 
			from mfr_plans_jobs x
			where exists(
				select 1 from mfr_plans_jobs_details jd
					join products p on p.product_id = jd.item_id
				where plan_job_id = x.plan_job_id
					and p.name like @search
				)

        if not exists(select 1 from #search_ids) 
			insert into #search_ids select plan_job_id 
			from mfr_plans_jobs x
			where exists(
				select 1 from mfr_plans_jobs_details jd
					join mfr_sdocs mfr on mfr.doc_id = jd.mfr_doc_id
				where plan_job_id = x.plan_job_id
					and mfr.number = @search_param
				)

		if exists(select 1 from #search_ids) 
		begin
			set @search = null; set @type_id = null
		end
	end

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = concat(
		' where (1=1)'

		, case when @type_id is not null and @oper_id is null then concat(' and (x.type_id = ', @type_id, ')') end

		, case 
			-- закрыто сегодня			
			when @status_id is not null then 
				case
					when @status_id = 101 then ' and (dbo.getday(x.d_closed) = @today)'
					when @status_id = 1000 then '' -- all statuses
					else concat(' and (x.status_id = ', @status_id, ')') 
				end
			when @search is null 
				and @folder_id is null
				and @item_id is null
				and @oper_id is null
				and not exists(select 1 from #search_ids)
				then ' and (x.status_id between 0 and 99 or x.type_id = 4)'
		  end		
		
		, case when @place_id is not null then ' and (x.place_id = @place_id)' end
		
		, case when @d_from is not null then 
			case isnull(@dates_id, 0)
				when 0 then ' and (x.d_doc >= @d_from)' 
				when 1 then ' and (x.d_closed >= @d_from)' 
				when 2 then ' and (cast(x.update_date as date) >= @d_from)' 
			end
		  end
		
		, case when @d_to is not null then
			case isnull(@dates_id, 0)
				when 0 then ' and (x.d_doc <= @d_to)'
				when 1 then ' and (cast(x.d_closed as date) <= @d_to)'
				when 2 then ' and (cast(x.update_date as date) <= @d_to)'
			end			
		  end

        , case when isnull(@dates_id, 0) = 3 then
            ' and exists(
                select 1 from mfr_plans_jobs_executors e
                    join mfr_plans_jobs_details jd on jd.id = e.detail_id
                where jd.plan_job_id = x.plan_job_id
                    and e.d_doc between @d_from and @d_to
                    and (e.fact_q > 0 or e.duration_wk > 0)
            )'            
          end
		
		, case when @item_id is not null then concat(' and exists(select 1 from mfr_plans_jobs_details where plan_job_id = x.plan_job_id and item_id = ', @item_id, ')') end
		
		, case when @oper_id is not null then concat('
			and exists(select 1 from v_mfr_r_plans_jobs_items_all where job_id = x.plan_job_id',
				' and oper_id = ', @oper_id,
				')'
			) end
		, case when @search is not null then 
            ' and (
                x.content like @search
                or exists(
                    select 1 from mfr_plans_jobs_details jd
                    where jd.plan_job_id = x.plan_job_id
                        and exists(
                            select 1 from mfr_plans_jobs_executors e
                                join mols on mols.mol_id = e.mol_id
                            where e.detail_id = jd.id
                                and mols.name like @search
                            )
                    )
                )' 
          end
		)

	declare @today datetime = dbo.today()
	declare @fields_base nvarchar(max) = N'		
		@mol_id int,		
		@d_from datetime,
		@d_to datetime,
		@today datetime,
		@place_id int,
		@search nvarchar(max)
	'

	declare @join nvarchar(max) = N'
		join #subjects s on s.id = x.subject_id
		'		
		+ case when @folder_id is not null or exists(select 1 from #ids) then ' join #ids i on i.id = x.plan_job_id ' else '' end
		+ case when exists(select 1 from #search_ids) then 'join #search_ids i2 on i2.id = x.plan_job_id' else '' end
		
	if @buffer_operation is  null
	begin
		-- @rowscount
        set @sql = N'select @rowscount = count(*) from v_mfr_plans_jobs x with(nolock) ' + @join + @where
        set @fields = @fields_base + ', @rowscount int out'

        exec sp_executesql @sql, @fields,
            @mol_id, @d_from, @d_to, @today, @place_id, @search,
            @rowscount out

				if @trace = 1 print @sql

		-- @order_by
			declare @order_by nvarchar(50) = N' order by x.plan_job_id'
			if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

			declare @subquery nvarchar(max) = N'
				(select x.* from v_mfr_plans_jobs x with(nolock) '
				+ @join + @where
				+' ) x ' + @order_by

			-- @sql
			set @sql = N'select x.* from ' + @subquery

			-- optimize on fetch
			if @rowscount > @fetchrows set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'

			set @fields = @fields_base + ', @offset int, @fetchrows int'

		if @trace = 1 print @sql
		
		exec sp_executesql @sql, @fields,
				@mol_id, @d_from, @d_to, @today, @place_id, @search,
				@offset, @fetchrows
	end

	else begin

		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

		set @rowscount = -1 -- dummy
		set @fields = @fields_base
					
		exec objs_buffer_viewhelper
			@buffer_operation = @buffer_operation, @obj_type = 'MFJ', @base_view = 'V_MFR_PLANS_JOBS', @pkey = 'PLAN_JOB_ID', @join = @join, @where = @where,
			@fields = @fields out, @sql = @sql out			

		exec sp_executesql @sql, @fields,
				@mol_id, @d_from, @d_to, @today, @place_id, @search,
				@buffer_id

	end -- buffer_operation

	exec drop_temp_table '#ids,#search_ids'
end
go
