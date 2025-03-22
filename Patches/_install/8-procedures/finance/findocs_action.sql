if object_id('findocs_action') is not null drop proc findocs_action
go
-- exec findocs_action 1000, 'createPayorders', 46617, 9, 1
create proc findocs_action
	@mol_id int,
	@action varchar(32),
	@folder_id int = null,
	@principal_id int = null,
	@groupby_vendor bit = 1
as
begin

	set nocount on;

	BEGIN TRY
	BEGIN TRANSACTION

		if @action = 'createPayorders'
		begin

			-- "окрасить" приходы
				create table #resultInputs(
					row_id int,
					folder_id int,
					vendor_id int,
					budget_id int,
					deal_product_id int,
					article_id int,
					d_doc date,
					findoc_id int index ix_findoc,
					value float,
					value_nds float
					)			
				exec findocs_mkdetails @mol_id = @mol_id, @folder_id = @folder_id

			declare @ids as app_pkids
			insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'fd'

			-- @details
				declare @details table(subject_id int, agent_id int, vendor_id int, budget_id int, article_id int, value_rur decimal(18,2))
					insert into @details(subject_id, agent_id, vendor_id, budget_id, article_id, value_rur)
					select subject_id, agent_id, vendor_id, budget_id, article_id, sum(value)
					from (			
						select 
							f.subject_id,
							agent_id = (select pred_id from subjects where subject_id = @principal_id),
							vendor_id = case when @groupby_vendor = 1 then x.vendor_id end,
							x.budget_id,
							x.article_id,
							x.value
						from #resultInputs x
							join findocs f on f.findoc_id = x.findoc_id
							join @ids i on i.id = x.findoc_id
						) x
					group by subject_id, agent_id, vendor_id, budget_id, article_id

			-- payorders
				declare @today datetime = dbo.today()
				declare @map table(payorder_id int primary key, vendor_id int)

				insert into payorders(dbname, type_id, mol_id, subject_id, d_pay_plan, agent_id, recipient_id, ccy_id, note, reserved)
					output inserted.payorder_id, cast(inserted.reserved as int) into @map
				select db_name(), 1, @mol_id, subject_id, @today, agent_id, agent_id, 'RUR',
					case when vendor_id is not null then concat('Производитель ', (select name from agents where agent_id = (select pred_id from subjects where subject_id = vendor_id))) end,
					vendor_id
				from (
					select subject_id,  agent_id, vendor_id, value_rur = sum(value_rur)
					from @details
					group by subject_id,  agent_id, vendor_id
				) x

			-- payorders_details
				insert into payorders_details(payorder_id, budget_id, article_id, value_ccy)
				select m.payorder_id, x.budget_id, x.article_id, x.value_rur
				from @details x
					join @map m on isnull(m.vendor_id,0) = isnull(x.vendor_id,0)

			-- place orders to buffer
				declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'po'
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'po', payorder_id, @mol_id
				from @map
		end

		else if @action = 'compactDetails'
		begin

			select findoc_id into #ids from findocs_details group by findoc_id having count(*) = 1

			update x
			set budget_id = fd.budget_id,
				article_id = fd.article_id
			from findocs x
				join findocs_details fd on fd.findoc_id = x.findoc_id
				join #ids i on i.findoc_id = x.findoc_id

			delete from findocs_details
			where findoc_id in (select findoc_id from #ids)		

		end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
	END CATCH

end
go
