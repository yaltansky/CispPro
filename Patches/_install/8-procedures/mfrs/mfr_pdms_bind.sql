if object_id('mfr_pdms_bind') is not null drop proc mfr_pdms_bind
go
create proc mfr_pdms_bind
	@mol_id int,
	@status_id int = null, -- установить статус
	@opers_pdm_id int = null, -- карточке ДСЕ - источник операций
	@exec_reglament_id int = null, -- регламент
	@executor_id int = null -- исполнитель
as
begin
    set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
        declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
            'opers_pdm_id = ', @opers_pdm_id,
            '@exec_reglament_id = ', @exec_reglament_id,
            '@executor_id = ', @executor_id
            )
        exec tracer_log @tid, @tid_msg      

	exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'

	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfpdm')

	if @status_id is not null
	begin
		update mfr_pdms set status_id = @status_id
		where pdm_id in (select id from @buffer)
	end

	else if @opers_pdm_id is not null
	begin
        exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Admin'

        declare @map app_mapids2
        insert into @map(old_id, new_id) select @opers_pdm_id, id from @buffer

        exec mfr_pdm_sync @mol_id = @mol_id, @map = @map, @parts = 'opers'
	end

    else if @executor_id is not null
	begin
		declare @tasks table (
			task_id int index ix_task,
			pdm_id int,
			refkey varchar(255) index ix_refkey
			)
			insert into @tasks(pdm_id, refkey)
			select x.pdm_id, concat('/mfrs/pdms/', x.pdm_id)
			from mfr_pdms x
				join @buffer i on i.id = x.pdm_id

			update x set task_id = t.task_id
			from @tasks x
				join (
					select refkey, max(task_id) as task_id
					from tasks 
					where refkey like '/mfrs/pdms%'
					group by refkey
				) t on t.refkey = x.refkey

		declare @tasks_added table (task_id int primary key, pdm_id int)

		insert into tasks(type_id, author_id, analyzer_id, title, status_id, refkey, parent_id)
			output inserted.task_id, inserted.parent_id into @tasks_added
		select top 50
			1, @mol_id, @mol_id,
			concat('Чертёжная деталь #', pdm_id),
			0,
			refkey,
			pdm_id
		from @tasks
		where task_id is null
		
		update x set task_id = a.task_id
		from @tasks x
			join @tasks_added a on a.pdm_id = x.pdm_id

		-- status_id
		update x set status_id = 0, author_id = @mol_id
		from tasks x
			join @tasks xx on xx.task_id = x.task_id

		-- delete old executors
		delete x from tasks_mols x
			join @tasks xx on xx.task_id = x.task_id
		where x.role_id = 1

		declare c_tasks cursor local read_only for select task_id, pdm_id from @tasks
		declare @task_id int, @pdm_id int

		open c_tasks; fetch next from c_tasks into @task_id, @pdm_id
			begin try
				while (@@fetch_status != -1)
				begin
					if (@@fetch_status != -2)
					begin
						declare @comment varchar(max) = concat('Прошу принять к исполнению работу над заполнением разделов по детали #', @pdm_id, '.')

						exec task_sign @task_id = @task_id,
							@action_id = 'Assign',
							@action_name = 'К исполнению',
							@from_mol_id = @mol_id,
							@to_mols_ids = @executor_id,
							@comment = @comment,
							@body = @comment

						update tasks set parent_id = null where task_id = @task_id
					end
					fetch next from c_tasks into @task_id, @pdm_id
				end
			end try 
			begin catch end catch
		close c_tasks; deallocate c_tasks

		-- exec_reglament_id
		update x set 
			status_id = 2,
			exec_reglament_id = @exec_reglament_id, 
			executor_id = @executor_id
		from mfr_pdms x
			join @buffer i on i.id = x.pdm_id
	end

    -- trace end
        exec tracer_close @tid
end
go
