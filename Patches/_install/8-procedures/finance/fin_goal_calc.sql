if object_id('fin_goal_calc') is not null drop proc fin_goal_calc
go
-- exec fin_goal_calc 700, 3, 15781
create proc fin_goal_calc
	@mol_id int,
	@fin_goal_id int = null,
	@folder_id int = null,
	@calcallgroups bit = 0,
	@trace bit = 0
as
begin
	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	if @fin_goal_id is null
		select @fin_goal_id = fin_goal_id from fin_goals
		where status_id = -2 -- mybook
			and mol_id = @mol_id

	if @folder_id is not null
		update fin_goals
		set folder_id = @folder_id
		where fin_goal_id = @fin_goal_id

	declare @tid int; exec tracer_init 'fin_goal_calc', @trace_id = @tid out

    exec tracer_log @tid, 'read params'
        declare @prev_id int,
            @book_d_from datetime, @book_d_to datetime,
            @d_from datetime, @d_to datetime

            select 
                @prev_id = parent_id,
                @book_d_from = d_from,
                @book_d_to = d_to,
                @folder_id = folder_id
            from fin_goals where fin_goal_id = @fin_goal_id

            -- auto-create mols params
            if not exists(select 1 from fin_goals_mols where fin_goal_id = @fin_goal_id and mol_id = @mol_id)
                insert into fin_goals_mols(fin_goal_id, mol_id, d_from, d_to)
                values (@fin_goal_id, @mol_id, @book_d_from, @book_d_to)

            select 
                @d_from = isnull(d_from, @book_d_from),
                @d_to = isnull(d_to, @book_d_to),
                @folder_id = isnull(folder_id, @folder_id)
            from fin_goals_mols where fin_goal_id = @fin_goal_id and mol_id = @mol_id

    -- @objects by reglament
        declare @objects as app_objects
        insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id

    -- @subjects
        declare @subjects as app_pkids
        insert into @subjects select subject_id from fin_goals where fin_goal_id = @fin_goal_id
        if exists(select 1 from @subjects where id = -2)
        begin
            delete from @subjects
            insert into @subjects select subject_id from subjects where subject_id > 0
                and subject_id in (select obj_id from @objects where obj_type = 'sbj')
        end

    -- @budgets
        declare @budgets as app_pkids
        insert into @budgets select distinct obj_id from @objects where obj_type = 'bdg'
        
        declare @all_budgets bit = case when exists(select 1 from @budgets where id = -1) then 1 else 0 end
            
        create table #fact(
            folder_id int default 0,
            goal_account_id int,
            budget_id int,
            article_id int,
            value_start decimal(18,2),
            value_in decimal(18,2),
            value_out decimal(18,2)        
            )
            create index ix_fact on #fact(folder_id, goal_account_id, budget_id, article_id)

    exec tracer_log @tid, 'build #folders'
        -- folder_id
        create table #folders(folder_id int, parent_id int, name varchar(50), has_childs bit)
        create table #folders_details(findoc_id int primary key, folder_id int)

        declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')

        if @folder_id is null
        begin
            insert into #fact(goal_account_id, budget_id, article_id, value_in, value_out)
            select 
                f.goal_account_id, f.budget_id, f.article_id,
                sum(case when f.value_rur > 0 then f.value_rur end) as value_in,
                sum(case when f.value_rur < 0 then f.value_rur end) as value_out
            from findocs# f
                join findocs_accounts fa on fa.account_id = f.account_id
            where f.d_doc between @d_from and @d_to			
                -- reglament
                and f.subject_id in (select id from @subjects)
                and (@all_budgets = 1 or f.budget_id in (select id from @budgets))
                and fa.name <> @vat_refund
            group by f.goal_account_id, f.budget_id, f.article_id
        end
        
        else begin
                
            declare @keyword varchar(50) = (select keyword from objs_folders where folder_id = @folder_id)
            declare @folder hierarchyid = (select node from objs_folders where folder_id = @folder_id)
                
            -- #folders
            insert into #folders(folder_id, parent_id, name, has_childs)
            select folder_id, parent_id, name, has_childs
            from objs_folders
            where node.IsDescendantOf(@folder) = 1			
                and keyword = @keyword
                and is_deleted = 0

            -- #folders_details
            insert into #folders_details(findoc_id, folder_id)
            select fd.obj_id, max(f.folder_id)
            from objs_folders_details fd
                join #folders f on f.folder_id = fd.folder_id and f.has_childs = 0
            where fd.obj_type = 'fd'
            group by fd.obj_id

            -- #fact
            insert into #fact(folder_id, goal_account_id, budget_id, article_id, value_in, value_out)
            select 
                fd.folder_id, f.goal_account_id, f.budget_id, f.article_id,
                sum(case when f.value_rur > 0 then f.value_rur end) as value_in,
                sum(case when f.value_rur < 0 then f.value_rur end) as value_out
            from findocs# f
                join #folders_details fd on fd.findoc_id = f.findoc_id
            where 
                -- reglament
                (@all_budgets = 1 or f.budget_id in (select id from @budgets))
            group by fd.folder_id, f.goal_account_id, f.budget_id, f.article_id
        end

    exec tracer_log @tid, 'считаем вх.остатки по бюджетам'
        create table #lefts (
            folder_id int,
            goal_account_id int default 0, budget_id int, article_id int,
            value_start decimal(18,2), 
            primary key clustered (goal_account_id, budget_id, article_id)
            )

        if @folder_id is null
        begin
            declare @lefts_d_from datetime = 
                case
                    when @prev_id is not null then @book_d_from
                    else 0
                end

            -- auto-calc outgoing lefts
            if not exists(select 1 from fin_goals_lefts where fin_goal_id = @prev_id)
                exec fin_goal_lefts_calc @prev_id

            insert into #lefts(goal_account_id, budget_id, article_id, value_start)
            select goal_account_id, budget_id, article_id, sum(value_start)
            from (
                -- входящие остатки книги
                select isnull(goal_account_id,0) as goal_account_id, budget_id, article_id, isnull(value_end, value_end_calc) as value_start
                from fin_goals_lefts
                where fin_goal_id = @prev_id

                UNION ALL
                -- обороты за период внутри книги
                select f.goal_account_id, f.budget_id, f.article_id, sum(f.value_rur) as value_start
                from findocs# f
                    join findocs_accounts fa on fa.account_id = f.account_id
                    join budgets b on b.budget_id = f.budget_id
                where (f.d_doc >= @lefts_d_from and f.d_doc < @d_from)
                    -- reglament
                    and f.subject_id in (select id from @subjects)
                    and (@all_budgets = 1 or f.budget_id in (select id from @budgets))
                    and fa.name <> @vat_refund
                group by f.goal_account_id, f.budget_id, f.article_id
                having cast(sum(f.value_rur) as decimal) <> 0
                ) u
            group by goal_account_id, budget_id, article_id
        end

    exec tracer_log @tid, 'insert into fin_goals_details'
        delete from fin_goals_details where fin_goal_id = @fin_goal_id and mol_id = @mol_id

        insert into fin_goals_details(
            fin_goal_id, mol_id, folder_id, goal_account_id, budget_id, article_id, value_start, value_in, value_out, value_end
            )
        select 
            @fin_goal_id, @mol_id,
            folder_id, goal_account_id, budget_id, article_id,
            value_start, value_in, value_out,
            value_start + value_in + value_out
        from (
            select
                folder_id,
                goal_account_id,
                budget_id,
                article_id,
                value_start = isnull(sum(value_start), 0),
                value_in = isnull(sum(value_in), 0),
                value_out = isnull(sum(value_out), 0)
            from (
                select
                    folder_id = 0,
                    goal_account_id = isnull(goal_account_id,0),
                    budget_id,
                    article_id,
                    value_start,
                    value_in = cast(0 as float),
                    value_out = cast(0 as float)
                from #lefts

                union all
                select 
                    folder_id,
                    goal_account_id = isnull(goal_account_id, 0),
                    budget_id,
                    article_id,
                    value_start,
                    value_in,
                    value_out
                from #fact
                ) u
            group by folder_id, goal_account_id, budget_id, article_id
            ) uu
        
        delete from fin_goals_details
        where fin_goal_id = @fin_goal_id
            and mol_id = @mol_id
            and cast(abs(isnull(value_start,0)) + abs(isnull(value_in,0)) + abs(isnull(value_out,0)) + abs(isnull(value_end,0)) as decimal(18,2)) = 0.00

    -- fin_goals_sums
        delete from fin_goals_sums where fin_goal_id = @fin_goal_id and mol_id = @mol_id

    if @calcallgroups = 1
    begin
        exec tracer_log @tid, 'build tree by bdr_articles'
        exec fin_goal_calc;10 @fin_goal_id, @mol_id, 'bdr_articles', @tid
    end

    exec tracer_log @tid, 'build tree by budgets_by_vendors'
        exec fin_goal_calc;10 @fin_goal_id, @mol_id, 'budgets_by_vendors', @tid
        
    exec tracer_close @tid
    if @trace = 1 exec tracer_view @tid

    drop table #fact, #folders, #folders_details, #lefts
end
go
-- helper: build tree by dictionary
create proc fin_goal_calc;10
	@fin_goal_id int,
	@mol_id int,
	@group_id varchar(50),
	@tid int = null
as
begin

	create table #sums(
		folder_id int,
		goal_account_id int,
		article_id int,
		budget_id int index ix_budget,
		excluded bit default(0),
		--
		parent_id int,
		node hierarchyid,
		node_id int index ix_node_id,
		name nvarchar(250),
		has_childs bit default (0),
		level_id int,
		is_deleted bit,
		sort_id float,
		--
		value_start decimal(18,2),
		value_in decimal(18,2),
		value_out decimal(18,2),	
		value_end decimal(18,2),
		value_in_excl decimal(18,2),
		value_out_excl decimal(18,2),
		)
		create index ix_folder1 on #sums(folder_id, budget_id)

	declare @column_id sysname = 
        case
            when @group_id = 'bdr_articles' then 'article_id'
            when @group_id = 'budgets_by_vendors' then 'budget_id'
            when @group_id = 'fin_goals_accounts' then 'goal_account_id'
        end;

	if @column_id is null
	begin
		raiserror('Cannot find primary key index on dictionary name %s', 16, 1, @group_id)
		return
	end

	declare @folder_id int = isnull(
		(select folder_id from fin_goals where fin_goal_id = @fin_goal_id),
		(select folder_id from fin_goals_mols where fin_goal_id = @fin_goal_id and mol_id = @mol_id)
		)

	declare @sql nvarchar(max) = N'	
	declare @folder hierarchyid = (select node from objs_folders where folder_id = @folder_id)
	declare @has_folders bit = case when ''%DICTIONARY_NAME'' = ''budgets_by_vendors'' then 1 else 0 end

	create table #details(
		folder_id int,
		%COLUMN_ID int,
		value_start decimal(18,2),
		value_in decimal(18,2),
		value_out decimal(18,2),
		value_end decimal(18,2)
		)
		create index ix_details on #details(folder_id, %COLUMN_ID)

	insert into #details(folder_id, %COLUMN_ID, value_start, value_in, value_out, value_end)
	select isnull(folder_id,0), %COLUMN_ID, sum(value_start), sum(value_in), sum(value_out), sum(value_end)
	from (
		select
			case when @has_folders = 1 then folder_id else @folder_id end as folder_id,
			%COLUMN_ID, value_start, value_in, value_out, value_end
		from fin_goals_details
		where fin_goal_id = @fin_goal_id
			and mol_id = @mol_id
		) x
	group by folder_id, %COLUMN_ID

	create table #map (folder_id int, node_id varchar(30), row_id int,
		constraint pk_map primary key (folder_id, node_id)
		)

	declare @nodes table(
		row_id int identity primary key,
		folder_id int, %COLUMN_ID int,
		parent_id varchar(30), node_id varchar(30), name varchar(250), has_childs bit,
		node hierarchyid, level_id int)

	;with tree as (
		select distinct 
			folder_id, a.parent_id, a.%COLUMN_ID, a.name, a.has_childs
			from %DICTIONARY_NAME a
				join #details f on f.%COLUMN_ID = a.%COLUMN_ID
		UNION ALL
		select 
			tree.folder_id,
			t.parent_id, t.%COLUMN_ID, t.name, t.has_childs
		from %DICTIONARY_NAME t
			join tree on tree.parent_id = t.%COLUMN_ID
	)
	insert into @nodes(folder_id, parent_id, node_id, %COLUMN_ID, name, has_childs)
		output inserted.folder_id, inserted.node_id, inserted.row_id into #map
	select distinct folder_id,
		case
			when parent_id is null then 
				case
					when @has_folders = 0 then null
					else ''F'' + cast(folder_id as varchar)
				end
			else ''C'' + cast(parent_id as varchar)
		end 
		, ''C'' + cast(%COLUMN_ID as varchar)
		, %COLUMN_ID
		, name
		, has_childs
	from tree

	if @has_folders = 1
	begin
		;with tree as (
			select distinct a.parent_id, a.folder_id, a.name, a.node
				from objs_folders a
					join @nodes n on n.folder_id = a.folder_id
				where n.parent_id like ''F%''

			union all
			select t.parent_id, t.folder_id, t.name, t.node
			from objs_folders t
				join tree on tree.parent_id = t.folder_id
		)
		insert into @nodes(folder_id, parent_id, node_id, name, has_childs)
			output inserted.folder_id, inserted.node_id, inserted.row_id into #map
		select distinct 
			folder_id,
			case
				when node.GetLevel() = @folder.GetLevel() then null
				else ''F'' + cast(parent_id as varchar)
			end
			, ''F'' + cast(folder_id as varchar)
			, name
			, 1 -- has_childs
		from tree
		where node.GetLevel() >= @folder.GetLevel()
	end

	-- map parents
	update x
	set parent_id = m.row_id
	from @nodes x
		join #map m on m.folder_id = x.folder_id and m.node_id = x.parent_id

	-- map parents (2)
	update x
	set parent_id = m.row_id
	from @nodes x
		join #map m on m.node_id = x.parent_id
	where parent_id like ''F%''

	-- map parents (2)
	update @nodes set parent_id = null
	where parent_id = ''F0''

	insert into #sums(folder_id, parent_id, node_id, %column_id, name, has_childs)
	select folder_id, parent_id, row_id, %column_id, name, has_childs
	from @nodes

	update x
	set value_start = r.value_start,
		value_in = r.value_in,
		value_out = r.value_out,
		value_end = isnull(r.value_start,0) + isnull(r.value_in,0) + isnull(r.value_out,0)
	from #sums x
		join (
			select 
				folder_id, %column_id, 
				sum(value_start) value_start,
				sum(value_in) value_in,
				sum(value_out) value_out
			from #details
			group by folder_id, %column_id
		) r on r.folder_id = x.folder_id
			and r.%column_id = x.%column_id

	drop table #map, #details
	';

	set @sql = replace(@sql, '%column_id', @column_id)
	set @sql = replace(@sql, '%dictionary_name', @group_id)

	exec sp_executesql @sql, N'@fin_goal_id int, @mol_id int, @group_id varchar(32), @folder_id int, @tid int',
		@fin_goal_id, @mol_id, @group_id, @folder_id, @tid

    -- иерархия
        exec fin_goal_calc;20 @fin_goal_id, @mol_id, @group_id
        exec fin_goal_calc;30

    -- build name
        update x
        set name = 
                case
                    when not exists(select 1 from deals_costs where deal_id = d.deal_id and value_bdr <> 0) then x.name + '(нет калькуляции)'
                    else x.name
                end
        from #sums x
            join deals d on d.budget_id = x.budget_id

    -- result
        insert into fin_goals_sums(
            fin_goal_id, mol_id, group_id, 
            folder_id, goal_account_id,
            budget_id, article_id, 
            node, parent_id, node_id, name, has_childs, level_id, sort_id,
            value_start, value_in, value_out, value_end, 
            excluded, value_in_excl, value_out_excl
            )
        select 
            @fin_goal_id, @mol_id, @group_id,
            folder_id, goal_account_id,
            budget_id, article_id,
            node, parent_id, node_id, name, has_childs, level_id, sort_id,
            value_start, value_in, value_out, value_end,
            excluded, value_in_excl, value_out_excl
        from #sums

        drop table #sums
end
go
-- helper: build local tree
create proc fin_goal_calc;20
	@fin_goal_id int,
	@mol_id int,
	@group_id varchar(32)	
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
-- helper: summary of parents
create proc fin_goal_calc;30
as
begin

	if object_id('tempdb.dbo.#folders') is not null	
	begin
		if exists(select 1 from #folders)
		begin
			update x
			set excluded = 1
			from #sums x
				join fin_goals_meta_excludes ex on ex.budget_id = x.budget_id
			where ex.folder_id in (select folder_id from #folders)

			update x
			set value_in = 0,
				value_out = 0,
				value_in_excl = value_in,
				value_out_excl = value_out,
				value_end = value_start
			from #sums x
			where x.excluded = 1
		end
	end
	
	update x
	set value_start = r.value_start,
		value_in = r.value_in,
		value_out = r.value_out,
		value_end = isnull(r.value_start,0) + isnull(r.value_in,0) + isnull(r.value_out,0),
		value_in_excl = r.value_in_excl,
		value_out_excl = r.value_out_excl
	from #sums x
		join (
			select y2.node_id, 
				sum(y1.value_start) as value_start,
				sum(y1.value_in) as value_in,
				sum(y1.value_out) as value_out,
				sum(y1.value_end) as value_end,
				sum(y1.value_in_excl) as value_in_excl,
				sum(y1.value_out_excl) as value_out_excl
			from #sums y2
				join #sums y1 on 
						y2.has_childs = 1
					and y1.node.IsDescendantOf(y2.node) = 1
					and y1.has_childs = 0
			group by y2.node_id
		) r on r.node_id = x.node_id

	delete from #sums where (
		  abs(isnull(value_start,0))
		+ abs(isnull(value_in,0))
		+ abs(isnull(value_out,0))
		+ abs(isnull(value_end,0))
		+ abs(isnull(value_in_excl,0))
		+ abs(isnull(value_out_excl,0))
		) = 0.00
end
go
