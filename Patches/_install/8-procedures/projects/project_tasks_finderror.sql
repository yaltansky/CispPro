if exists(select 1 from sys.objects where name = 'project_tasks_finderror')
	drop proc project_tasks_finderror
go

create proc project_tasks_finderror
	@project_id int,	
	@from_number int = null,
	@threshold int = 300
as
begin

	set nocount on;

	BEGIN TRANSACTION

		BEGIN TRY

			declare @old table(task_id int primary key, task_number int, predecessors varchar(500))
				insert into @old select task_id, task_number, predecessors from projects_tasks
				where project_id = @project_id and (@from_number is null or task_number >= @from_number)

			-- clear predecessors
			update projects_tasks
			set predecessors = null
			where project_id = @project_id
				and (@from_number is null or task_number >= @from_number)

			-- calc links
			exec project_tasks_calc_links @project_id

			declare c_temp cursor local read_only for 
				select task_id, predecessors from @old where predecessors is not null
				order by task_number

			declare @exit bit = 0, @task_id int, @predecessors varchar(250)
	
			open c_temp
			fetch next from c_temp into @task_id, @predecessors

			while (@@fetch_status <> -1) and @exit = 0
			begin
				if (@@fetch_status <> -2)
				begin
					print @task_id

					update projects_tasks set predecessors = @predecessors where task_id = @task_id
					exec project_tasks_calc_links @project_id, @task_id
					exec project_tasks_calc null, @project_id

					if (select max(duration_buffer) from projects_tasks where project_id = @project_id) > @threshold
					begin
						set @exit = 1
						select task_id, task_number, name, predecessors from projects_tasks where task_id = @task_id
						print 'Превышен установленный порог буфера задач ' + cast(@threshold as varchar)
					end
		
				end

				fetch next from c_temp into @task_id, @predecessors
			end

			close c_temp
			deallocate c_temp	
		END TRY

		BEGIN CATCH
			declare @err nvarchar(max) = error_message()
			print @err
		END CATCH
	
	ROLLBACK

end
go
