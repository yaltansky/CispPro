if object_id('buyorders_create_invoices') is not null drop proc buyorders_create_invoices
go
create proc buyorders_create_invoices
	@mol_id int,
	@queue_id uniqueidentifier = null
as
begin

    set nocount on;

	declare @today datetime = dbo.today()	

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids
		if @queue_id is null
			insert into @buffer select id from dbo.objs_buffer(@mol_id, 'buyorder')
		else
			insert into @buffer select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'buyorder'

	exec buyorders_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

	BEGIN TRY
	BEGIN TRANSACTION
		declare @docs table(
			doc_id int, agent_id int
			primary key(agent_id)
			)

		declare @details table(
			subject_id int,
			agent_id int,
			doc_id int,
			mol_id int,
            product_id int,
			unit_id int,
			quantity float,
            mfr_number varchar(100),
			price_pure float,
			nds_ratio decimal(5,4),
			index ix (agent_id,mol_id,product_id)
			)

		insert into @details(
			subject_id, agent_id, doc_id, mol_id, product_id, unit_id, quantity, mfr_number, nds_ratio, price_pure
			)
		select
			sd.subject_id, sd.agent_id, sd.doc_id, @mol_id, x.product_id, x.unit_id, x.quantity, x.mfr_number, x.nds_ratio, x.price_pure
		from sdocs_products x
			join sdocs sd on sd.doc_id = x.doc_id
			join @buffer buf on buf.id = x.doc_id
		where sd.status_id between 0 and 99 -- до статуса "Закрыт"

		if exists(select 1 from @details)
		begin		
			-- sdocs
				insert into sdocs(
					subject_id, type_id, status_id, d_doc, agent_id, mol_id, ccy_id, add_mol_id, add_date
					)
					output inserted.doc_id, inserted.agent_id into @docs
				select 
					subject_id, 8, 0, @today, agent_id, @mol_id, 'RUR',			
					@mol_id, getdate()
				from @details
				group by subject_id, agent_id

				-- parents (счёт --> заявка, один-ко-многим)
					update x set parent_id = i.doc_id
					from sdocs x
						join @buffer b on b.id = x.doc_id
						join @docs i on i.agent_id = x.agent_id

				update x set 
					number = concat(s.short_name, '/СЧ/', x.doc_id),
					refkey = concat('/finance/invoices/', doc_id) 
				from sdocs x
					join subjects s on s.subject_id = x.subject_id
				where x.doc_id in (select doc_id from @docs)
				
				print concat('created ', @@rowcount, ' invoices')

			-- sdocs_products
				insert into sdocs_products(
					doc_id, product_id, unit_id, nds_ratio, quantity, price_pure
					)
				select
					d.doc_id, x.product_id, min(x.unit_id), min(x.nds_ratio), sum(x.quantity), min(x.price_pure)
				from @details x
					join @docs d on d.agent_id = x.agent_id
				group by d.doc_id, x.product_id

            -- sdocs_products_details
                insert into sdocs_products_details(
                    doc_id, detail_id, mfr_number, quantity, add_mol_id
                    )
                select x.doc_id, x.detail_id, xx.mfr_number, xx.quantity, @mol_id
                from sdocs_products x
                    join @docs d on d.doc_id = x.doc_id
                        join @details xx on xx.agent_id = d.agent_id and xx.product_id = x.product_id

				declare @ids as app_pkids; insert into @ids select doc_id from @docs
				exec invoices_calc_milestones @docs = @ids

			-- status_id (express method)
				update x set status_id = 5 -- к оплате
				from sdocs x
					join @buffer buf on buf.id = x.doc_id
				where x.status_id < 5

			-- results
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'inv'
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'inv', doc_id, @mol_id from @docs

		end

		else
			print 'creating invoices: nothing to do'

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

end
go
