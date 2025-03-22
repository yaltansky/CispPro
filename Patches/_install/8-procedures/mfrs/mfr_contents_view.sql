if object_id('mfr_contents_view') is not null drop proc mfr_contents_view
go
-- exec mfr_contents_view @doc_id = 13285442, @extra_id = 1
create proc mfr_contents_view
	@doc_id int,
	@product_id int = null,
	@root_id int = null,
	@parent_id int = null,
	@milestone_id int = null,
	@attr_id int = null,
	@search nvarchar(max) = null,
	@view_id int = null,
		-- id: 1, name: 'Базовый план'
		-- id: 4,20, name: 'План ПДО'
		-- id: 30, name: 'Оперативный план'
		-- id: 2,40, name: 'Прогнозный план'
		-- id: 3,50, name: 'Сопоставление Базовый-Прогноз'
		-- id: 60, name: 'Сопоставление Оперативный-Прогноз'
	@extra_id int = null
        -- 1 Критический путь
        -- 2 ABC: анализ
        -- 4 Отставание
        -- 6 Переделы
        -- 7 Диаграмма Ганта
as 
begin
	set nocount on;
	set transaction isolation level read uncommitted;

	declare @critical_buffer int = isnull(cast((select dbo.app_registry_value('MfrCriticalBuffer')) as int), 5)

	if @product_id is null 
		and 1 = (select count(distinct product_id) from sdocs_products where doc_id = @doc_id)
	begin
		set @product_id = (select top 1 product_id from sdocs_products where doc_id = @doc_id)
	end

	create table #result(
		-- keys
			row_id int identity,
			content_id int index ix_content,
		-- tree
			node_initial hierarchyid,
			node hierarchyid,
			node_id int,
			parent_id int,
			has_childs bit not null default(0),
			name nvarchar(500),
			level_id int,
			sort_id float,
			is_deleted bit not null default(0),
		-- base
			plan_id int,
			mfr_doc_id int,
			product_id int,
			pdm_id int,
			draft_id int,
			child_id int,
			item_type_id int,
			item_type_name varchar(50),
			item_id int,
			status_id int,
			status_name varchar(30),
			status_css varchar(50),
			status_style varchar(50),
			is_buy bit,
			unit_name varchar(20),
			q_brutto float,
			q_brutto_product float,
			w_brutto float,
			item_value0 decimal(18,2),
			item_value0_part decimal(18,2),		
		-- dates
			opers_from date,
			opers_to date,
			duration_buffer int,
			opers_days float,
			opers_count int,
        -- dates compare
			opers_to1 date,
			opers_to2 date,
			opers_to_diff int,
		-- misc
			talk_id int,
			is_milestone bit,
			slice char(1)
		)

	-- ABC: анализ
	if @extra_id = 2 
		exec mfr_contents_view;2 @doc_id = @doc_id, @product_id = @product_id, @view_id = @view_id
	
	-- Переделы
	else if @extra_id = 6
		exec mfr_contents_view;6 @doc_id = @doc_id, @product_id = @product_id

	-- Состав изделия
	else begin

		declare @root hierarchyid = (select top 1 node from sdocs_mfr_contents where mfr_doc_id = @doc_id and product_id = @product_id and child_id = @root_id)
		declare @result table (id int index ix_id, node hierarchyid index ix_node)

		if @parent_id is not null
		begin
			insert into @result
			select x.content_id, x.node
			from sdocs_mfr_contents x
			where x.mfr_doc_id = @doc_id
				and x.product_id = @product_id
				and isnull(x.parent_id,0) = @parent_id
		end
	
		else if @search is null
			and @milestone_id is null
			and @attr_id is null
			and isnull(@view_id, 1) = 1
			and @extra_id is null
		begin
			insert into @result
			select content_id, node
			from sdocs_mfr_contents
			where mfr_doc_id = @doc_id
				and product_id = @product_id
				and isnull(parent_id,0) = coalesce(@parent_id, @root_id, 0)
		end

		else
		begin
			declare @content_id int = dbo.hashid(@search)
			declare @item_id int

			if @content_id is not null set @search = null
			else if substring(@search, 1, 5) = 'item#' begin
				set @item_id = try_cast(substring(@search, 6, 255) as int)
				set @search = null
			end
			else begin
				set @search = '%' + replace(@search, ' ', '%') + '%'
				set @search = replace(@search, '[', '')
				set @search = replace(@search, ']', '')
			end

			declare @contents_view as table(
				content_id int primary key, is_buy bit, opers_to_diff int,
				index ix (is_buy, content_id)
				)
            declare @contents_view_found as app_pkids

				if @view_id in (3,50) -- 'Сопоставление Базовый-Прогноз'
				begin
					insert into @contents_view(content_id, opers_to_diff, is_buy)
					select content_id, datediff(d, opers_to_predict, opers_to), is_buy
					from sdocs_mfr_contents x
					where mfr_doc_id = @doc_id
						and product_id = @product_id
						and is_deleted = 0

					if @extra_id = 4
					begin
						;with 
							max_delay1 as (
								select min(opers_to_diff) as max_delay from @contents_view where is_buy = 0 and opers_to_diff < 0
								),
							max_delay2 as (
								select min(opers_to_diff) as max_delay from @contents_view where is_buy = 1 and opers_to_diff < 0
								),
							found as (
								select content_id from @contents_view, max_delay1 where is_buy = 0 and opers_to_diff between max_delay and max_delay/2
								union 
								select content_id from @contents_view, max_delay2 where is_buy = 1 and opers_to_diff between max_delay and max_delay/2
								)
						insert into @contents_view_found(id)
						select distinct content_id from found
					end
				end

				if @view_id = 60 -- 'Сопоставление Оперативный-Прогноз'
				begin
					insert into @contents_view(content_id, opers_to_diff, is_buy)
					select content_id, datediff(d, opers_to_predict, opers_to_ploper), is_buy
					from sdocs_mfr_contents x
					where mfr_doc_id = @doc_id
						and product_id = @product_id
						and is_deleted = 0
				end

			declare @contents_ms as table(
				content_id int primary key, mfr_doc_id int, product_id int, node hierarchyid,
				index ix_node(mfr_doc_id, product_id, node)
				)

				if @milestone_id is not null
				begin
					insert into @contents_ms
					select content_id, mfr_doc_id, product_id, node
					from sdocs_mfr_contents x
					where mfr_doc_id = @doc_id and product_id = @product_id
						and exists(select 1 from sdocs_mfr_opers where content_id = x.content_id and milestone_id = @milestone_id)

					if isnull(@view_id,1) in (2,40) -- 'Прогнозный план'
						insert into @contents_ms
						select distinct x.content_id, x.mfr_doc_id, x.product_id, x.node
						from sdocs_mfr_contents x
							join @contents_ms ms on ms.mfr_doc_id = x.mfr_doc_id and ms.product_id = x.product_id and x.node.IsDescendantOf(ms.node) = 1
						where not exists(select 1 from @contents_ms where content_id = x.content_id)
							and x.status_id not in (-1, 100) -- не завершённые детали/материалы
				end
			
            declare @attr_gantt int = (select attr_id from prodmeta_attrs where code = 'NodeGantt');

			insert into @result
				select x.content_id, x.node
				from sdocs_mfr_contents x
					join products p2 on p2.product_id = x.item_id
					left join @contents_view xv on xv.content_id = x.content_id
					left join mfr_drafts d on d.draft_id = x.draft_id
				where x.mfr_doc_id = @doc_id
					and x.product_id = @product_id				
					and (@root_id is null or x.node.IsDescendantOf(@root) = 1)
					and (@content_id is null or x.content_id = @content_id)
					and (@item_id is null or x.item_id = @item_id)
					and (
						isnull(@view_id,1) in (1,4,20) -- Базовый, ПДО
						or (
							@view_id = 30 -- Оперативный план
							and (x.opers_from_ploper is not null) -- есть оперативный план
							)
						or (
							@view_id in (2,40) -- Прогнозный план
							and (x.opers_from_predict is not null) -- есть прогноз
							)
						or (
							@view_id in (3,50) -- 'Сопоставление Базовый-Прогноз'
							-- and xv.opers_to_diff != 0
							)
						or (
							@view_id = 60 -- 'Сопоставление Оперативный-Прогноз'
                            -- and xv.opers_to_diff != 0
							)
						)
					and (@search is null 
							or x.name like @search 
							or p2.name like @search
						)
					and (
						@milestone_id is null
						or exists(select 1 from @contents_ms where content_id = x.content_id)
						)
					and (
						@attr_id is null
						or exists(select 1 from sdocs_mfr_contents_attrs where content_id = x.content_id and attr_id = @attr_id)
						)
					and (
						@extra_id is null
						-- Критический путь (базовый)
						or (@extra_id = 1 and isnull(@view_id,1) = 1 and x.duration_buffer <= @critical_buffer)						
						-- Критический путь (ПДО)
						or (@extra_id = 1 and @view_id in (4,20) and x.duration_buffer <= @critical_buffer)
						-- Критический путь (оперативный)
						or (@extra_id = 1 and @view_id = 30 and x.duration_buffer_ploper <= @critical_buffer)
						-- Критический путь (прогноз)
						or (@extra_id = 1 and @view_id in (2,40) and x.duration_buffer_predict <= @critical_buffer)

						-- Критический путь (сопоставление базовый-прогноз)
						or (@extra_id = 1 and @view_id in (3,50) and x.duration_buffer_predict <= @critical_buffer)
						-- Отставание (сопоставление базовый-прогноз)
						or (@extra_id = 4 and @view_id in (3,50) and (
							exists(select 1 from @contents_view_found where id = x.content_id)
							))

						-- Критический путь (сопоставление оперативный-прогноз)
						or (@extra_id = 1 and @view_id = 60 and x.duration_buffer_predict <= @critical_buffer)

						-- Переделы
						or (@extra_id = 6 and exists(select 1 from sdocs_mfr_opers where content_id = x.content_id and milestone_id is not null))
                        
                        -- Диаграмма Ганта
                        or (@extra_id = 7 and 
                            x.content_id in (select content_id from sdocs_mfr_contents_attrs where attr_id = @attr_gantt))
						)
					and x.is_deleted = 0
					
			-- get all parents
			declare @parents as table(content_id int primary key, node hierarchyid index ix_node)
				insert into @parents(content_id, node)
				select content_id, node
				from sdocs_mfr_contents
				where mfr_doc_id = @doc_id
					and product_id = @product_id
					and has_childs = 1
					and is_deleted = 0

			insert into @result(id, node)
				select distinct x.content_id, x.node
				from @parents x
					join @result r on r.node.IsDescendantOf(x.node) = 1
				where not exists(select 1  from @result where id = x.content_id)
		end

		-- result
		insert into #result(
			node_initial, node,
			content_id, parent_id, has_childs, name, level_id,
			plan_id, mfr_doc_id, product_id, pdm_id, draft_id, child_id, item_type_id, item_id, status_id, is_buy,
			unit_name, q_brutto, q_brutto_product, item_value0, item_value0_part, opers_count, opers_days,
			opers_from, opers_to, duration_buffer,
			opers_to1, opers_to2, opers_to_diff,
			node_id, item_type_name,
			talk_id, is_milestone
			)
		select
			x.node,
			concat('/', 
				row_number() over (order by x.has_childs desc, x.item_value0 desc),
				'/'
				),
			x.content_id, x.parent_id, x.has_childs, x.name, x.level_id,
			x.plan_id, x.mfr_doc_id, x.product_id, d.pdm_id, x.draft_id, x.child_id, x.item_type_id, x.item_id, x.status_id, x.is_buy,
			x.unit_name, x.q_brutto, x.q_brutto_product, x.item_value0, x.item_value0_part, x.opers_count, x.opers_days,
			x.opers_from, x.opers_to, x.duration_buffer,
			
            case when @view_id = 60 then x.opers_to_ploper else x.opers_to end,
            x.opers_to_predict,
            x3.opers_to_diff,

			node_id = x.child_id,
			item_type_name = it.name,
			x.talk_id,
			x.is_milestone
		from sdocs_mfr_contents x
			left join @contents_view x3 on x3.content_id = x.content_id
			left join mfr_items_types it on it.type_id = x.item_type_id
			left join mfr_drafts d on d.draft_id = x.draft_id
		where x.content_id in (select id from @result)
			and x.is_deleted = 0
	end

-- post-process
	if @view_id in (4,20) -- ПДО
		update x set
			opers_from = c.opers_from_plan,
			opers_to = c.opers_to_plan,
			opers_days = dbo.work_day_diff(c.opers_from_plan, c.opers_to_plan) + 1
        from #result x
            join sdocs_mfr_contents c on c.content_id = x.content_id

	else if @view_id = 30 -- оперативный
		update x set
			opers_from = c.opers_from_ploper,
			opers_to = c.opers_to_ploper,
			opers_days = dbo.work_day_diff(c.opers_from_ploper, c.opers_to_ploper) + 1,
			duration_buffer = c.duration_buffer_ploper
        from #result x
            join sdocs_mfr_contents c on c.content_id = x.content_id

	else if @view_id in (2,40) -- прогноз
		update x set
			opers_from = c.opers_from_predict,
			opers_to = c.opers_to_predict,
			opers_days = dbo.work_day_diff(c.opers_from_predict, c.opers_to_predict) + 1,
			duration_buffer = c.duration_buffer_predict
        from #result x
            join sdocs_mfr_contents c on c.content_id = x.content_id

    else    
		update x set
			opers_days = dbo.work_day_diff(c.opers_from, c.opers_to) + 1
        from #result x
            join sdocs_mfr_contents c on c.content_id = x.content_id

	update x set status_name = s.name, status_css = s.css, status_style = s.style
	from #result x
		join mfr_items_statuses s on s.status_id = x.status_id

	if @root_id is not null
		update #result set level_id = level_id - @root.GetLevel()

-- select
	select * from #result order by node
	drop table #result
end
GO
-- helper: ABC-анализ
create proc mfr_contents_view;2
	@doc_id int,
	@product_id int,
	@view_id int = null
as
begin

	declare @items table(
		row_id int identity,
		content_id int primary key,
		item_group_id int,
		is_buy bit,
		item_value0 decimal(18,2),
		duration_buffer int,
		slice char(1)
		)

		insert into @items(content_id, item_group_id, is_buy, item_value0, duration_buffer)
		select x.content_id, it.group_id, x.is_buy, x.item_value0, x.duration_buffer
		from sdocs_mfr_contents x
			left join mfr_items_types it on it.type_id = x.item_type_id
		where x.mfr_doc_id = @doc_id
			and x.product_id = @product_id
			and x.is_deleted = 0
		order by x.item_value0 desc

	declare @max_id int = (select max(row_id) from @items)
	
	update @items set slice = 'D' where isnull(item_group_id,1) != 1 or is_buy = 1
	update @items set slice = 'A' where slice is null and row_id < @max_id * 0.05
	update @items set slice = 'B' where slice is null and (row_id < @max_id * 0.15 or duration_buffer = 0)
	update @items set slice = 'C' where slice is null
	
	declare @slice table(slice char(1) primary key, name varchar(50), slice_id int, path varchar(10))
		insert into @slice
		values 
			('A', 'ABC: КЛЮЧЕВЫЕ ДЕТАЛИ', -1, '/1/'),
			('B', 'ABC: БАЗОВЫЕ ДЕТАЛИ', -2, '/2/'),
			('C', 'ABC: ПРОЧИЕ ДЕТАЛИ', -3, '/3/'),
			('D', 'ABC: МАТЕРИАЛЫ', -4, '/4/')

	insert into #result(
		node,
		content_id, node_id, parent_id, name,
		plan_id, mfr_doc_id, product_id, draft_id, child_id, item_type_id, item_type_name, item_id, status_id, is_buy, unit_name,
		q_brutto, q_brutto_product, item_value0, item_value0_part, opers_count, opers_days, opers_from, opers_to,
		duration_buffer,
		has_childs, slice
		)
	select
		concat(slice.path, 
			row_number() over (order by x.has_childs desc, x.item_value0 desc),
			'/'
			),
		x.content_id,
		node_id = x.child_id,
		parent_id = slice.slice_id,
		x.name,
		x.plan_id,
		x.mfr_doc_id,
		x.product_id,
		x.draft_id,
		x.child_id,
		x.item_type_id,
		item_type_name = it.name,
		x.item_id,
		x.status_id,
		x.is_buy,
		x.unit_name,
		x.q_brutto,
		x.q_brutto_product,
		x.item_value0,
		x.item_value0_part,
		x.opers_count,
		x.opers_days,
		x.opers_from,
		x.opers_to,
		x.duration_buffer,
		x.has_childs,
		i.slice
	from sdocs_mfr_contents x
		left join mfr_items_types it on it.type_id = x.item_type_id
		left join sdocs_mfr_drafts d on d.draft_id = x.draft_id
		join @items i on i.content_id = x.content_id
			join @slice slice on slice.slice = i.slice	

	declare @SUM_ITEMS_VALUE decimal(18,2) = (select sum(item_value0) from #result)
	
	insert into #result(
		node,
		mfr_doc_id, product_id, content_id, node_id, name, has_childs, status_id, item_value0, item_value0_part
		)
	select 
		a.path,
		@doc_id, @product_id, slice_id, slice_id, name, 1, 0,
		r.item_value0,
		r.item_value0 / nullif(@SUM_ITEMS_VALUE,0)
	from @slice a
		join (
			select slice, sum(item_value0) as item_value0
			from #result
			group by slice
		) r on r.slice = a.slice
end
go
-- helper: Переделы
create proc mfr_contents_view;6
	@doc_id int,
	@product_id int
as
begin

	declare @items table(
		row_id int identity,
		content_id int primary key,
		slice int
		)

		insert into @items(content_id, slice)
		select x.content_id, max(o.milestone_id)
		from sdocs_mfr_contents x
			join sdocs_mfr_opers o on o.content_id = x.content_id
				join mfr_milestones ms on ms.milestone_id = o.milestone_id
		where x.mfr_doc_id = @doc_id
			and x.product_id = @product_id
		group by x.content_id

	declare @slice table(slice int primary key, name varchar(100), slice_id int, path varchar(20))
	insert into @slice(slice, name, slice_id, path)
	select milestone_id, name, -milestone_id,
		concat('/', row_number() over (order by name),'/')
	from mfr_milestones
	
	insert into #result(
		node, slice,
		content_id, node_id, parent_id, name,
		plan_id, mfr_doc_id, product_id, draft_id, item_id, status_id, is_buy, unit_name,
		q_brutto_product, item_value0, opers_count, opers_days, opers_from, opers_to,
		duration_buffer,
		has_childs,
		is_milestone
		)
	select
		concat(slice.path, 
			row_number() over (order by x.has_childs desc, x.name),
			'/'
			),
		slice.slice,
		x.content_id,
		node_id = x.child_id,
		parent_id = slice.slice_id,
		x.name,
		-- 
		x.plan_id,
		x.mfr_doc_id,
		x.product_id,
		x.draft_id,
		x.item_id,
		x.status_id,
		x.is_buy,		
		x.unit_name,
		-- 
		x.q_brutto_product,
		x.item_value0,
		x.opers_count,
		x.opers_days,
		x.opers_from,
		x.opers_to,
		-- 
		x.duration_buffer,
		-- 
		x.has_childs,
		--
		x.is_milestone
	from sdocs_mfr_contents x
		join @items i on i.content_id = x.content_id
			join @slice slice on slice.slice = i.slice

	insert into #result(
		node,
		mfr_doc_id, product_id, content_id, node_id, name, has_childs, status_id,
		q_brutto_product, opers_from, opers_to, item_value0
		)
	select 
		a.path,
		@doc_id, @product_id, slice_id, slice_id, name, 1, r.status_id,
		q_brutto_product, opers_from, opers_to, item_value0
	from @slice a
		join (
			select parent_id,
				status_id = min(status_id),
				q_brutto_product = sum(q_brutto_product),
				opers_from = min(opers_from),
				opers_to = max(opers_to),
				item_value0 = sum(item_value0)
			from #result
			group by parent_id
		) r on r.parent_id = a.slice_id

	update #result set level_id = node.GetLevel() - 1
end
go
