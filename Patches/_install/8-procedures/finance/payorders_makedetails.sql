if object_id('payorders_makedetails') is not null drop proc payorders_makedetails
go
-- exec payorders_makedetails 1000, 12662
create proc payorders_makedetails
	@mol_id int,
	@payorder_id int = null,
	@folder_id int = null
as
begin

	set nocount on;

	declare @ids as app_pkids
		if @payorder_id is not null
			insert into @ids select @payorder_id
		else
			insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'po'
	
	declare @findocs table(findoc_id int primary key, payorder_id int)

	-- reglament
		declare @objects as app_objects; insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id, @for_update = 1
		declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	
	-- check
		if exists(
			select 1 from findocs
			where findoc_id in (select findoc_id from @findocs)
				and subject_id not in (select subject_id from @subjects)
			)
		begin
			raiserror('У Вас нет доступа к изменению оплат в буфере в соответствии с правами на субъект учёта.', 16, 1)
		end

	declare @findocs_details table (id int primary key, findoc_id int, value_ccy decimal(18,2))
	declare @badids varchar(max), @buffer_id int, @err varchar(max)

	insert into @findocs(findoc_id, payorder_id)
	select findoc_id, max(x.payorder_id) from payorders_pays x 
	where payorder_id in (select id from @ids)
		and not exists(select 1 from findocs_details where findoc_id = x.findoc_id)
	group by findoc_id

	BEGIN TRY
	BEGIN TRANSACTION

		if exists(select 1 from @findocs)
			and exists(select 1 from payorders_details where payorder_id in (select payorder_id from @findocs))
		begin
			-- make details
			insert into findocs_details(findoc_id, budget_id, article_id, value_ccy)
			output inserted.id, inserted.findoc_id, inserted.value_ccy into @findocs_details
			select 
				x.findoc_id, pd.budget_id, pd.article_id,
				-- пропорционально оплате
				cast(x.value_ccy / nullif(p.value_ccy,0) as float) * pd.value_ccy
			from findocs x
				join @findocs i on i.findoc_id = x.findoc_id
					join payorders_details pd on pd.payorder_id = i.payorder_id
						join payorders p on p.payorder_id = pd.payorder_id
			where abs(isnull(pd.value_ccy,0)) > 0.00
				and pd.is_deleted = 0

			-- округление
			update fd
			set value_ccy = value_ccy + value_diff
			from findocs_details fd
				join (
					select xx.id, x.value_ccy - xx.value_ccy as value_diff
					from findocs x
						join (
							select findoc_id, max(id) as id, sum(value_ccy) as value_ccy
							from @findocs_details
							group by findoc_id
						) xx on xx.findoc_id = x.findoc_id
					where abs(x.value_ccy - xx.value_ccy) between 0.01 and 1.00
				) diff on diff.id = fd.id

			-- checksum		
				if exists(
					select 1
					from findocs x
						join @findocs i on i.findoc_id = x.findoc_id
						join (
							select findoc_id, sum(value_ccy) as value_ccy
							from findocs_details
							group by findoc_id
						) xx on xx.findoc_id = x.findoc_id
					where abs(x.value_ccy - xx.value_ccy) > 0.01
					)
				begin
					set @badids = (
						select distinct concat(x.findoc_id, ' - ', cast(x.value_ccy - xx.value_ccy as decimal(18,2))) + ',' [text()]
						from findocs x
							join @findocs i on i.findoc_id = x.findoc_id
							join (
								select findoc_id, sum(value_ccy) as value_ccy
								from findocs_details
								group by findoc_id
							) xx on xx.findoc_id = x.findoc_id
						where abs(x.value_ccy - xx.value_ccy) > 0.01
						for xml path('')
						)
					raiserror('При формировании детализации оплаты не совпали контрольные суммы (%s). Это может быть при ошибочной связи заявка-оплаты.', 16, 1, @badids)
				end

			-- buffer
				set @buffer_id = dbo.objs_buffer_id(@mol_id)
				
				delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'fd'
			
				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'fd', findoc_id, @mol_id from @findocs

			-- return value
				select count(*) as count_findocs from @findocs
		end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		if @@trancount > 0 rollback transaction
		set @err = error_message()
		raiserror (@err, 16, 1)
	END CATCH

end
go
