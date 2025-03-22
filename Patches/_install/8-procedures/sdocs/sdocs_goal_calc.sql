if object_id('sdocs_goal_calc') is not null drop proc sdocs_goal_calc
go
-- exec sdocs_goal_calc 700
create proc sdocs_goal_calc
	@mol_id int,
	@goal_id int = null,
	@stock_id int = null,
	@trace bit = 0
as
begin
	
	set nocount on;

	if @goal_id is null
		select @goal_id = goal_id from sdocs_goals
		where status_id = -2 -- mybook
			and mol_id = @mol_id

	if @stock_id is not null
		update sdocs_goals
		set stock_id = @stock_id
		where goal_id = @goal_id

	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @echo = @trace, @trace_id = @tid out
		declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
			' @mol_id=', @mol_id,
			' @goal_id=', @goal_id
			)
		exec tracer_log @tid, @tid_msg

exec tracer_log @tid, 'read params'
	declare @d_from datetime, @d_to datetime
	exec sdocs_goal_params @mol_id, @goal_id, @d_from out, @d_to out, @stock_id out

exec tracer_log @tid, 'build #details'
	create table #details(
        doc_id int,
		id_order int,
		d_order datetime,
		d_mfr datetime,
		d_ship datetime,
		stock_id int,
        product_id int,
		q_order decimal(18,2),
		v_order decimal(18,2),
		q_mfr decimal(18,2),
		q_issue decimal(18,2),		
		q_ship decimal(18,2)        
		)
		create index ix_details on #details(doc_id, stock_id, product_id)

-- #details
	declare @max_date datetime = '9999-12-31'

	insert into #details(doc_id, id_order, d_order, d_mfr, d_ship, stock_id, product_id, q_order, v_order, q_mfr, q_issue, q_ship)
	select 
		x.id_order, x.id_order, x.d_order, max(x.d_mfr), max(x.d_ship),
		x.stock_id, x.product_id, 
		sum(x.q_order), sum(x.v_order), sum(x.q_mfr), sum(x.q_issue), sum(x.q_ship)
	from sdocs_provides x
	where (@stock_id is null or x.stock_id = @stock_id)
		and x.id_order is not null
		and not (
			(
					isnull(x.d_mfr, @max_date) < @d_from
				and isnull(x.d_issue, @max_date) < @d_from
				and isnull(x.d_ship, @max_date) < @d_from
				and isnull(x.d_order, @max_date) < @d_from
			) or (
					isnull(x.d_mfr, @max_date) > @d_to
				and isnull(x.d_issue, @max_date) > @d_to
				and isnull(x.d_ship, @max_date) > @d_to
				and isnull(x.d_order, @max_date) > @d_to
			)
		)
	group by
		x.id_order, x.d_order, x.stock_id, x.product_id

exec tracer_log @tid, 'insert into sdocs_goals_details'
	delete from sdocs_goals_details where goal_id = @goal_id and mol_id = @mol_id

	insert into sdocs_goals_details(
		goal_id, mol_id, id_order, d_order, d_mfr, d_ship, stock_id, product_id, q_order, v_order, q_mfr, q_issue, q_ship
		)
	select 
		@goal_id, @mol_id,
		id_order, d_order, d_mfr, d_ship,
		stock_id, product_id,
		q_order, v_order, q_mfr, q_issue, q_ship
	from #details

-- sdocs_goals_sums
	create table #sums(
		parent_id int,
		node_id int index ix_node_id,
		name nvarchar(250),
		node hierarchyid,
		has_childs bit default (0),
		level_id int,
		is_deleted bit not null default(0),
		--
		doc_id int,
		d_order datetime,
		d_mfr datetime,
		d_ship datetime,
		q_order decimal(18,2),
		v_order decimal(18,2),
		q_mfr decimal(18,2),
        q_issue decimal(18,2),		
		q_ship decimal(18,2)
	)

	delete from sdocs_goals_sums where goal_id = @goal_id and mol_id = @mol_id

exec tracer_log @tid, 'build tree by sdocs_tree_orders'
	exec sdocs_goal_calc;10 @goal_id, @mol_id, 'sdocs_by_depts', @tid
	
exec tracer_close @tid
if @trace = 1 exec tracer_view @tid

	drop table #details, #sums
end
go

-- build tree by dictionary
create proc sdocs_goal_calc;10
	@goal_id int,
	@mol_id int,
	@dictionary_name sysname,
	@tid int
as
begin

	delete from #sums

	declare @column_id sysname = (
		select c.name
		from sys.columns c
			join (
				select ic.object_id, ic.column_id
				from sys.indexes i
					join sys.index_columns ic on ic.object_id = i.object_id and ic.index_id = i.index_id
				where i.is_primary_key = 1
			) ic on ic.object_id = c.object_id and ic.column_id = c.column_id
		where c.object_id = object_id(@dictionary_name)
		)

	if @column_id is null
	begin
		raiserror('Cannot find primary key index on dictionary name %s', 16, 1, @dictionary_name)
		return
	end

	declare @sql nvarchar(max) = N'	
	create table #rows(
		%COLUMN_ID int,
		d_order datetime,
		d_mfr datetime,
		d_ship datetime,
		q_order decimal(18,2),
		v_order decimal(18,2),
		q_mfr decimal(18,2),
		q_issue decimal(18,2),		
		q_ship decimal(18,2)
		)
		create index ix_details on #rows(%COLUMN_ID)

	insert into #rows(%COLUMN_ID, d_order, d_mfr, d_ship, q_order, v_order, q_mfr, q_issue, q_ship)
	select %COLUMN_ID, max(d_order), max(d_mfr), max(d_ship), sum(q_order), sum(v_order), sum(q_mfr), sum(q_issue), sum(q_ship)
	from #details
	group by %COLUMN_ID

	create table #map (node_id varchar(30), row_id int,
		constraint pk_map primary key (node_id)
		)

	declare @nodes table(
		row_id int identity primary key,
		%COLUMN_ID int,
		parent_id varchar(30), node_id varchar(30), name varchar(250), has_childs bit,
		node hierarchyid, level_id int)

	;with tree as (
		select distinct 
			a.parent_id, a.%COLUMN_ID, a.name, a.has_childs
			from %DICTIONARY_NAME a
				join #rows f on f.%COLUMN_ID = a.%COLUMN_ID
		UNION ALL
		select 
			t.parent_id, t.%COLUMN_ID, t.name, t.has_childs
		from %DICTIONARY_NAME t
			join tree on tree.parent_id = t.%COLUMN_ID
	)
	insert into @nodes(parent_id, node_id, %COLUMN_ID, name, has_childs)
		output inserted.node_id, inserted.row_id into #map
	select distinct
		case
			when parent_id is null then null
			else ''C'' + cast(parent_id as varchar)
		end 
		, ''C'' + cast(%COLUMN_ID as varchar)
		, %COLUMN_ID
		, name
		, has_childs
	from tree

	-- map parents
	update x
	set parent_id = m.row_id
	from @nodes x
		join #map m on m.node_id = x.parent_id

	insert into #sums(parent_id, node_id, %column_id, name, has_childs)
	select parent_id, row_id, %column_id, name, has_childs
	from @nodes

	update x
	set d_order = r.d_order,
		d_mfr = r.d_mfr,
		d_ship = r.d_ship,
		q_order = r.q_order,
		v_order = r.v_order,
		q_mfr = r.q_mfr,
		q_issue = r.q_issue,		
		q_ship = r.q_ship		
	from #sums x
		join (
			select 
				%column_id,
				max(d_order) d_order,
				max(d_mfr) d_mfr,
				max(d_ship) d_ship,
				sum(q_order) q_order,
				sum(v_order) v_order,
				sum(q_mfr) q_mfr,
				sum(q_issue) q_issue,
				sum(q_ship) q_ship
			from #rows
			group by %column_id
		) r on r.%column_id = x.%column_id

	drop table #map, #rows
	';

	set @sql = replace(@sql, '%column_id', @column_id)
	set @sql = replace(@sql, '%dictionary_name', @dictionary_name)

	exec sp_executesql @sql, N'@goal_id int, @mol_id int, @group_id varchar(32)',
		@goal_id, @mol_id, @dictionary_name

-- иерархия
	exec sdocs_goal_calc;20 @goal_id, @mol_id
	exec sdocs_goal_calc;30

-- result
	insert into sdocs_goals_sums(
		goal_id, mol_id, group_id, 
		id_order, d_order, d_mfr, d_ship,
		node, parent_id, node_id, name, has_childs, level_id,
		q_order, v_order, q_mfr, q_issue, q_ship
		)
	select 
		@goal_id, @mol_id, @dictionary_name,
		doc_id, d_order, d_mfr, d_ship,
		node, parent_id, node_id, name, has_childs, level_id,
		q_order, v_order, q_mfr, q_issue, q_ship
	from #sums

end
go

-- build local tree
create proc sdocs_goal_calc;20
	@goal_id int,
	@mol_id int
as
begin

	declare @children tree_nodes
		insert into @children(node_id, parent_id, num)
		select node_id, parent_id,  
			row_number() over (partition by parent_id order by parent_id, name)
		from #sums

	declare @nodes tree_nodes
	insert into @nodes exec tree_calc @children

	update x
	set node = xx.node,
		level_id = xx.node.GetLevel()
	from #sums x
		join @nodes as xx on xx.node_id = x.node_id

end
go

-- summary of parents
create proc sdocs_goal_calc;30
as
begin

	update x
	set q_order = r.q_order,
		v_order = r.v_order,
		q_mfr = r.q_mfr,
        q_issue = r.q_issue,		
		q_ship = r.q_ship		
	from #sums x
		join (
			select y2.node_id, 				
				sum(y1.q_order) as q_order,
				sum(y1.v_order) as v_order,
				sum(y1.q_mfr) as q_mfr,
                sum(y1.q_issue) as q_issue,				
				sum(y1.q_ship) as q_ship
			from #sums y2
				join #sums y1 on 
						y2.has_childs = 1
					and y1.node.IsDescendantOf(y2.node) = 1
					and y1.has_childs = 0
			group by y2.node_id
		) r on r.node_id = x.node_id
end
go
