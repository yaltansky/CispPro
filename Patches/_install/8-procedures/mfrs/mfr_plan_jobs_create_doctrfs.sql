if object_id('mfr_plan_jobs_create_doctrfs') is not null drop proc mfr_plan_jobs_create_doctrfs
go
create proc mfr_plan_jobs_create_doctrfs
	@mol_id int,
	@subject_id int = null,
	@d_doc date = null,
	@place_id int = null,
	@place_to_id int = null,
	@place_mol_id int = null,
	@queue_id uniqueidentifier = null
as
begin
    set nocount on;

	declare @proc_name varchar(100) = object_name(@@procid)
	exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name
    if @@error != 0 return

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids
	
	if @queue_id is null
		insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfj')
	else
		insert into @buffer select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfj'

	declare @details table(
		place_id int,
        place_to_id int,
        item_id int,
		mfr_number varchar(100),
		unit_id int,
		quantity float
		)

	set @d_doc = isnull(@d_doc, dbo.today())
	if @subject_id is null set @subject_id = (select top 1 subject_id from mfr_plans where status_id = 1)
	
	-- @details
		insert into @details(place_id, place_to_id, item_id, mfr_number, unit_id, quantity)
		select j.place_id, j.place_to_id, x.item_id, mfr.number, u.unit_id, sum(fact_q)
		from mfr_plans_jobs_details x
            join mfr_plans_jobs j on j.plan_job_id = x.plan_job_id
			    join @buffer i on i.id = j.plan_job_id
			left join mfr_sdocs mfr on mfr.doc_id = x.mfr_doc_id
			join products_units u on u.name = 'шт'
        where (@place_id is null or j.place_id = @place_id)
            and (@place_to_id is null or j.place_to_id = @place_to_id)
		group by 
			j.place_id, j.place_to_id, x.item_id, mfr.number, u.unit_id
        having
            sum(fact_q) > 0

		if not exists(select 1 from @details)
		begin
			raiserror('Нет деталей для создания документов "Передаточная накладная".', 16, 1)
			return
		end

	BEGIN TRY
	BEGIN TRANSACTION
		
		declare @docs table(doc_id int primary key)
			
		-- sdocs			
			insert into sdocs(
				type_id, subject_id, d_doc,
				status_id, place_id, place_to_id,
				mol_id, add_date, add_mol_id
				)
			output inserted.doc_id into @docs
			select distinct
				10, @subject_id, @d_doc, 
				0, place_id, place_to_id,
				@place_mol_id, getdate(), @mol_id
            from @details;

			update x set number = concat(sbj.short_name, '/ДЕТ-', x.doc_id)
			from sdocs x
				join @docs i on i.doc_id = x.doc_id
				join subjects sbj on sbj.subject_id = x.subject_id

		-- sdocs_products
			insert into sdocs_products(doc_id, product_id, mfr_number, unit_id, plan_q, quantity)
			select d.doc_id, x.item_id, x.mfr_number, x.unit_id, x.quantity, x.quantity
			from @details x
				join sdocs sd on sd.place_id = x.place_id and sd.place_to_id = x.place_to_id
                    join @docs d on d.doc_id = sd.doc_id
				join products p on p.product_id = x.item_id
			order by d.doc_id, p.name;

		-- results
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'MFTRF'
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'MFTRF', doc_id, @mol_id from @docs;

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

end
go
