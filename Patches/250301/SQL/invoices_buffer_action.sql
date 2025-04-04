if object_id('invoices_buffer_action') is not null drop proc invoices_buffer_action
go
create proc invoices_buffer_action
	@mol_id int,
	@action varchar(32),
	@status_id int = null
as
begin

    set nocount on;

	declare @today datetime = dbo.today()
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

	declare @buffer as app_pkids
	insert into @buffer select id from dbo.objs_buffer(@mol_id, 'inv')

	declare @subject_id int = 15339 -- Техснаб
	
	BEGIN TRY
	BEGIN TRANSACTION

		declare @details table(			
			row_id int primary key,
			invoice_id int index ix_invoice,
			invoice_number varchar(100),
			agent_id int,
			mol_id int,
			mfr_doc_id int,    
			item_id int,
            payment_type nvarchar(250),
			value_ccy decimal(18,2),
			value_rur decimal(18,2),
			nds_ratio decimal(5,4)
			)
		
		declare @map table(
			payorder_id int primary key, invoice_id int
			)

		if @action = 'CheckAccess'
		begin
			if (
				select count(distinct sd.subject_id) 
				from sdocs sd
				where doc_id in (select id from @buffer)
				) > 1
			begin
				raiserror('Заявки на закупку должны быть из одного субъекта учёта.', 16, 1)
			end

			if dbo.isinrole_byobjs(@mol_id, 
				'Mfr.Admin,Mfr.Admin.Materials',
				'SBJ', @subject_id) = 0
			begin
				raiserror('У Вас нет доступа к модерации объектов в данном субъекте учёта (роли Mfr.Admin,Mfr.Admin.Materials).', 16, 1)
			end
		end

		else if @action = 'CreatePayordersByInvpays' 
		begin
			
			if dbo.isinrole_byobjs(@mol_id, 'Mfr.Admin.Materials', 'SBJ', @subject_id) = 0
			begin
				raiserror('У Вас нет доступа к выполнению действия %s в этом контексте.', 16, 1, @action)
				return
			end

			delete from @buffer
			insert into @buffer select id from dbo.objs_buffer(@mol_id, 'invpay')

			insert into @details(
				row_id, invoice_id, invoice_number, agent_id, mol_id, mfr_doc_id, item_id, payment_type, nds_ratio, value_ccy, value_rur
				)
			select
				x.row_id,
				x.inv_id,
				i.number,
				i.agent_id,
				@mol_id,
				x.mfr_doc_id,
				x.item_id,
                ms.name,
				nds.nds_ratio,
				x.inv_value - isnull(x.findoc_value,0),
				x.inv_value - isnull(x.findoc_value,0)
			from supply_r_invpays_totals x
				join @buffer buf on buf.id = x.row_id
				join supply_invoices i on i.doc_id = x.inv_id
                join sdocs_milestones_names ms on ms.milestone_id = x.inv_milestone_id
				join (
					select doc_id, item_id = product_id, nds_ratio = max(nds_ratio)
					from supply_invoices_products
					group by doc_id, product_id
				) nds on nds.doc_id = x.inv_id and nds.item_id = x.item_id
			where x.inv_value - isnull(x.findoc_value,0)  > 1

			-- шапки заявок
				insert into payorders(
					dbname, reserved, type_id, subject_id, status_id, agent_id, recipient_id, 
                    payment_type, number,
                    ccy_id, mol_id, refkey, note
					)
				output inserted.payorder_id, cast(inserted.reserved as int) into @map
				select 
					db_name(),
                    d.invoice_id,
					4, -- Заявка на материалы
					@subject_id,
					0, -- Черновик
					d.agent_id,
					d.agent_id,
					(
                        select payment_type + ','  [text()] 
                        from (
                            select distinct payment_type from @details where invoice_id = d.invoice_id
                            ) pp
                        for xml path('')                        
                    ),
                    concat(d.invoice_number,  ' от ',  convert(varchar, inv.d_doc, 104)),
                    'RUR',
					max(d.mol_id),
					concat('/dummy/ref/', d.agent_id),
                    inv.note
				from @details d
                    join sdocs inv on inv.doc_id = d.invoice_id
				group by d.invoice_id, d.invoice_number, d.agent_id, inv.d_doc, inv.note

			-- детализация заявки
				insert into payorders_materials(
					payorder_id, invoice_id, mfr_doc_id, item_id, value_ccy, value_rur, nds_ratio
					)
				select
					map.payorder_id,
					x.invoice_id,
					x.mfr_doc_id,
					x.item_id,
					sum(x.value_ccy),
					sum(x.value_rur),
					max(x.nds_ratio)
				from @details x
					join @map map on map.invoice_id = x.invoice_id
				group by 
					map.payorder_id, x.invoice_id, x.mfr_doc_id, x.item_id

			-- поместить в буфер заявки
				delete from objs_folders_details where folder_id = @buffer_id
					and obj_type = 'PO'
		
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'PO', payorder_id, @mol_id
				from @map

			-- отметить статусом строки журнала
				if @action = 'CreatePayordersByInvpays'
					update x set inv_condition_pay = 'заявка'
					from supply_r_invpays_totals x
						join @details xx on xx.row_id = x.row_id
		end

		else if @action = 'BindStatus'
		begin
			exec invoices_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

			update x set 
				status_id = @status_id,
				update_mol_id = @mol_id, update_date = getdate()
			from sdocs x
				join @buffer i on i.id = x.doc_id
		end

		else if @action = 'ExpandInvPaysByInvoices'
			exec objs_folder_getrefs @mol_id = @mol_id, @folder_id = -1, @obj_type_source = 'invpay', @obj_type_target = 'invpayByInvoices'

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		if @@trancount > 0 rollback transaction
		declare @err varchar(max) = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

end
go
