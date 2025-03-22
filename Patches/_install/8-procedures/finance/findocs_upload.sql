if object_id('findocs_upload') is not null drop proc findocs_upload
go
create proc findocs_upload
	@mol_id int,
	@group_id uniqueidentifier
as
begin
	
	set nocount on;

	begin
		-- #accounts	
		create table #accounts (		
			upload_id int,
			account_id int,
			number varchar(50),
			date_from datetime,
			date_to datetime,
			ccy_id varchar(3),
			saldo_in decimal(18,2),
			saldo_out decimal(18,2)
		)

		-- #pays
		create table #pays (
			row_id int identity primary key,
			findoc_id int,
			d_doc datetime,
			subject_id int,
			account_id int,
			number varchar(100),
			agent_id int,
			agent_name varchar(255),
			agent_inn varchar(30),
			agent_acc varchar(50),
			note varchar(500),
			ccy_id char(3),
			value_ccy float NOT NULL default(0)
		)
	end -- #tables

	begin
		declare c_uploads cursor local read_only for 
			select upload_id from findocs_uploads where group_id = @group_id
		
		declare @upload_id int
		
		open c_uploads; fetch next from c_uploads into @upload_id
			while (@@fetch_status <> -1)
			begin
				if (@@fetch_status <> -2) exec findocs_upload;2 @upload_id
				fetch next from c_uploads into @upload_id
			end
		close c_uploads; deallocate c_uploads
	end -- parse

	-- process
		if not exists(select 1 from findocs_uploads where group_id = @group_id and errors is not null) begin
			exec findocs_upload;3 @mol_id = @mol_id
		end
		
		if object_id('tempdb.dbo.#accounts') is not null drop table #accounts
		if object_id('tempdb.dbo.#pays') is not null drop table #pays

	select * from findocs_uploads where group_id = @group_id
end
go
-- helper: prepare
create procedure findocs_upload;2
	@upload_id int
as
begin
	-- чтение xml
		declare @xml xml = (select data from findocs_uploads where upload_id = @upload_id)

	-- получим идентификатор XML
		declare @handle_xml int
		exec sp_xml_preparedocument @handle_xml output, @xml

		declare @errors table(error varchar(500))
		
		insert into @errors(error) select error
		from openxml (@handle_xml, '/FindocStatement/Errors/*', 2) with (
			error varchar(500) 'text()'
			)

		if exists(select 1 from @errors)
		begin
			update x
			set errors = (
				select error + ' ' [text()] from @errors for xml path('')
				)
			from findocs_uploads x
			where upload_id = @upload_id
			
			goto final
		end

	-- @subject_id
		declare @subject_id int, @mol_id int, @check_saldo bit
			select 			
				@subject_id = subject_id,
				@mol_id = mol_id,
				@check_saldo = check_saldo
			from findocs_uploads
			where upload_id = @upload_id

	-- #accounts
		insert into #accounts (upload_id, account_id, number, date_from, date_to, saldo_in, saldo_out)
			select top 1 @upload_id, AccId, AccNo, DateFrom, DateTo, SumStart, SumEnd
			from openxml (@handle_xml, '/FindocStatement', 2) with (
				AccId int 'AccId',
				AccNo varchar(100) 'AccNo',
				DateFrom datetime 'DateFrom',
				DateTo datetime 'DateTo',
				SumStart decimal(18,2) 'SumStart',
				SumEnd decimal(18,2) 'SumEnd'
				)

		if exists(select 1 from #accounts where upload_id = @upload_id and isnull(account_id,0) = 0)
		begin
			declare @account_number varchar(100) = (select number from #accounts where upload_id = @upload_id)
			declare @count_accounts int = isnull((select count(*) from findocs_accounts where subject_id = @subject_id and number = @account_number and is_deleted = 0), 0)

			-- попытаемся найти без субъекта
			if @count_accounts = 0
			begin
				set @count_accounts = isnull((select count(*) from findocs_accounts where number = @account_number and is_deleted = 0), 0)
				-- установим субъект в загрузке
				if @count_accounts = 1 begin
					set @subject_id = (select top 1 subject_id from findocs_accounts where number = @account_number and is_deleted = 0)
				end
			end

			if @count_accounts = 0
			begin
				update findocs_uploads
				set errors = concat(errors, case when errors is not null then '. ' end,
					'Финансовая книга с номером ', @account_number, ' не найдена')
				where upload_id = @upload_id
				goto final
			end

			else if @count_accounts > 1
			begin
				update findocs_uploads
				set errors = concat(errors, case when errors is not null then '. ' end,
					'Существует несколько ',
					'(', @count_accounts, ')',
					' финансовых книг в рамках выбранного субъекта учёта.'
					)
				where upload_id = @upload_id
				goto final
			end

		end

		update x
		set account_id = isnull(nullif(x.account_id,0), a.account_id),
			ccy_id = a.ccy_id
		from #accounts x
			join findocs_accounts a on a.subject_id = @subject_id and a.number = x.number
		where x.upload_id = @upload_id
			and a.is_deleted = 0

		declare 
			@account_id int, @ccy_id varchar(3),
			@date_from datetime,
			@saldo_in decimal(18,2),
			@saldo_out decimal(18,2)

			select 
				@account_id = account_id,
				@date_from = date_from,
				@ccy_id = ccy_id,
				@saldo_in = isnull(saldo_in,0),
				@saldo_out = isnull(saldo_out,0)
			from #accounts 
			where upload_id = @upload_id

		select @subject_id = subject_id from findocs_accounts where account_id = @account_id and is_deleted = 0

		update findocs_uploads
		set subject_id = @subject_id,
			account_id = @account_id,
			errors = null
		where upload_id = @upload_id

	-- check permissions
		declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id, @for_update = 1
		declare @subject_name varchar(100) = (select name from subjects where subject_id = @subject_id)

		-- @subjects
		if not exists(select 1 from @objects where obj_type = 'sbj' and obj_id = @subject_id)
		begin
			update findocs_uploads
			set errors = concat(errors, case when errors is not null then '. ' end,
				'У Вас нет доступа для импорта по субъекту учёта ',
				@subject_name, '.'
				)
			where upload_id = @upload_id
			goto final
		end

	-- #pays
		insert into #pays (subject_id, account_id, d_doc, number, agent_name, agent_acc, agent_inn, note, ccy_id, value_ccy)
			select @subject_id, @account_id, DocDate, DocNo, AgentName, AgentAcc, AgentINN, Note, @ccy_id, Value 
			from openxml (@handle_xml, '/FindocStatement/Rows/*', 2) WITH (
				DocNo varchar(150) 'DocNo',
				DocDate datetime 'DocDate',			
				AgentName varchar(150) 'AgentName',
				AgentINN varchar(50) 'AgentINN',
				AgentAcc varchar(30) 'AgentAcc',
				Value decimal(18,2) 'Value',
				Note varchar(500) 'Note'
			)

		update #accounts
		set date_from = (select min(d_doc) from #pays),
			date_to = (select max(d_doc) from #pays)
		where date_from = 0

	-- check saldo
		if @check_saldo = 1
		begin
			declare 
				@saldo_in_check decimal(18,2) = (
					select sum(value_ccy)
					from (
						select a.saldo_in as value_ccy from findocs_accounts a where account_id = @account_id
						union all
						select value_ccy from findocs where account_id = @account_id and d_doc < @date_from
						) f
					),
				@saldo_out_check decimal(18,2) = @saldo_in + (select sum(value_ccy) from #pays where account_id = @account_id)

			if abs(@saldo_in - @saldo_in_check) >= 0.01
			begin
				update findocs_uploads
				set errors = concat(errors, case when errors is not null then '. ' end,
					'Входящий остаток выписки ', @saldo_in,
					' не соответствует исходящему остатку ', @saldo_in_check, ' журнала оплат на утро ',
					convert(varchar, @date_from, 104), '.'
					)
				where upload_id = @upload_id
				goto final
			end

			if abs(@saldo_out - @saldo_out_check) >= 0.01
			begin
				update findocs_uploads
				set errors = concat(errors, case when errors is not null then '. ' end,
					'Исходящий остаток выписки ', @saldo_out,
					' не соответствует исходящему остатку ', @saldo_out_check, ' журнала оплат.'
					)
				where upload_id = @upload_id
				goto final
			end
		end

	-- rows count info
		update x
		set file_name = concat(x.file_name, ' (',
			(select count(*) from #pays where account_id = @account_id),
			' строк)'
			)
		from findocs_uploads x
		where upload_id = @upload_id

	-- purge log
		declare @purge_date datetime = dbo.today() - 7
		delete from findocs_uploads
		where add_date < @purge_date

	-- @handle_xml remove
	final:
	exec sp_xml_removedocument @handle_xml
end
go
-- helper: process data
create procedure findocs_upload;3
	@mol_id int
as
begin
	-- ccy_rates
		exec ccy_rates_calc

	-- agents
		-- by inn
			insert into agents(name, name_print, inn)
			select distinct agent_name, agent_name, agent_inn
			from #pays x
			where len(agent_inn) >= 10
				and not exists(
					select 1 from agents where status_id >= 0 and len(inn) >= 10
						and inn = x.agent_inn
					)

			update x
			set agent_id = a.agent_id
			from #pays x
				join (
					select inn, agent_id = min(agent_id) from agents
					where status_id = 1 and len(inn) >= 10
					group by inn
					having count(*) <= 3
				) a on a.inn = x.agent_inn
			where len(x.agent_inn) >= 10

		-- by name		
			insert into agents(name, name_print, inn)
			select distinct agent_name, agent_name, agent_inn
			from #pays
			where agent_id is null
				and agent_name not in (select name from agents)
				and agent_name <> '-'

			update x
			set agent_id = isnull(a.main_id, a.agent_id)
			from #pays x
				join agents a on a.name = x.agent_name
			where x.agent_id is null

		-- main_id
			update x
			set agent_id = pa.agent_id
			from #pays x
				join agents a on a.agent_id = x.agent_id
					join agents pa on pa.agent_id = a.main_id

	-- findoc_id
		-- попытка сохранить findoc_id
		update x
		set findoc_id = f.findoc_id
		from #pays x
			join (
				select account_id, d_doc, number, agent_id, value_ccy, note, max(findoc_id) as findoc_id
				from findocs
				group by account_id, d_doc, number, agent_id, value_ccy, note
			) f on f.account_id = x.account_id
				and f.d_doc = x.d_doc
				and f.number = x.number
				and f.agent_id = x.agent_id
				and f.value_ccy = x.value_ccy
				and f.note = x.note

		update x
		set findoc_id = null
		from #pays x
			join (
				select findoc_id, row_id = min(row_id)
				from #pays
				group by findoc_id
				having count(*) > 1
			) f on f.findoc_id = x.findoc_id
		where x.row_id <> f.row_id

		-- для остальных - новые FINDOC_ID
		declare @seed int = isnull((select max(findoc_id) from findocs), 0)
		update x
		set findoc_id = @seed + xx.new_id
		from #pays x
			join (
				select row_id,
					row_number() over (order by row_id) as new_id
				from #pays
				where findoc_id is null
			) xx on xx.row_id = x.row_id

	-- import
		DECLARE @TRANCOUNT INT = @@TRANCOUNT;	
		BEGIN TRY

			IF @TRANCOUNT = 0 BEGIN TRANSACTION
			ELSE SAVE TRANSACTION FINDOCS_UPLOAD

			-- check for rows count to update
				declare @deleted table(findoc_id int primary key)
				insert into @deleted select findoc_id
				from findocs x
					join #accounts a on a.account_id = x.account_id
						and x.d_doc between a.date_from and a.date_to

				if (select count(*) from @deleted) > 300
				begin
					declare @count_deleted int = (select count(*) from @deleted)
					raiserror('Слишком много записей (%d) должно быть обновлено, так что может возникнуть риск нежелательной потери данных. Уменьшите количество файлов для загрузки.', 16, 1, @count_deleted)
				end

			-- save findocs_details (if any)
				select * into #findocs from findocs where findoc_id in (select findoc_id from @deleted)
				select * into #findocs_details from findocs_details where findoc_id in (select findoc_id from @deleted)

				delete from findocs_details where findoc_id in (select findoc_id from @deleted)
				delete from findocs where findoc_id in (select findoc_id from @deleted)

			-- findocs
				declare @findocs table(findoc_id int)

				insert into findocs(
					findoc_id,		
					subject_id,
					account_id,
					d_doc,
					number,
					agent_id, agent_inn, agent_acc,
					budget_id,
					article_id,
					ccy_id,
					value_ccy,
					note
					)
					output inserted.findoc_id into @findocs
				select
					p.findoc_id,		
					p.subject_id,
					p.account_id,
					p.d_doc,
					p.number,
					p.agent_id,	p.agent_inn, p.agent_acc,
					f.budget_id,
					f.article_id,
					p.ccy_id,
					p.value_ccy,
					p.note
				from #pays p
					left join #findocs f on f.findoc_id = p.findoc_id

			-- restore details (if any)
				insert into findocs_details(findoc_id, budget_id, article_id, value_ccy, note)
				select fd.findoc_id, fd.budget_id, fd.article_id, fd.value_ccy, fd.note
				from #findocs_details fd
					join findocs f on f.findoc_id = fd.findoc_id	 

			-- @buffer
				declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
				delete from objs_folders_details where folder_id = @buffer_id
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'FD', findoc_id, @mol_id from @findocs
				
			-- findocs_accounts_calc
				declare @account_ids varchar(max) = (
					select cast(account_id as varchar) + ','  [text()] from #accounts for xml path('')
					)
				exec findocs_accounts_calc @account_ids = @account_ids

				drop table #findocs, #findocs_details

			IF @TRANCOUNT = 0 COMMIT TRANSACTION
		END TRY

		BEGIN CATCH
			declare @err varchar(max); set @err = error_message()
			declare @xstate int = xact_state()

			if @xstate = -1
				ROLLBACK TRANSACTION;
			else if @xstate = 1 and @trancount = 0
				ROLLBACK TRANSACTION;
			else if @xstate = 1 and @trancount > 0
				ROLLBACK TRANSACTION FINDOCS_UPLOAD;

			raiserror (@err, 16, 3)
		END CATCH
end
go
