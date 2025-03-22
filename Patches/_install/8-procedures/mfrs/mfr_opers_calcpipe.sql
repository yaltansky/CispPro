if object_id('mfr_opers_calcpipe') is not null drop proc mfr_opers_calcpipe
go
-- exec mfr_opers_calcpipe 1000, @trace = 1
create proc mfr_opers_calcpipe
	@mol_id int = null,
	@docs app_pkids readonly,
	@queue_id uniqueidentifier = null
as
begin
	set nocount on;

	-- buffer
		declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
		delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'MFR'

		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select @buffer_id, 'MFR', id, @mol_id
		from @docs

		declare @thread_id varchar(32) = (select thread_id from queues where queue_id = @queue_id)

	-- append
		declare @qid uniqueidentifier = newid()
		exec queue_append
			@queue_id = @qid,
			@mol_id = @mol_id,
			@thread_id = @thread_id,
			@name = 'Пересчёт графиков (заказы)',
			@sql_cmd = 'RMQ.mfr_opers_calc_docs',
			@use_rmq = 1

	-- parent_id
		update queues set parent_id = (select id from queues where queue_id = @queue_id)
		where queue_id = @qid

end
go
-- helper: prepare
create proc mfr_opers_calcpipe;10 
	@queue_id uniqueidentifier
as 
begin
	set nocount on;

	declare @today datetime = dbo.today()

	declare @docs_name varchar(50)
		exec mfr_opers_calcpipe;90 @queue_id, @docs_name = @docs_name out

	declare @sql nvarchar(max)

	-- #docs
		create table #docs(row_id int identity, id int primary key, doc_group_id int)
			
			insert into #docs(id) select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'MFR'
			order by obj_id
			
			if not exists(select 1 from #docs)
				insert into #docs(id) select doc_id from mfr_sdocs where plan_status_id = 1 and status_id >= 0
				order by doc_id

	-- /*** DEBUG ***/
		DELETE FROM #DOCS; 
		INSERT INTO #DOCS(id) SELECT 947

		update #docs set doc_group_id = row_id % 10

		set @sql = N'
			insert into @docs_name(mfr_doc_id, doc_group_id)
			select id, doc_group_id from #docs
			'
		set @sql = replace(@sql, '@docs_name', @docs_name)
		exec sp_executesql @sql

	-- normalize
		EXEC SYS_SET_TRIGGERS 0
			update x set mfr_doc_id = c.mfr_doc_id
			from sdocs_mfr_opers x
				join sdocs_mfr_contents c on c.content_id = x.content_id
					join #docs i on i.id = c.mfr_doc_id
			where x.mfr_doc_id != c.mfr_doc_id

			update x set status_id = 0 
			from sdocs_mfr_opers x
				join #docs i on i.id = x.mfr_doc_id
			where x.status_id is null
		EXEC SYS_SET_TRIGGERS 1

end
go
-- helper: get data
create proc mfr_opers_calcpipe;20
	@queue_id uniqueidentifier,
	@layer_id int,
	@doc_group_id int,
	@debug bit = 0
as
begin
	set nocount on;

	declare @today datetime = dbo.today()

	declare @docs_name varchar(50), @opers_name varchar(50)
		if @debug = 0 exec mfr_opers_calcpipe;90 @queue_id, @doc_group_id, @docs_name = @docs_name out

	-- #docs
		create table #docs(id int primary key)
			
			declare @sql nvarchar(max) = N'
				insert into #docs select mfr_doc_id from @docs_name
				where doc_group_id = @doc_group_id
				'
			set @sql = replace(@sql, '@docs_name', @docs_name)
			exec sp_executesql @sql, N'@doc_group_id int', @doc_group_id

	-- output
		declare @max_date date = dateadd(y, 1, dbo.today())

		select
		-- select top 10000
			LAYER_ID = @LAYER_ID,
			C.MFR_DOC_ID,
			C.PRODUCT_ID,
			O.OPER_ID,
			O.NEXT_ID,
			
			D_INITIAL = case @layer_id
				when 2 then @today 
				else sd.d_doc
			end,
			
			D_FINAL = case @layer_id
				when 1 then isnull(sd.d_ship, @max_date)
				when 3 then sd.d_issue_plan
			end,

			O.D_BEFORE,
			O.D_AFTER,
			DURATION = isnull(o.duration,1) * dur.factor,
			PROGRESS =
				case 
					when @layer_id = 1 then 0
					else
						case
							when c.is_buy = 0 then
								case when o.status_id = 100 then 1 else isnull(o.progress,0) end
							else 
								case when o.status_id >= 30 then 1 else isnull(o.progress,0) end
						end
				end,
			CALC_MODE_ID =
				case @layer_id
					when 2 then 1 -- EarlyStart
					else 2 -- LateStart
				end
		from sdocs_mfr_opers o
			join #docs i on i.id = o.mfr_doc_id
			join sdocs_mfr_contents c on c.content_id = o.content_id
				join sdocs sd on sd.doc_id = c.mfr_doc_id
			join projects_durations dur on dur.duration_id = o.duration_id
		where (@layer_id in (1,3) 
				-- условие для прогноза
				or 	(c.status_id < 30 and isnull(o.status_id,0) < 30)	-- для материалов Приход, ЛЗК, Выдано = Выдано
			)
			-- and o.oper_id = 41864762
		order by c.mfr_doc_id, c.product_id

end
go
-- helper: create temp tables
create proc mfr_opers_calcpipe;90
	@queue_id uniqueidentifier,
	@doc_group_id int = null,
	@docs_name varchar(50) = null out,
	@result_name varchar(50) = null out
as
begin

	set @docs_name = 'MFR_R_OPERS_DOCS'
	set @result_name = 'MFR_R_OPERS'

	declare @sql nvarchar(max)
			
	if @doc_group_id is null
	begin
		exec cisptmp..sp_msforeachtable 'drop table ?', @whereand = 'and (o.name like "mfr_r_opers%")'

		set @sql = replace('
			IF OBJECT_ID(''@DOCS_NAME'') IS NOT NULL DROP TABLE @DOCS_NAME;
			CREATE TABLE @DOCS_NAME(
				MFR_DOC_ID INT PRIMARY KEY,
				DOC_GROUP_ID INT INDEX IX_GROUP
			)', '@DOCS_NAME', @docs_name)

		exec sp_executesql @sql
	-- end

	-- else begin
		set @sql = replace('
			IF OBJECT_ID(''@RESULT_NAME'') IS NOT NULL DROP TABLE @RESULT_NAME;
			CREATE TABLE @RESULT_NAME(
				OPER_ID INT PRIMARY KEY,
				D_FROM DATETIME,
				D_TO DATETIME,
				DURATION_BUFFER FLOAT
			)', '@RESULT_NAME', @result_name)

		exec sp_executesql @sql
	end
end
go
-- helper: post process
create proc mfr_opers_calcpipe;100
	@queue_id uniqueidentifier,
	@layer_id int,
	@trace bit = 0
as
begin
	set nocount on;

	RETURN

	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
	declare @today datetime = dbo.today()

	create table #docs(id int primary key)
	insert into #docs select mfr_doc_id from mfr_r_opers_docs

	EXEC SYS_SET_TRIGGERS 0

		declare @query nvarchar(max) = N'
			declare @d_from datetime, @d_to datetime

			exec tracer_log @tid, ''update opers''
				update x set 
					?d_from = r.d_from,
					?d_to = r.d_to
					?duration_buffer
				from sdocs_mfr_opers x
					join mfr_r_opers r on r.oper_id = x.oper_id
				where (x.?d_from is null or x.?d_from != r.d_from)
					or (x.?d_to is null or x.?d_to != r.d_to)

			exec tracer_log @tid, ''calc base of items (by opers)''
				update x
				set ?opers_from = op.?opers_from,
					?opers_to = op.?opers_to
				from sdocs_mfr_contents x
					join (
						select 
							content_id,
							min(?d_from) as ?opers_from,
							max(?d_to) as ?opers_to
						from sdocs_mfr_opers op
							join #docs i on i.id = op.mfr_doc_id
						group by content_id
					) op on op.content_id = x.content_id
			
			exec tracer_log @tid, ''calc parents''
				update x
				set @d_from = isnull(x.?opers_from, xx.?opers_from),
					@d_to = isnull(x.?opers_to, xx.?opers_to),
					?opers_from = @d_from,
					?opers_to = @d_to					
				from sdocs_mfr_contents x
					join (
						select
							r.content_id,
							min(r2.?opers_from) as ?opers_from,
							max(r2.?opers_to) as ?opers_to
						from sdocs_mfr_contents r
							join #docs i on i.id = r.mfr_doc_id
							join sdocs_mfr_contents r2 on 
									r2.mfr_doc_id = r.mfr_doc_id
								and	r2.product_id = r.product_id
								and r2.node.IsDescendantOf(r.node) = 1
						where r.opers_count is null
						group by r.content_id
					) xx on xx.content_id = x.content_id
			'
		declare @sql nvarchar(max)

		if @layer_id = 1
		begin
			set @sql = @query
			set @sql = replace(@sql, '?d_from', 'd_from')
			set @sql = replace(@sql, '?d_to', 'd_to')
			set @sql = replace(@sql, '?opers_from', 'opers_from')
			set @sql = replace(@sql, '?opers_to', 'opers_to')
			set @sql = replace(@sql, '?duration_buffer', ', duration_buffer = r.duration_buffer')
			exec sp_executesql @sql, N'@tid int', @tid

			declare @days int

			update x
			set @days = datediff(d, opers_from, opers_to),
				opers_days = case when @days = 0 then 1 else @days end
			from sdocs_mfr_contents x
				join #docs i on i.id = x.mfr_doc_id
		end

		if @layer_id = 2
		begin
			exec tracer_log @tid, 'update opers'
				update x
				set d_from_predict = r.d_from,
					d_to_predict = r.d_to,
					duration_buffer_predict = r.duration_buffer
				from sdocs_mfr_opers x
					join mfr_r_opers r on r.oper_id = x.oper_id
				where (x.d_from_predict is null or x.d_from_predict != r.d_from)
					or (x.d_to_predict is null or x.d_to_predict != r.d_to)

			exec tracer_log @tid, 'calc childs'
				update x
				set opers_from_predict = op.opers_from_predict,
					opers_to_predict = op.opers_to_predict,
					duration_buffer_predict = op.duration_buffer_predict
				from sdocs_mfr_contents x
					join (
						select 
							content_id,
							min(d_from_predict) as opers_from_predict,
							max(d_to_predict) as opers_to_predict,
							max(duration_buffer_predict) as duration_buffer_predict
						from sdocs_mfr_opers op
							join #docs i on i.id = op.mfr_doc_id
						group by content_id
					) op on op.content_id = x.content_id
		
			exec tracer_log @tid, 'calc parents'
				update x
				set opers_from_predict = isnull(x.opers_from_predict, xx.opers_from_predict),
					opers_to_predict = isnull(x.opers_to_predict, xx.opers_to_predict)
				from sdocs_mfr_contents x
					join (
						select
							r.content_id,
							min(r2.opers_from_predict) as opers_from_predict,
							max(r2.opers_to_predict) as opers_to_predict
						from sdocs_mfr_contents r
							join #docs i on i.id = r.mfr_doc_id
							join sdocs_mfr_contents r2 on 
									r2.mfr_doc_id = r.mfr_doc_id
								and	r2.product_id = r.product_id
								and r2.node.IsDescendantOf(r.node) = 1
						where r.has_childs = 1
							and r.opers_count is null -- если у детали/узла нет операций, то наследуем от дочерних узлов
						group by r.content_id
					) xx on xx.content_id = x.content_id

				update x set
					opers_from_predict = opers_from, opers_to_predict = opers_to
				from sdocs_mfr_contents x
					join #docs i on i.id = x.mfr_doc_id
				where status_id = 100
					and (
						isnull(opers_from_predict,0) != opers_from
						or isnull(opers_to_predict,0) != opers_to
					)
		end

		if @layer_id = 3
		begin
			set @sql = @query
			set @sql = replace(@sql, '?d_from', 'd_from_plan')
			set @sql = replace(@sql, '?d_to', 'd_to_plan')
			set @sql = replace(@sql, '?opers_from', 'opers_from_plan')
			set @sql = replace(@sql, '?opers_to', 'opers_to_plan')
			set @sql = replace(@sql, '?duration_buffer', '')
			exec sp_executesql @sql, N'@tid int', @tid
		end

	exec tracer_log @tid, 'post process'

		-- D_ISSUE_CALC, D_ISSUE_FORECAST
			declare @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%готовая продукция%')

			update x
			set d_issue_calc = c.opers_to,
				d_issue_forecast = c.opers_to_predict
			from sdocs x
				join #docs i on i.id = x.doc_id
				join (
					select mfr_doc_id, 
						opers_to = max(isnull(d_to_fact, d_to)),
						opers_to_predict = max(isnull(d_to_fact, d_to_predict))
					from sdocs_mfr_opers
					where milestone_id = @attr_product
					group by mfr_doc_id
				) c on c.mfr_doc_id = x.doc_id

		-- sync milestones
			declare @ms_docs app_pkids; insert into @ms_docs select id from #docs
			exec mfr_milestones_calc @docs = @ms_docs

	EXEC SYS_SET_TRIGGERS 1

	final:
		exec drop_temp_table '#docs'
		if @trace = 1 exec tracer_view @tid
end
go

-- exec mfr_opers_calcpipe;20 null, 1, 9
-- exec mfr_opers_calcpipe;100 null, 1, @trace = 1

-- select
-- 	x.oper_id,
-- 	x.d_from, r.d_from,
-- 	x.d_to, r.d_to
-- from sdocs_mfr_opers x
-- 	left join mfr_r_opers r on r.oper_id = x.oper_id
-- where cast(x.d_from as date) != cast(r.d_from as date)
-- 	or cast(x.d_to as date) != cast(r.d_to as date)
