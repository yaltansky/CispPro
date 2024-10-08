if object_id('mfr_docs_archive') is not null drop proc mfr_docs_archive
go
-- exec mfr_docs_archive 1000
create proc [mfr_docs_archive]
	@mol_id int,
	@ignore_check_jobs bit = 0
as
begin

	set nocount on;

	raiserror('Метод в настоящий момент не используется.', 16, 1)

	declare @proc_name varchar(50) = object_name(@@procid)
	exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name

	declare @use_archive_docs bit = isnull(cast((select dbo.app_registry_value('MfrUseArchiveDocs')) as bit), 0)
	if @use_archive_docs = 0
	begin
		raiserror('Для данной базы данных авто-архивирование не применяется.', 16, 1)
		return
	end

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

	-- @plans, @docs
		declare @plans as app_pkids, @docs as app_pkids

		insert into @plans select id from dbo.objs_buffer(@mol_id, 'mfp')
		insert into @docs select doc_id from mfr_sdocs where status_id >= 0
			and plan_id in (select id from @plans)
		
-- /*** DEBUG ***/
-- UPDATE SDOCS SET STATUS_ID = 100 WHERE STATUS_ID <> 100 
-- 	AND DOC_ID IN (SELECT ID FROM @DOCS)
-- /*** DEBUG ***/

	-- check docs
		if exists(
			select 1 from mfr_sdocs
			where doc_id in (select id from @docs)
				and status_id <> 100
			)
		begin
			-- docs --> buffer
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfr'
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'mfr', doc_id, @mol_id from mfr_sdocs
			where (status_id between 0 and 99)
				and doc_id in (select id from @docs)

			raiserror('Среди заказов есть заказы вне статуса "Закрыто". Эти заказы не могут быть архивированы.', 16, 1)
			return
		end

	-- #jobs_items
		select r.*
		into #jobs_items
		from mfr_r_plans_jobs_items r
			join (
				select distinct job_id
				from mfr_r_plans_jobs_items r
					join @docs i on i.id = r.mfr_doc_id
			) rr on rr.job_id = r.job_id

	-- #provides
		select r.*
		into #provides
		from mfr_r_provides r
			join (
				-- счета поставщикам
				select distinct r.row_id
				from mfr_r_provides r
					join (
						select distinct id_invoice
						from mfr_r_provides r
							join @docs i on i.id = r.mfr_doc_id
					) rr on rr.id_invoice = r.id_invoice

				-- приходы на склад
				union all

				select distinct r.row_id
				from mfr_r_provides r
					join (
						select distinct id_ship
						from mfr_r_provides r
							join @docs i on i.id = r.mfr_doc_id
					) rr on rr.id_ship = r.id_ship

				-- выдача в производство
				union all

				select distinct r.row_id
				from mfr_r_provides r
					join (
						select distinct id_job
						from mfr_r_provides r
							join @docs i on i.id = r.mfr_doc_id
					) rr on rr.id_job = r.id_job
			) rr on rr.row_id = r.row_id
			
	-- check jobs
		declare @check_jobs as app_pkids
			insert into @check_jobs
			select distinct r.job_id
			from #jobs_items r
			where slice = 'mix'
				and not exists(select 1 from @docs where id = r.mfr_doc_id)
				and r.job_status_id <> 100

		if @ignore_check_jobs = 0 and exists(select 1 from @check_jobs)
		begin		
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfj'
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'mfj', id, @mol_id from @check_jobs

			raiserror('Обнаружены открытые сменные задания, связанные с архивными заказами. Эти занадания необходимо закрыть и повторить операцию.', 16, 1)
			return
		end

	BEGIN TRY
	BEGIN TRANSACTION
	-- archive jobs
		-- mfr_plans_jobs
			update mfr_plans_jobs set status_id = -100
			where plan_job_id in (select distinct job_id from #jobs_items)

		-- mfr_r_plans_jobs_items_0
			delete x from mfr_r_plans_jobs_items_0 x
			where exists(select 1 from @docs where id = x.mfr_doc_id)

			-- сохранить факт реализации готовой продукции
				insert into mfr_r_plans_jobs_items_0(
					plan_id, mfr_doc_id, content_id, item_id, oper_number, job_id, job_detail_id, job_date, job_status_id, plan_q, fact_q, slice
					)
				select
					x.plan_id, x.mfr_doc_id, x.content_id, x.item_id, oper_number, job_id, job_detail_id, job_date, job_status_id, plan_q, fact_q,
					'products'
				from #jobs_items x
					join @docs i on i.id = x.mfr_doc_id
					join sdocs_mfr_contents c with(nolock) on c.content_id = x.content_id
				where c.product_id = c.item_id -- готовая продукция
				
				delete x from #jobs_items x where exists(select 1 from @docs where id = x.mfr_doc_id)

			-- сохранить открытую часть сменных заданий
				insert into mfr_r_plans_jobs_items_0(
					plan_id, mfr_doc_id, content_id, item_id, oper_number, job_id, job_detail_id, job_date, job_status_id, plan_q, fact_q, slice
					)
				select
					plan_id, mfr_doc_id, content_id, item_id, oper_number, job_id, job_detail_id, job_date, job_status_id, plan_q, fact_q,
					'reminds'
				from #jobs_items x

	-- archive provides
		-- sdocs
			update x set status_id = -100
			from sdocs x				
			where type_id in (8,9,12)
				and doc_id in (
					select distinct id_invoice from #provides where id_invoice is not null
					union all select distinct id_ship from #provides where id_ship is not null
					union all select distinct id_job from #provides where id_job is not null
				)
		
		-- mfr_r_provides_0
			delete x from mfr_r_provides_0 x
			where exists(select 1 from @docs where id = x.mfr_doc_id)

			delete x from #provides x where exists(select 1 from @docs where id = x.mfr_doc_id)

			insert into mfr_r_provides_0(
				mfr_doc_id, item_id, unit_name, agent_id, id_mfr, id_order, id_invoice, id_ship, id_job, d_mfr, d_mfr_to, d_order, d_invoice, d_delivery, d_ship, d_job, q_mfr, q_order, q_invoice, q_ship, q_job, price_invoice, slice
				)
			select
				mfr_doc_id, item_id, unit_name, agent_id, id_mfr, id_order, id_invoice, id_ship, id_job, d_mfr, d_mfr_to, d_order, d_invoice, d_delivery, d_ship, d_job, q_mfr, q_order, q_invoice, q_ship, q_job, price_invoice, slice
			from #provides

	-- archive mfr_docs
		-- -- plan_id
		-- 	declare @plan_id int = (select top 1 plan_id from mfr_plans where status_id = 100 and number like '%архив%' order by plan_id desc)
		-- 	if @plan_id is null
		-- 	begin
		-- 		declare @subject_id int = (select top 1 subject_id from mfr_plans where status_id > 0)
		-- 		insert into mfr_plans(subject_id, number, status_id, d_from, d_to) values(@subject_id, 'Архив', 100, dbo.today(), dbo.today())
		-- 		set @plan_id = @@identity
		-- 	end	

		-- sdocs
			update sdocs set status_id = -100 where doc_id in (select id from @docs)
			update mfr_plans set status_id = 100 where plan_id in (select id from @plans)

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) = error_message()
		raiserror (@err, 16, 3)
	END CATCH

	final:
		exec drop_temp_table '#jobs_items,#provides'
		return
	mbr:
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		raiserror('manual break', 16, 1)
end
GO
