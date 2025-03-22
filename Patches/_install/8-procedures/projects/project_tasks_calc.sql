if object_id('project_tasks_calc') is not null drop proc project_tasks_calc
go
create proc project_tasks_calc
	@tree_id int = null,
	@project_id int = null,
	@mol_id int = null,
	@gantt_only bit = 1,
	@calc_refs bit = 1,
	@trace bit = 0
as
begin
	set nocount on;

	-- start log		
		declare @tid int; exec tracer_init 'project_tasks_calc', @trace_id = @tid out, @echo = @trace
	-- prepare
        update projects_tasks set parent_id = null
        where project_id = @project_id and task_id = parent_id

        update x set parent_id = null from projects_tasks x
        where project_id = @project_id
            and not exists(select 1 from projects_tasks where task_id = x.parent_id)
	BEGIN TRY
	BEGIN TRANSACTION
		-- dump deleted
            if @project_id is not null
                exec project_tasks_calc;4 @project_id
		-- #ref_projects
            create table #ref_projects (project_id int primary key);
                insert into #ref_projects
                    select ref_project_id from projects_tasks
                    where project_id = @project_id and ref_project_id is not null
                        and is_deleted = 0

            create table #saved_tasks (task_id int primary key, project_id int, node hierarchyid, parent_id int, outline_level int, sort_id float);
            create table #saved_links (link_id int primary key, project_id int);
		-- set calc_mode for refs projects (as in parent project)
            update x
            set calc_mode_id = xx.calc_mode_id
            from projects x
                inner join projects xx on xx.project_id = @project_id
            where x.project_id in (select project_id from #ref_projects)
		-- PREPARE CHILDS PROJECTS (if any)
            if exists(select 1 from #ref_projects)
            begin
                exec tracer_log @tid, 'prepare childs projects'

                -- refresh PARENT_ID of refs projects
                update x
                set parent_id = t.project_id
                from projects x
                    inner join projects_tasks t on t.ref_project_id = x.project_id and t.is_deleted = 0
                where t.project_id = @project_id

                -- #saved_tasks
                insert into #saved_tasks
                    select task_id, project_id, node, parent_id, outline_level, sort_id from projects_tasks
                    where project_id in (select project_id from #ref_projects)

                -- #saved_links
                insert into #saved_links(link_id, project_id)
                    select link_id, project_id from projects_tasks_links
                    where project_id in (select project_id from #ref_projects)

                -- set virtual parents
                update x
                set parent_id = t.task_id
                from projects_tasks x
                    inner join projects_tasks t on t.ref_project_id = x.project_id
                where t.project_id = @project_id
                    and x.parent_id is null
                
                    -- set virtual has_childs
                    update projects_tasks set has_childs = 1
                    where project_id = @project_id and ref_project_id is not null

                -- set virtual owner
                update projects_tasks set project_id = @project_id
                where project_id in (select project_id from #ref_projects)
            
                -- set virtual links
                update projects_tasks_links set project_id = @project_id
                where project_id in (select project_id from #ref_projects)

                -- delete bad links
                delete l from projects_tasks_links l, projects_tasks s
                where s.project_id = l.project_id and s.task_id = l.source_id and s.is_deleted = 1

                delete l from projects_tasks_links l, projects_tasks t 
                where t.project_id = l.project_id and t.task_id = l.target_id and t.is_deleted = 1
            end
            
            if not exists(select 1 from #ref_projects)
            begin
                -- calc tasks refs
                exec tracer_log @tid, 'calculate tasks refs'
                exec project_tasks_calc;3 @project_id = @project_id
            end
		-- calc gantt for tasks
            create table #result (
                task_id int primary key,
                d_from datetime,
                d_to datetime,
                duration_buffer int,
                outline_level int,
                duration decimal(18,2),
                progress decimal(18,2),
                is_critical bit,
                is_long bit,
                is_overlong bit,
                execute_level int
                )

            exec tracer_log @tid, 'calculate gantt'
            ;insert into #result exec project_calc @tree_id = @tree_id, @project_id = @project_id, @trace_allowed = @trace

            exec tracer_log @tid, 'write results'
            ;exec sys_set_triggers 0
                -- все задачи
                update t
                set d_from = isnull(t.d_from_fact, cast(r.d_from as date)),
                    d_to = isnull(t.d_to_fact, cast(r.d_to as date)),
                    wk_d_from = r.d_from,
                    wk_d_to = r.d_to,
                    outline_level = r.outline_level,
                    duration_buffer = r.duration_buffer,
                    is_critical = r.is_critical,
                    is_long = r.is_long,
                    is_overlong = r.is_overlong,
                    execute_level = r.execute_level
                from projects_tasks t
                    join #result r on r.task_id = t.task_id

                -- суммарные задачи
                update t
                set duration = r.duration,
                    progress = r.progress
                from projects_tasks t
                    join #result r on r.task_id = t.task_id
                where t.has_childs = 1

            ;exec sys_set_triggers 1
		
            if @gantt_only = 0
            begin		
                -- индикаторы проекта
                exec project_calc_indicators @project_id = @project_id
                exec tracer_log @tid, 'project_calc_indicators'
            end

            exec drop_temp_table '#result'
		-- RESTORE CHILDS PROJECTS (if any)
            if exists(select 1 from #ref_projects)
            begin
                exec tracer_log @tid, 'restore childs projects'

                -- restore #saved_tasks
                update x
                set project_id = old.project_id,
                    node = old.node,
                    parent_id = old.parent_id,
                    outline_level = old.outline_level,
                    sort_id = old.sort_id
                from projects_tasks x
                    inner join #saved_tasks old on old.task_id = x.task_id

                -- restore #saved_links
                update x
                set project_id = old.project_id
                from projects_tasks_links x
                    inner join #saved_links old on old.link_id = x.link_id

                -- change projects.d_from
                update x
                set d_from = t.d_from
                from projects x
                    inner join projects_tasks t on t.ref_project_id = x.project_id
                where t.project_id = @project_id

                -- clear virtual parents
                update projects_tasks set has_childs = 0
                where project_id = @project_id and ref_project_id is not null			
            end
	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION

		declare @err nvarchar(max) = error_message()
		declare @errlog nvarchar(max) = '##error:' + @err		
		raiserror (@err, 16, 1)
		exec tracer_log @tid, @errlog
	END CATCH

	-- check for reference
		if @calc_refs = 1 and exists(
			select 1 from projects_tasks x
			where project_id = @project_id 
				and exists(select 1 from sdocs_mfr_opers where project_task_id = x.task_id)
			)
		begin
			exec project_tasks_calc;2 @project_id = @project_id		
		end

	exec tracer_close @tid
	if @trace = 1 exec tracer_view @tid
end
GO
-- helper: calc SDOCS_MFR_OPERS.D_BEFORE
create proc project_tasks_calc;2
	@project_id int
as
begin
	set nocount on;

	update x set d_after = t.d_from, d_before = t.d_to
	from sdocs_mfr_opers x 
		join projects_tasks t on t.task_id = x.project_task_id
	where t.project_id = @project_id
end
go
-- helper: calc count_checks, count_checks_all
create proc project_tasks_calc;3
	@project_id int
as
begin
	set nocount on;

	update x
	set count_checks = null,
		count_checks_all = null
	from projects_tasks x	
	where project_id = @project_id

	update x
	set count_checks = (
			select count(*) from tasks
			where project_task_id = x.task_id and status_id in (select status_id from tasks_statuses where is_working = 1)
			),
		count_checks_all = (select count(*) from tasks where project_task_id = x.task_id and status_id not in (-1))
	from projects_tasks x	
	where project_id = @project_id
		and task_id in (select distinct project_task_id from tasks where project_task_id is not null)
end
go
-- helper: dump deleted tasks
create proc project_tasks_calc;4
	@project_id int
as
begin
	if not exists(select 1 from projects_tasks where project_id = @project_id and is_deleted = 1)
		return -- nothing todo

	-- dump deleted tasks
		declare @dump_id varchar(32) = cast(getdate() as varchar)

		insert into dump_projects_tasks(
			dump_id, 
			project_id, parent_id, task_id, status_id, task_number, name, d_from, d_to, base_d_from, base_d_to, duration, progress, predecessors, has_childs, description, sort_id, is_critical, add_date, update_date, update_mol_id, count_checks, count_checks_all, priority_id, outline_level, d_after, tags, is_long, duration_buffer, execute_level, has_files, d_before, is_node, reserved
		)
		select 
			@dump_id,
			project_id, parent_id, task_id, status_id, task_number, name, d_from, d_to, base_d_from, base_d_to, duration, progress, predecessors, has_childs, description, sort_id, is_critical, add_date, update_date, update_mol_id, count_checks, count_checks_all, priority_id, outline_level, d_after, tags, is_long, duration_buffer, execute_level, has_files, d_before, is_node, reserved
		from projects_tasks
		where project_id = @project_id
			and is_deleted = 1

	-- purge data
		delete from projects_tasks
		where project_id = @project_id
			and is_deleted = 1
end
go
