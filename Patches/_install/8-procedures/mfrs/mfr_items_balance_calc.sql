if object_id('mfr_items_balance_calc') is not null drop proc mfr_items_balance_calc
go
-- exec mfr_items_balance_calc 1
create proc mfr_items_balance_calc
	@inforce bit = 0
as
begin

	set nocount on;	

	declare @d_calc datetime = isnull((select top 1 d_calc from mfr_r_items_balance), '1900-01-01')
	if @inforce = 0 and datediff(minute, @d_calc, getdate()) <= 10
	begin
		print 'Register MFR_R_ITEMS_BALANCE is actual. No calculation nedeed.'
		return -- not expired
	end

	truncate table mfr_r_items_balance

	declare @calc_by_doc int = isnull(cast((select dbo.app_registry_value('MfrCalcBalanceByDoc')) as int), 0)
	declare @date_start date = cast((select dbo.app_registry_value('MfrItemsBalanceDateStart')) as date)

    create table #docs(id int primary key)
    insert into #docs select doc_id from mfr_sdocs where plan_status_id = 1 and status_id between 0 and 99

	-- sdocs (10,12): передаточные накладные деталей, выдача в производство материвлов
		-- приход на участок PLACE_ID
		insert into mfr_r_items_balance(
			place_id, mfr_doc_id, item_id, doc_id, d_doc, quantity, unit_name
			)
		select 
			sd.place_to_id,
			mfr_doc_id = case when @calc_by_doc = 1 then mfr.doc_id end,
			sp.product_id, sp.doc_id, sd.d_doc, 
			sp.quantity, u.name
		from sdocs sd
			join sdocs_products sp on sp.doc_id = sd.doc_id
				join mfr_sdocs mfr on mfr.number = sp.mfr_number
                    join #docs i on i.id = mfr.doc_id
				join products_units u on u.unit_id = sp.unit_id
		where sd.type_id in (10,12)
			and (@date_start is null or sd.d_doc >= @date_start)
			-- and (@d_to is null or sd.d_doc <= @d_to)
			and sd.status_id != -1

		-- расход с участка PLACE_ID
		insert into mfr_r_items_balance(
			place_id, mfr_doc_id, item_id, doc_id, d_doc, quantity, unit_name
			)
		select 
			sd.place_id,
			mfr_doc_id = case when @calc_by_doc = 1 then mfr.doc_id end,
			sp.product_id, sp.doc_id, sd.d_doc, 
			-sp.quantity, u.name
		from sdocs sd
			join sdocs_products sp on sp.doc_id = sd.doc_id
				join mfr_sdocs mfr on mfr.number = sp.mfr_number
                    join #docs i on i.id = mfr.doc_id
				join products_units u on u.unit_id = sp.unit_id
		where sd.type_id in (10)
			and (@date_start is null or sd.d_doc >= @date_start)
			-- and (@d_to is null or sd.d_doc <= @d_to)
			and sd.status_id != -1

	-- @jobs
		declare @jobs table(
			oper_id int index ix_oper,
			mfr_doc_id int,
			product_id int,
			child_id int,			
			content_id int,
			item_id int,			
			place_id int,		
			job_id int,
			job_date date,
			quantity float,
			unit_name varchar(20),
			k_part float not null default(1),
			index ix_join (mfr_doc_id, product_id, child_id)			
			)
	
		-- items (of opened sdocs)
		insert into @jobs(
			mfr_doc_id, product_id, child_id, content_id, item_id, oper_id, place_id,
			job_id, job_date,
			quantity, k_part, unit_name
			)
		select 
			c.mfr_doc_id, c.product_id, c.child_id, c.content_id, c.item_id, o.oper_id, isnull(j.place_id, o.place_id), 
			r.job_id, r.job_date,
			r.fact_q, r.fact_q / nullif(c.q_brutto_product,0), c.unit_name
		from v_mfr_r_plans_jobs_items_all r
			join sdocs_mfr_contents c on c.content_id = r.content_id
			join sdocs_mfr_opers o on o.oper_id = r.oper_id and o.is_first = 1
			join mfr_sdocs mfr on mfr.doc_id = r.mfr_doc_id
                join #docs i on i.id = mfr.doc_id
			join mfr_plans_jobs j on j.plan_job_id = r.job_id
		where c.is_buy = 0
			and c.has_childs = 1
			and r.fact_q > 0			
			and (@date_start is null or r.job_date >= @date_start)
			and mfr.status_id != -1

		-- childs
		insert into @jobs(
            place_id, mfr_doc_id, product_id, content_id, item_id, job_id, job_date, quantity, unit_name)
		select 
            isnull(c.place_id, x.place_id),
            x.mfr_doc_id, c.product_id, c.content_id, c.item_id, 
            x.job_id, x.job_date, -x.k_part*c.q_brutto_product, c.unit_name
		from @jobs x
			join sdocs_mfr_contents c on c.mfr_doc_id = x.mfr_doc_id and c.product_id = x.product_id and c.parent_id = x.child_id

		-- mfr_r_items_balance
		insert into mfr_r_items_balance(place_id, mfr_doc_id, item_id, content_id, job_id, d_doc, quantity, unit_name)
		select place_id, mfr_doc_id, item_id, content_id, job_id, job_date, sum(quantity), unit_name
		from (
			select 
				place_id,
				mfr_doc_id = case when @calc_by_doc = 1 then mfr_doc_id end,
				item_id,
				content_id,
				job_id, job_date, quantity, unit_name
			from @jobs
			-- where (@d_to is null or job_date <= @d_to)
			) x
		group by place_id, mfr_doc_id, item_id, content_id, job_id, job_date, unit_name

	-- -- write-off balances
	-- 	if @d_to is not null exec mfr_items_balance_calc;2 @d_to = @d_to, @subject_id = @subject_id

end
go
-- helper: write-off balances (списание остатков в "ноль")
-- create proc mfr_items_balance_calc;2
-- 	@d_to date,
-- 	@subject_id int
-- as
-- begin
-- 	declare @output table(
-- 		subject_id int, place_id int, product_id int, mfr_doc_id int, unit_id int, quantity float,
-- 		index ix_join (subject_id, place_id)
-- 		)

-- 	insert into @output(subject_id, place_id, product_id, mfr_doc_id, unit_id, quantity)
-- 	select
-- 		@subject_id,
-- 		x.place_id,
-- 		x.item_id,
-- 		x.mfr_doc_id,
-- 		max(isnull(u.unit_id,0)),
-- 		sum(x.quantity)			
-- 	from mfr_r_items_balance x
-- 		left join products_units u on u.name = x.unit_name
-- 		join mfr_places pl on pl.place_id = x.place_id
-- 	group by x.place_id, x.item_id, x.mfr_doc_id
-- 	having abs(sum(x.quantity)) > 0.001

-- 	if exists(select 1 from @output)
-- 	begin
-- 		declare @new_docs table(
-- 			id int identity, subject_id int, place_id int, doc_id int, 
-- 			index ix_join (subject_id, place_id)
-- 			)
-- 		insert into @new_docs(subject_id, place_id)
-- 		select distinct subject_id, place_id from @output

-- 		BEGIN TRY
-- 		BEGIN TRANSACTION
				
-- 			declare @seed int = isnull((select max(doc_id) from sdocs), 0)
-- 			update @new_docs set doc_id = @seed + id

-- 			SET IDENTITY_INSERT SDOCS ON
			
-- 				declare @place_inv int = (select top 1 place_id from mfr_places where note = 'Инвентаризация')
-- 					if @place_inv is null begin
-- 						insert into mfr_places(subject_id, name, note) values(@subject_id, 'INV', 'Инвентаризация')
-- 						set @place_inv = @@identity
-- 					end					
				
-- 				-- sdocs
-- 				insert into sdocs(type_id, doc_id, subject_id, place_to_id, d_doc, number, status_id, note, add_mol_id)
-- 				select 
-- 					10, doc_id, subject_id, place_id, @d_to, 
-- 					concat('ИНВ/', convert(varchar, @d_to, 20), '/', id),
-- 					100,
-- 					'Списание остатков',
-- 					-25
-- 				from @new_docs

-- 				-- sdocs_products
-- 				insert into sdocs_products(doc_id, product_id, quantity, unit_id)
-- 				select d.doc_id, x.product_id, -x.quantity, x.unit_id
-- 				from @output x
-- 					join @new_docs d on d.subject_id = x.subject_id and d.place_id = x.place_id

-- 			SET IDENTITY_INSERT SDOCS OFF

-- 		COMMIT TRANSACTION
-- 		END TRY

-- 		BEGIN CATCH
-- 			IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
-- 			declare @err varchar(max) set @err = error_message()
-- 			raiserror (@err, 16, 1)
-- 		END CATCH
-- 	end
-- end
-- go
