if object_id('task_sign') is not null drop proc task_sign
go
create proc task_sign
	@task_id int,
	@action_id varchar(32),
	@action_name varchar(32),
	@from_mol_id int,
	@to_mols_ids varchar(max),
	@comment varchar(max),
	@body varchar(max),
	@analyzer_id int = null,
	@d_deadline datetime = null,
	@duration int = null,
	@query_id int = null,
	@query_solution_id int = null,
	@query_solution_grades int = null,
	@stay_as_member bit = null,
    @attrs_ids varchar(max) = null,
    @hist_id int = null out
as
begin

	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- params
		declare @today datetime = dbo.today()
		declare @author_id int, @type_id int, @theme_id int, @old_status_id int
			select 
				@type_id = type_id,
				@author_id = author_id,
				@analyzer_id = isnull(@analyzer_id, analyzer_id),
				@theme_id = theme_id,
				@old_status_id = status_id
			from tasks where task_id = @task_id

		declare @mols table(mol_id int)
		declare @mols_hist table(mol_id int)
		declare @sync_hist_mols bit = 1

		if @to_mols_ids is not null
		begin
			insert into @mols select distinct item from dbo.str2rows(@to_mols_ids, ',')
			insert into @mols_hist select mol_id from @mols where mol_id <> @from_mol_id
		end
		
		declare @new_status_id int

	if @action_id in ('Send', 'SendAndClose')
	begin
		update tasks
		set analyzer_id = @analyzer_id, 
			owner_id = @analyzer_id,
			d_deadline_author = @d_deadline,
			status_id = case when @analyzer_id = @author_id then 2 else 1 end
		where task_id = @task_id

		-- Добавить в список ролей Автора, Координатора
		delete from tasks_mols where task_id = @task_id and role_id in (10,20)
		-- нормализуем участников
		exec task_sign;2 @task_id = @task_id

		if @action_id = 'SendAndCLose' set @new_status_id = 5
	end

	else if @action_id = 'ChangeAuthor'
	begin
		update tasks
		set author_id = (select top 1 mol_id from @mols)
		where task_id = @task_id

		-- Добавить в список ролей Автора, Координатора
		delete from tasks_mols where task_id = @task_id and role_id in (10)
		-- нормализуем участников
		exec task_sign;2 @task_id = @task_id
	end

	else if @action_id = 'Redirect'
	begin
		update tasks
		set analyzer_id = @analyzer_id, owner_id = @analyzer_id
		where task_id = @task_id
				
		delete from tasks_mols where task_id = @task_id and role_id = 20 -- Изменить роль координатора
		
        if @stay_as_member = 1
			insert into tasks_mols(task_id, mol_id, role_id) select @task_id, @from_mol_id, 2
			where not exists(select 1 from tasks_mols where task_id = @task_id and mol_id = @from_mol_id and role_id = 2)
		else
			delete from tasks_mols where task_id = @task_id and mol_id = @from_mol_id -- удалить из участников		
		-- нормализуем участников
		exec task_sign;2 @task_id = @task_id
	end

	else if @action_id = 'Refine'
		update tasks 
		set owner_id = @author_id,
			status_id = 0
		where task_id = @task_id

	else if @action_id = 'AcceptToExecute'
	begin
		if exists(select 1 from tasks_mols where task_id = @task_id and role_id = 1 and mol_id = @from_mol_id)
			update tasks set status_id = 2 where task_id = @task_id

		else begin
			update tasks set 
				analyzer_id = @from_mol_id,
				status_id = 2
			where task_id = @task_id

			-- добавить в координаторы
            delete from tasks_mols where task_id = @task_id and mol_id = @from_mol_id
			insert into tasks_mols(task_id, role_id, mol_id) values(@task_id, 20, @from_mol_id)

			-- добавить в исполнители
			insert into tasks_mols(task_id, role_id, mol_id, duration, d_deadline)
			values(@task_id, 1, @from_mol_id, @duration, @d_deadline)
		end

		-- показать в hist, что уведомлён Заказчик
		delete from @mols; insert into @mols values(@author_id)
	end

	else if @action_id = 'Assign'
	begin
		update tasks set 
			status_id = 2,
			analyzer_id = coalesce(@analyzer_id, analyzer_id, @from_mol_id)
		where task_id = @task_id

		if @d_deadline is null
			select @d_deadline = d_deadline from tasks where task_id = @task_id

		update tasks_mols
		set d_deadline = @d_deadline,
			duration = isnull(@duration, duration),
			d_executed = null,
            attrs = @attrs_ids
		where task_id = @task_id and role_id = 1
			and mol_id in (select mol_id from @mols)

		update tasks set 
			d_deadline = 
				case
					when d_deadline_author is null then d_deadline_analyzer
					else d_deadline
				end
		where task_id = @task_id

		-- удаляем Координатора из Исполнителей
		delete from tasks_mols where task_id = @task_id and mol_id = @analyzer_id and role_id = 1;
		-- добавляем исполнителей
		insert into tasks_mols(task_id, role_id, mol_id, duration, d_deadline, attrs)
		select @task_id, 1, m.mol_id, @duration, @d_deadline, @attrs_ids
		from @mols m
			join mols on mols.mol_id = m.mol_id
		where not exists(select 1 from tasks_mols where task_id = @task_id and role_id = 1 and mol_id = m.mol_id)
		-- нормализуем участников
		exec task_sign;2 @task_id = @task_id
	end

	else if @action_id = 'Revoke'
	begin
		delete from tasks_mols where task_id = @task_id and role_id in (1,2) and mol_id in (select mol_id from @mols)
		goto checkdone
	end

	else if @action_id = 'ChangeDeadline'
		update tasks 
		set d_deadline = @d_deadline
		where task_id = @task_id

	else if @action_id = 'Postpone'
		update tasks set status_id = -2 where task_id = @task_id

	else if @action_id = 'Done'
	begin
		update tasks_mols
		set d_executed = getdate()
		where task_id = @task_id and role_id = 1 and mol_id = @from_mol_id

		checkdone:
		-- #92194, #144157
		if not exists(select 1 from tasks_mols where task_id = @task_id and role_id = 1 and d_executed is null)
		begin
			update tasks set 
				@new_status_id = 
					case 
						when @author_id = @analyzer_id and @author_id = @from_mol_id then 5
						when @from_mol_id = @analyzer_id then 4
						else 3 
					end,
				status_id = @new_status_id,
				owner_id = case when @new_status_id = 4 then author_id end
			where task_id = @task_id				
		end
	end

	else if @action_id = 'CloseExecutor'
	begin
		update tasks_mols
		set d_executed = getdate()
		where task_id = @task_id 
			and mol_id in (select mol_id from @mols)
			and role_id = 1
			and d_executed is null
	end

	else if @action_id = 'RouteAssign'
	begin
		update tasks_mols
		set status_id = -3 -- Отправлен запрос
		where task_id = @task_id and mol_id = @from_mol_id

		set @sync_hist_mols = 0
	end

	else if @action_id = 'RouteChangeSigner'
	begin
		delete from tasks_mols where task_id = @task_id and mol_id in (select mol_id from @mols)
		
		insert into tasks_mols(task_id, mol_id, role_id)
		select @task_id, mol_id, 1
		from @mols x
	end

	else if @action_id in ('RouteSign', 'RouteRequirements', 'RouteReject')
	begin
		-- отметка об исполнении (формально)
		update tasks_mols
		set d_executed = getdate()
		where task_id = @task_id and role_id = 1 and mol_id = @from_mol_id
	
		-- отметить визирование
		update tasks_routes
		set d_sign = getdate(),
			note = @comment,
			result_id = 
				case
					when @action_id = 'RouteReject' then -1
					when @action_id = 'RouteSign' then 1
					else 2
				end
		where task_id = @task_id and mol_id = @from_mol_id

		-- статус
		if @action_id = 'RouteReject'
			or not exists(select 1 from tasks_mols where task_id = @task_id and role_id = 1 and d_executed is null)
		begin
			set @new_status_id = 5
		end
	end

	else if @action_id = 'PassToAcceptance'
	begin
		update x set d_executed = getdate()
		from tasks_mols x
		where task_id = @task_id and role_id = 1 and mol_id = @from_mol_id

		declare @exec_counter int = (select count(*) from tasks_mols where task_id = @task_id and role_id = 1 and d_executed is null)

		declare @simple_accept bit = 
			case
				when @author_id = -25 then 1
				when @author_id = @analyzer_id and @analyzer_id = @from_mol_id and @exec_counter = 0 then 1
				else 0
			end

		update tasks set 
			status_id = case when @simple_accept = 1 then 5 else 4 end,
			owner_id = case when @simple_accept = 1 then null else author_id end
		where task_id = @task_id
	end

	else if @action_id = 'PassToAuthor'
	begin
		if @author_id = -25 -- КИСП
			update tasks set status_id = 5 where task_id = @task_id
		else begin
			update tasks set status_id = 4, owner_id = author_id where task_id = @task_id
			-- revoke all executors
			declare @deleted table(mol_id int)
			delete from tasks_mols
				output deleted.mol_id into @deleted
			where task_id = @task_id
				and role_id = 1
				and (d_executed is null or mol_id = @from_mol_id)
			-- asign myself as executor
			insert into tasks_mols(task_id, role_id, mol_id, d_executed)
			values(@task_id, 1, @from_mol_id, getdate())
			-- append them as memebers
			insert into tasks_mols(task_id, role_id, mol_id)
				select distinct @task_id, 2, mol_id from @deleted x
				where not exists(select 1 from tasks_mols where task_id = @task_id and role_id = 2 and mol_id = x.mol_id)
		end
	end

	else if @action_id = 'Accept'
		update tasks
		set status_id = 5, owner_id = null
		where task_id = @task_id

	else if @action_id = 'Reject'
	begin
		update tasks
		set status_id = case when @author_id = @analyzer_id then 2 else 3 end,
			owner_id = analyzer_id
		where task_id = @task_id

		if @author_id = @analyzer_id 
		begin
			declare @executor_id int = (select top 1 mol_id from tasks_mols	where task_id = @task_id and role_id = 1)
			update tasks_mols set d_executed = null where task_id = @task_id and mol_id = @executor_id
			
			if not exists(select 1 from @mols where mol_id = @executor_id)
			begin
				insert into @mols select @executor_id
				insert into @mols_hist select @executor_id
			end
		end
	end

	else if @action_id = 'Delete'
		update tasks
		set status_id = -1, owner_id = null
		where task_id = @task_id

	else if @action_id = 'Comment'
	begin
        -- в случае листа согласования
		if @type_id = 2 and not exists(select 1 from tasks_routes where task_id = @task_id and mol_id = @from_mol_id)
			insert into tasks_routes(task_id, name, mol_id, allow_reject)
			values (@task_id, 'Участник', @from_mol_id
				, case when @from_mol_id = @analyzer_id then 1 else 0 end
			)
	end
	
	else if @action_id = 'Agree'
		set @new_status_id = 5 -- закрыть задачу

	else if @action_id = 'Close'
	begin
		set @new_status_id = 5 -- закрыть задачу

		-- в случае листа согласования
		if @type_id = 2 and not exists(select 1 from tasks_routes where task_id = @task_id and mol_id = @from_mol_id)
			insert into tasks_routes(task_id, name, mol_id) values (@task_id, 'Участник', @from_mol_id)
	end

	else if @action_id = 'ReOpen'
	begin
		update tasks set status_id = 2 where task_id = @task_id;
		--delete from tasks_mols where task_id = @task_id and role_id = 1 and mol_id = @analyzer_id
		--insert into tasks_mols(task_id, role_id, mol_id) values (@task_id, 1, @analyzer_id)
	end

	if @new_status_id is not null
	begin
		update tasks 
		set status_id = @new_status_id,
			d_closed = 
				case 
					when @new_status_id = 4 then getdate()
					when @new_status_id = 5 then isnull(d_closed, getdate())
					else null
				end
		where task_id = @task_id
	end
	-- обратная связь с владельцем
		declare @refkey varchar(250) = (select refkey from tasks where task_id = @task_id)
		if @refkey is not null
		begin
			if charindex('payorders', @refkey) > 0
				exec payorder_sign @task_id = @task_id, @action_id = @action_id

			else if charindex('projects', @refkey) > 0 or charindex('deals', @refkey) > 0
				exec deal_sign @task_id = @task_id, @action_id = @action_id

			else if charindex('documents', @refkey) > 0
				exec document_sign @task_id = @task_id, @action_id = @action_id

			else if @refkey like '/mfrs/pdms%'
				exec mfr_pdm_sign @mol_id = @from_mol_id, @task_id = @task_id, @action_id = @action_id

			else if @refkey like '/mfrs/%/drafts%'
				exec mfr_draft_sign @mol_id = @from_mol_id, @task_id = @task_id, @action_id = @action_id

			else if @refkey like '/mfrs/%/items/%'
				exec mfr_items_sign @mol_id = @from_mol_id, @task_id = @task_id, @action_id = @action_id

			else if @refkey like '/mfrs/wksheets/%'
				exec mfr_wk_sheet_sign @mol_id = @from_mol_id, @task_id = @task_id, @action_id = @action_id

			else if @refkey like '/products/list/%'
				exec product_sign @mol_id = @from_mol_id, @task_id = @task_id, @action_id = @action_id
		end

	-- CUSTOM INTEGRATION
		if @action_id in ('PassToAcceptance', 'Done')
			and exists(select 1 from tasks_attrs where task_id = @task_id and attr_name = 'crmguid' and attr_value is not null)
		begin
			exec cisp_gate..task_sign_crmapprovallist_update @task_id = @task_id
		end

	-- TASKS_MOLS
		insert into tasks_mols(task_id, role_id, mol_id, duration, d_deadline)
		select @task_id, 2, m.mol_id, @duration, @d_deadline
		from mols m
			join @mols i on i.mol_id = m.mol_id
		where not exists(select 1 from tasks_mols where task_id = @task_id and mol_id = m.mol_id)

	-- TASKS_HISTS
		declare @to_mols varchar(max); set @to_mols = ''	
		select @to_mols = @to_mols + ',' + mols.name from mols where mol_id in (select mol_id from @mols_hist)
		set @to_mols = substring(@to_mols, 2, 8000)

		declare @affected_status_id int = (select status_id from tasks where task_id = @task_id)

        begin try
            declare @hists app_pkids
            insert into tasks_hists(task_id, action_name, mol_id, to_mols, to_mols_ids
                , description, body
                , is_private
                , query_status_id
                , parent_id, query_solution_id , query_solution_grades		
                , body_css
                , action_id
                , to_status_id
                )
                output inserted.hist_id into @hists
            values (
                @task_id, @action_name, @from_mol_id, @to_mols, @to_mols_ids
                , @comment, @body
                , case when charindex('Query', @action_id) > 0 then 1 else 0 end
                , case 
                    when @action_id = 'Query' then 0
                    when @action_id = 'QuerySolution' then 2
                end
                , @query_id, @query_solution_id, @query_solution_grades
                , case 
                    when not exists(select 1 from tasks_hists where task_id = @task_id) then 'alert alert-warning' 
                    when @type_id in (2,3) and @from_mol_id = @analyzer_id then 'alert alert-default' 
                end
                , @action_id
                , case
                    when isnull(@old_status_id, 0) <> isnull(@affected_status_id, 0) then @affected_status_id 
                end
                )

            select @hist_id = id from @hists
        end try
        begin catch
            declare @errtry varchar(max) = error_message()
            raiserror (@errtry, 16, 3)
        end catch

	-- TASKS_QUERY
		if @action_id = 'Query'
		begin
			;update tasks_hists set parent_id = @hist_id where hist_id = @hist_id
			;insert into tasks_hists_mols(hist_id, mol_id) select @hist_id, mol_id from @mols
		end

		else if @action_id = 'QueryRespond'
		begin
			update tasks_hists_mols
			set d_respond = getdate()
			where hist_id = @query_id
				and mol_id = @from_mol_id

			update tasks_hists
			set query_status_id = 
					case
						when exists(select 1 from tasks_hists_mols where hist_id = @hist_id and d_respond is null) then 0
						else 1
					end
			where parent_id = @query_id
		end

		else if @action_id = 'QuerySolution'
		begin
			if @query_id is not null
				update tasks_hists set query_status_id = 2 where parent_id = @query_id
			else
				update tasks_hists set parent_id = @hist_id where hist_id = @hist_id			
		end

	-- TASKS_HISTS_MOLS
		if @sync_hist_mols = 1
		begin
			insert into tasks_hists_mols(hist_id, mol_id)
			select @hist_id, mol_id from @mols_hist x
			where not exists(select 1 from tasks_hists_mols where hist_id = @hist_id and mol_id = x.mol_id)

			-- Удалить tasks_hists_mols, если у сотрудника нет доступа.
			-- Это может произойти, например, при действиях: Переадресовать, Отозвать
			delete hm
			from tasks_hists_mols hm
				join tasks_hists h on h.hist_id = hm.hist_id
			where h.task_id = @task_id
				and not exists(select 1 from tasks_mols where task_id = h.task_id and mol_id = hm.mol_id)
		end

	-- EXECUTOR_NAME
		declare @count int, @executor varchar(50), @executors varchar(max)

		update x
		set @count = (select count(*) from tasks_mols where task_id = x.task_id and role_id = 1),
			@executor = (
				select top 1 m.name
				from tasks_mols tm
					join mols m on m.mol_id = tm.mol_id
				where tm.task_id = x.task_id
					and role_id = 1
						),
			@executors = (
				select top 2 cast(m.name as varchar) + '; ' as [text()]
				from tasks_mols tm
					join mols m on m.mol_id = tm.mol_id
				where tm.task_id = x.task_id
					and role_id = 1
				for xml path('')
						),
			executor_name = 
				case
					when @count = 1 then @executor
					when @count between 1 and 2 then @executors
					when @count > 2 then @executors + ' ... (' + cast(@count as varchar) + ')'
				end
		from tasks x	
		where x.task_id = @task_id

end
go
-- helper: normalize tasks_mols
create proc task_sign;2
	@task_id int
as
begin

	declare @theme_id int, @author_id int, @analyzer_id int
		select 
			@author_id = author_id,
			@analyzer_id = analyzer_id,
			@theme_id = theme_id
		from tasks where task_id = @task_id

	insert into tasks_mols(task_id, role_id, mol_id, slice) 
	select distinct task_id, role_id, mol_id, slice
	from (
		select task_id = @task_id, role_id = 10, mol_id = @author_id, slice = null
		union select @task_id, 20, analyzer_id, 'theme' from tasks_themes where theme_id = @theme_id and analyzer_id is not null
		union select @task_id, role_id, mol_id, 'theme' from tasks_themes_mols where theme_id = @theme_id
		) m
	where not exists(select 1 from tasks_mols where task_id = m.task_id and mol_id = m.mol_id and role_id = m.role_id)

	if not exists(select 1 from tasks_mols where task_id = @task_id and mol_id = @analyzer_id)
		insert into tasks_mols(task_id, role_id, mol_id) 
		select @task_id,
			case when @analyzer_id = @author_id then 1 else 20 end,
			@analyzer_id

end
go
