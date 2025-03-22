if object_id('tasks_view') is not null drop proc tasks_view
go
-- exec tasks_view @mol_id = 1000, @filter_xml = '<f><EXTRA_ID>1</EXTRA_ID></f>'
create proc tasks_view
	@mol_id int,	
	@filter_xml xml = null,
	-- 
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	@rowscount int = null out,
	-- 
	@trace bit = 0
as
begin
	set nocount on;
	set transaction isolation level read uncommitted;

    declare @today date = dbo.today()

	-- parse filter
		declare 
			@project_id int,	
			@project_task_id int,	
			@theme_id int,
			@author_id int,
			@analyzer_id int,
			@executor_id int,
			@role_mol_id int,
			@status_id int,
			@is_archive bit,
			@extra_id int,
			@event_id int,
			@search varchar(max),
			@refkey varchar(250),
			@d_doc_from date,
			@d_doc_to date,
			@d_deadline_from date,
			@d_deadline_to date,
			@d_hist_from date,
			@d_hist_to date,
			@d_closed_from date,
			@d_closed_to date,
			@folder_id int,
			@buffer_operation int

		declare @handle_xml int; exec sp_xml_preparedocument @handle_xml output, @filter_xml
			select
				@project_id = nullif(project_id, 0),
				@project_task_id = nullif(project_task_id, 0),
				@theme_id = nullif(theme_id, 0),
				@author_id = nullif(author_id, 0),
				@analyzer_id = nullif(analyzer_id, 0),
				@executor_id = nullif(executor_id, 0),
				@role_mol_id = nullif(role_mol_id, 0),
				@status_id = @filter_xml.value('(/*/STATUS_ID/text())[1]', 'int'),
				@is_archive = isnull(is_archive,0),
				@extra_id = nullif(extra_id,0),
				@event_id = nullif(event_id,0),
				@search = Search,
				@refkey = refkey,
				@d_doc_from = nullif(d_doc_from,'1900-01-01'),
				@d_doc_to = nullif(d_doc_to,'1900-01-01'),
				@d_deadline_from = nullif(d_deadline_from,'1900-01-01'),
				@d_deadline_to = nullif(d_deadline_to,'1900-01-01'),
				@d_hist_from = nullif(d_hist_from,'1900-01-01'),
				@d_hist_to = nullif(d_hist_to,'1900-01-01'),
				@d_closed_from = nullif(d_closed_from,'1900-01-01'),
				@d_closed_to = nullif(d_closed_to,'1900-01-01'),
				@folder_id = nullif(folder_id,0),
				@buffer_operation = nullif(buffer_operation,0)
			from openxml (@handle_xml, '/*', 2) with (
				PROJECT_ID INT,	
				PROJECT_TASK_ID INT,	
				THEME_ID INT,
				AUTHOR_ID INT,
				ANALYZER_ID INT,
				EXECUTOR_ID INT,
				ROLE_MOL_ID INT,
				STATUS_ID INT,
				IS_ARCHIVE BIT,
				EXTRA_ID INT,
				EVENT_ID INT,
				Search VARCHAR(MAX),
				REFKEY VARCHAR(250),
				D_DOC_FROM DATE,
				D_DOC_TO DATE,
				D_DEADLINE_FROM DATE,
				D_DEADLINE_TO DATE,
				D_HIST_FROM DATE,
				D_HIST_TO DATE,
				D_CLOSED_FROM DATE,
				D_CLOSED_TO DATE,
				FOLDER_ID INT,
				BUFFER_OPERATION INT
				)
		exec sp_xml_removedocument @handle_xml

    	-- @inout_status_id
		declare @inout_status_id int
		if @status_id <= -10 -- Виртуальные статусы
		begin
			set @inout_status_id = @status_id
			set @status_id = null
		end
	-- #ids
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
		create table #ids(id int primary key); insert into #ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'tsk'
		
		if not exists(select 1 from #ids)
        begin
			insert into #ids select distinct id from dbo.hashids(@search)
            if exists(select 1 from #ids) set @search = null
        end
    -- @search_text
        declare @search_text nvarchar(500)
        set @search_text = '"' + replace(@search, '"', '*') + '"'
        set @search = '%' + @search + '%'
        set @search_text = isnull(@search_text, '*')
    -- track week
        declare @track_week bit; set @track_week = case when @extra_id in (5,6) then 1 else 0 end
        declare @week_start date, @week_end date
        if @track_week = 1
        begin
            set @week_start = dbo.week_start(case when @extra_id = 5 then dbo.today() else dbo.today() + 7 end)
            set @week_end = dateadd(d, 6, @week_start)
        end
    -- @theme
        declare @theme hierarchyid = (select node from tasks_themes where theme_id = @theme_id)
	-- @project_task_id	
		if @project_task_id is not null
		begin
			declare @project_node hierarchyid = (select node from projects_tasks where task_id = @project_task_id)
			set @project_id = (select project_id from projects_tasks where task_id = @project_task_id)
        end

	declare @tasks_cache varchar(50) = concat('CISPTMP.dbo.TASKS$', @mol_id)
	exec tasks_view;3 @mol_id, @is_archive, @tasks_cache -- auto-create cache table

	declare @select_filelds nvarchar(max) = N'
        T.*,
        TS.STATUS_ID,
        STATUS_NAME = TS.NAME,
        STATUS_CSS = TS.CSS_CLASS,
        
        IS_OVERDUE = 
            CASE 
                WHEN TS.IS_WORKING = 1 AND T.D_DEADLINE < @TODAY THEN 1
            END,
        
        IS_AUDITOR = 0,
        IS_EXECUTOR = 0,
        IS_PARTICIPANT = 1
        '

	declare @from nvarchar(max) = concat('
		from (
            select 
                -- static fields
                T.TASK_ID, T.TITLE, T.AUTHOR_NAME, T.ANALYZER_NAME, T.EXECUTOR_NAME, 
                T.THEME_ID, T.PROJECT_TASK_ID,
                T.AUTHOR_ID, T.ANALYZER_ID,
                T.REFKEY, T.D_DOC, T.D_CLOSED, T.ADD_DATE, T.UPDATE_DATE,
                -- dynamic fields
                TT.STATUS_ID, TT.PRIORITY_ID, TT.D_DEADLINE, TT.IS_WORKING, TT.IS_MY, TT.IS_FAVORITE
            from v_tasks t
                join <tasks_cache> tt on tt.task_id = t.task_id
            ) t
			join tasks_statuses ts on ts.status_id = t.status_id
		where (1 = 1) ',
            -- refs
                case 
                    when @project_task_id is not null then
                        ' and project_task_id in (
                            select task_id from projects_tasks where project_id = @project_id and node.IsDescendantOf(@project_node) = 1
                            )'
                    when @project_id is not null then
                        ' and project_task_id in (
                            select task_id from projects_tasks where project_id = @project_id
                            )'
                end,

                case when @refkey is not null then ' and (t.refkey = @refkey)' end,
                
                case when @folder_id is not null or exists(select 1 from #ids) then ' and t.task_id in (select id from #ids)' end,
            -- @search
                case when @search is not null then
                    ' and (
                        t.title like @search
                        or exists(select 1 from tasks_hists where task_id = t.task_id and contains(body, @search_text))
                        )'
                end,
            -- @status_id
                case when @status_id is not null then ' and (t.status_id = @status_id)' end,

                -- incomings
                case when @inout_status_id = -10 then 
                    ' and exists(
                        select 1
                        from tasks_hists x
                            join tasks_hists_mols y on y.hist_id = x.hist_id
                        where x.task_id = t.task_id
                            and y.mol_id = @mol_id
                            and y.d_read is null
                    )' 
                end,
                -- активные задачи
                case when @inout_status_id = -30 then ' and (t.is_working = 1)' end,
            -- @extra_id
                -- id: 1, name: Мои задачи
                case when @extra_id = 1 then ' and (t.is_my = 1)' end,
                -- id: 7, name: Просроченные задачи
                case when @extra_id = 7 then ' and (t.d_deadline < @today and t.is_working = 1)' end,
                -- id: 11, name: Приоритетные
                case when @extra_id = 11 then ' and (t.priority_id is not null and t.is_working = 1)' end,
                -- id: 12, name: Помеченные
                case when @extra_id = 12 then ' and (t.is_favorite = 1)' end,
            -- dates
                case when @d_doc_from is not null then ' and (d_doc >= @d_doc_from)' end,
                case when @d_doc_to is not null then ' and (d_doc <= @d_doc_to)' end,
                case when @d_deadline_from is not null then ' and (d_deadline >= @d_deadline_from)' end,
                case when @d_deadline_to is not null then ' and (d_deadline <= @d_deadline_to)' end,
                case when @d_hist_from is not null then ' and exists(select 1 from tasks_hists where task_id = task_id and d_add >= @d_hist_from)' end,
                case when @d_hist_to is not null then ' and exists(select 1 from tasks_hists where task_id = task_id and d_add <= @d_hist_to)' end,
                case when @d_closed_from is not null then ' and (d_closed >= @d_closed_from)' end,
                case when @d_closed_to is not null then ' and (d_closed <= @d_closed_to)' end,
            -- misc
                case when @theme is not null then ' and theme_id in (select theme_id from tasks_themes where node.IsDescendantOf(@theme) = 1)' end,
                case when @track_week = 1 then ' and (d_deadline between @week_start and @week_end)' end,
                case when @author_id is not null then ' and (author_id = @author_id)' end,
                case when @analyzer_id is not null then ' and (analyzer_id = @analyzer_id)' end,
                case when @executor_id is not null then
                    ' and exists(select 1 from tasks_mols where task_id = t.task_id and mol_id = @executor_id and role_id = 1)'
                end,
                case when @role_mol_id is not null then
                    ' and exists(select 1 from tasks_mols where task_id = t.task_id and mol_id = @role_mol_id)'
                end
		)
        
        if @refkey is null
            set @from = replace(@from, '<tasks_cache>', concat('CISPTMP.dbo.TASKS$', @mol_id))
        else
            set @from = replace(@from, '<tasks_cache>', '(
                select task_id, status_id, priority_id = 0, d_deadline, is_working = 1, is_my = 1, is_favorite = 0
                from tasks
                where refkey = @refkey
                )')

		declare @fields_base nvarchar(max) = N'
			@mol_id int,
			@refkey varchar(250),
            @theme_id int,
            @theme hierarchyid,
            @project_id int,
            @project_task_id int,
            @project_node hierarchyid,
            @inout_status_id int,
            @status_id int,
            @author_id int,
            @analyzer_id int,
            @executor_id int,
            @role_mol_id int,
            @extra_id int,
            @search varchar(500),
            @search_text nvarchar(500),
            @track_week bit,
            @week_start date,
            @week_end date,
            @d_doc_from date,
			@d_doc_to date,
			@d_deadline_from date,
			@d_deadline_to date,
			@d_hist_from date,
			@d_hist_to date,
			@d_closed_from date,
			@d_closed_to date,
            @today date'

        declare @sql nvarchar(max), @fields nvarchar(max)

		if @buffer_operation is null
		begin
			-- @rowscount
				set @sql = N'select @rowscount = count(*) ' + @from
				set @fields = @fields_base + ', @rowscount int out'
				exec sp_executesql @sql, @fields,
                    @mol_id, @refkey, @theme_id, @theme, @project_id, @project_task_id, @project_node, @inout_status_id, @status_id,
                    @author_id, @analyzer_id, @executor_id, @role_mol_id, @extra_id, @search, @search_text,
                    @track_week, @week_start, @week_end, @d_doc_from, @d_doc_to, @d_deadline_from, @d_deadline_to,
                    @d_hist_from, @d_hist_to, @d_closed_from, @d_closed_to, @today,
                    @rowscount out

			-- selection
				set @sql = N'select ' + @select_filelds + @from
				if @sort_expression is null set @sql = @sql + ' order by t.update_date desc'
				else set @sql = @sql + ' order by t.' + @sort_expression

				set @sql = @sql + ' offset @offset rows fetch next @fetchrows rows only'
				set @fields = @fields_base + ', @offset int, @fetchrows int'

			if @trace = 1 print @sql

			exec sp_executesql @sql, @fields,
                @mol_id, @refkey, @theme_id, @theme, @project_id, @project_task_id, @project_node, @inout_status_id, @status_id,
                @author_id, @analyzer_id, @executor_id, @role_mol_id, @extra_id, @search, @search_text,
                @track_week, @week_start, @week_end, @d_doc_from, @d_doc_to, @d_deadline_from, @d_deadline_to,
                @d_hist_from, @d_hist_to, @d_closed_from, @d_closed_to, @today,
				@offset, @fetchrows
		end

		else begin
			set @rowscount = -1 -- dummy

			declare @buffer_id int; select @buffer_id = folder_id from objs_folders where keyword = 'BUFFER' and add_mol_id = @mol_id

			if @buffer_operation = 1
			begin
				-- add to buffer
				set @sql = N'
					delete from objs_folders_details where folder_id = @buffer_id and obj_type = ''TSK'';
					;insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
					select @buffer_id, ''TSK'', t.task_id, @mol_id '
					+ @from
					+ ';select top 0 ' + @select_filelds + @from
				set @fields = @fields_base + ', @buffer_id int'

                if @trace = 1 print @sql

				exec sp_executesql @sql, @fields,
                    @mol_id, @refkey, @theme_id, @theme, @project_id, @project_task_id, @project_node, @inout_status_id, @status_id,
                    @author_id, @analyzer_id, @executor_id, @role_mol_id, @extra_id, @search, @search_text,
                    @track_week, @week_start, @week_end, @d_doc_from, @d_doc_to, @d_deadline_from, @d_deadline_to,
                    @d_hist_from, @d_hist_to, @d_closed_from, @d_closed_to, @today,
                    @buffer_id
			end

			else if @buffer_operation = 2
			begin
				-- remove from buffer
				set @sql = N'
					delete from objs_folders_details
					where folder_id = @buffer_id
						and obj_type = ''TSK''
						and obj_id in (select t.task_id ' + @from + ')
					;select top 0 ' + @select_filelds + @from
				set @fields = @fields_base + ', @buffer_id int'
				
				exec sp_executesql @sql, @fields,
                    @mol_id, @refkey, @theme_id, @theme, @project_id, @project_task_id, @project_node, @inout_status_id, @status_id,
                    @author_id, @analyzer_id, @executor_id, @role_mol_id, @extra_id, @search, @search_text,
                    @track_week, @week_start, @week_end, @d_doc_from, @d_doc_to, @d_deadline_from, @d_deadline_to,
                    @d_hist_from, @d_hist_to, @d_closed_from, @d_closed_to, @today,
					@buffer_id
			end
		end
end
go
-- helper: totals info
-- tasks_view;2 -25, 1, 0, 1
create proc tasks_view;2
	@mol_id int,
    @is_my bit = 1,
    @is_archive bit = 0,
	@mode int = null -- null - all counters, 1 - themes totals, 2 - themes
as
begin
	set nocount on;
	set transaction isolation level read uncommitted;

	declare @today date = dbo.today()

	create table #tasks(
		task_id int index ix_task,
		analyzer_id int,
		theme_id int,
		status_id int,
		d_deadline date,
        is_working bit,
        is_my bit,
        is_favorite bit
		)

	declare @tasks_cache varchar(50) = concat('CISPTMP.dbo.[TASKS$', @mol_id, ']')
	exec tasks_view;3 @mol_id, @is_archive, @tasks_cache -- auto-create cache table

    -- #tasks
	declare @sql nvarchar(max) = replace('
        insert into #tasks(task_id, theme_id, status_id, is_working, is_my, d_deadline)
        select task_id, theme_id, status_id, is_working, is_my, d_deadline
        from <tasks_cache>
        where @is_my = 0 or is_my = 1
        ', '<tasks_cache>', @tasks_cache)

    exec sp_executesql @sql, N'@mol_id int, @is_my bit', @mol_id, @is_my

	create table #tv_counts(
		counts_type varchar(30),
		counts_id int,
        name varchar(50),
		css_class varchar(50),
        css_badge varchar(50),
		counts int,
        counts_over int,
		parent_id int,
		sort_id int identity
		)

    -- группировки по статусам
	if @mode is null
	begin
		-- Входящие
		insert into #tv_counts(counts_type, counts_id, name, css_class, counts)
		select 'countByStatuses',
			status_id,
			name,
			css_class,
			(
			select nullif(count(distinct y.task_id), 0)
			from tasks_hists_mols x
				join tasks_hists y on y.hist_id = x.hist_id
				join #tasks t on t.task_id = y.task_id
			where x.mol_id = @mol_id
				and x.d_read is null
                and t.is_working = 1
			)
		from tasks_statuses
		where status_id = -10

		-- Активные
		insert into #tv_counts(counts_type, counts_id, name, css_class, css_badge, counts)
		select 'countByStatuses',
			status_id,
			name,
			css_class,
			css_badge,
			(
				select nullif(count(*), 0) from #tasks
                where is_working = 1
			)
		from tasks_statuses
		where status_id = -30

		insert into #tv_counts(counts_type, counts_id, name, css_class, css_badge, counts)
		select 'countByStatuses',
			ts.status_id,
			ts.name,
			ts.css_class,
			ts.css_badge,
			nullif(count(*),0)
		from #tasks t
			join tasks_statuses ts on ts.status_id = t.status_id
		group by ts.status_id, ts.name, ts.css_class, ts.css_badge
		order by ts.status_id
	end

    -- Итоги по рубрикам
    else if @mode = 1
    begin

        insert into #tv_counts(counts_type, counts, counts_over)
        select 'countByThemes',
            (
                select count(*) from #tasks where is_working = 1
            ),
            (
                select count(*) from #tasks where is_working = 1 and d_deadline < @today
            )
    end

    -- группировки по рубрикам
	else if @mode = 2
    begin
        create table #tv_themes(theme_id int primary key, name varchar(100), parent_id int, level_id int, node hierarchyid, has_childs bit, counts int, counts_over int)
            insert into #tv_themes(theme_id, name, parent_id, level_id, node, has_childs, counts, counts_over)
            select theme_id, name, parent_id, level_id, node, has_childs,
                (
                    select count(*) from #tasks where theme_id = x.theme_id
                        and is_working = 1
                ),
                (
                    select count(*) from #tasks where theme_id = x.theme_id and d_deadline < @today
                        and is_working = 1
                )
            from tasks_themes x
            where x.is_deleted = 0
                and x.theme_id in (select distinct theme_id from #tasks)
            
            insert into #tv_themes(theme_id, name, level_id, node, has_childs)
            select x.theme_id, x.name, x.level_id, x.node, x.has_childs
            from tasks_themes x
            where exists(select 1 from #tv_themes where node.IsDescendantOf(x.node) = 1)
                and not exists(select 1 from #tv_themes where theme_id = x.theme_id)
    
            update x
            set counts = (select sum(counts) from #tv_themes where node.IsDescendantOf(x.node) = 1),
                counts_over = (select sum(counts_over) from #tv_themes where node.IsDescendantOf(x.node) = 1)
            from #tv_themes x

        insert into #tv_counts(counts_type, counts_id, name, counts, counts_over, parent_id)
        select 'countByThemes', theme_id, name, counts, counts_over, parent_id
        from #tv_themes
        order by node
    end

	-- final select
	select * from #tv_counts order by sort_id

	exec drop_temp_table '#tasks,#tv_counts,#tv_themes'
end
go
-- helper: auto-create cache table
create proc tasks_view;3
	@mol_id int,
    @is_archive bit = 0,
    @table_name varchar(100)
as
begin
	set nocount on;
	set transaction isolation level read uncommitted;

	IF NOT EXISTS(SELECT 1 FROM SYS.DATABASES WHERE NAME = 'CISPTMP')
		CREATE DATABASE CISPTMP 
            COLLATE Cyrillic_General_CI_AS; -- cisp for temp objects

    if object_id(@table_name) is null
    begin
    	declare @sql nvarchar(max) = replace('
            CREATE TABLE <TASKS_CACHE>(
                TASK_ID INT PRIMARY KEY,
                THEME_ID INT,
                D_DEADLINE DATE,
                STATUS_ID INT,
                PRIORITY_ID INT,
                IS_WORKING BIT,
                IS_MY BIT,
                IS_FAVORITE BIT,
                D_ADD DATETIME DEFAULT GETDATE(),
                LOCKED BIT
            )', '<TASKS_CACHE>', @table_name)

    	exec sp_executesql @sql
    end

	set @sql = replace('
        declare @d_calc datetime = isnull((select top 1 d_add from <tasks_cache>), ''2000-01-01'')

        -- CHECK LOCKED
        IF DATEDIFF(SECOND, @D_CALC, GETDATE()) < 60
        BEGIN
            DECLARE @CHECK_LIMIT INT = 0
            WHILE EXISTS(SELECT 1 FROM <TASKS_CACHE> WHERE LOCKED = 1) AND @CHECK_LIMIT < 10
            BEGIN 
                WAITFOR DELAY ''00:00:00:500''
                SET @CHECK_LIMIT = @CHECK_LIMIT + 1
            END
        END

        if datediff(second, @d_calc, getdate()) > 5
        begin
            TRUNCATE TABLE <TASKS_CACHE>;
            
            -- LOCK TABLE
            INSERT INTO <TASKS_CACHE>(TASK_ID, LOCKED) SELECT 0, 1

            insert into <tasks_cache>(task_id, theme_id, status_id, is_working, is_my, is_favorite, d_deadline, priority_id)
            select distinct 
                t.task_id, t.theme_id, t.status_id, ts.is_working,
                is_my = case when tm.task_id is not null then 1 end,
                is_favorite = case when tmf.task_id is not null then 1 end,
                t.d_deadline,
                tmp.priority_id
            from (
                select 
                    t.task_id, t.theme_id, 
                    status_id = isnull(tm.status_id, t.status_id),
                    is_archive = case when t.status_id = 5 and datediff(d, t.update_date, getdate()) > 365 then 1 else 0 end,
                    t.d_deadline
                from tasks t
                    -- #STATUS_RULE
                    left join tasks_themes_mols ttm on ttm.theme_id = t.theme_id and ttm.mol_id = @mol_id					
                    left join tasks_mols tm on tm.task_id = t.task_id 
                        and tm.mol_id = @mol_id and tm.role_id = 1 -- исполнитель видит только "свою" часть задачи
                        and tm.mol_id != t.analyzer_id -- координатор ...
                        and ttm.mol_id is null -- и аудитор должны видеть общий статус задачи
                ) t
                left join tasks_mols tm on tm.task_id = t.task_id and tm.mol_id = @mol_id and tm.role_id != 2
                left join tasks_mols tmf on tmf.task_id = t.task_id and tmf.mol_id = @mol_id and tmf.is_favorite = 1
                -- priority_id
                left join (
                    select task_id, max(priority_id) as priority_id
                    from tasks_mols where mol_id = @mol_id
                    group by task_id
                ) tmp on tmp.task_id = t.task_id
                join tasks_statuses ts on ts.status_id = t.status_id
            where 
                -- #REGLAMENT_VIEW
                (
                    t.task_id in (
                        select distinct tm.task_id from tasks_mols tm
                            join tasks t on t.task_id = tm.task_id
                                left join tasks_themes_mols ttm on ttm.theme_id = t.theme_id and ttm.mol_id = @mol_id -- аудиторы/читатели рубрик
                            join mols on mols.mol_id = tm.mol_id
                        where @mol_id in (mols.mol_id, mols.chief_id, ttm.mol_id)
                        )
                )
                and t.status_id != -1 -- кроме удалённых
                and is_archive = isnull(@is_archive,0)

            -- UNLOCK TABLE
            DELETE FROM <TASKS_CACHE> WHERE LOCKED = 1
        end
        ', '<tasks_cache>', @table_name)

    exec sp_executesql @sql, N'@mol_id int, @is_archive bit', @mol_id, @is_archive
end
go
