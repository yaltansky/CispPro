if object_id('invoices_create_orders') is not null drop proc invoices_create_orders
go
create proc [invoices_create_orders]
	@mol_id int,
	@ignore_stoplist bit = 0,
	@queue_id uniqueidentifier = null,
	@checkonly bit = 0
as
begin

    set nocount on;

	declare @today datetime = dbo.today()	

	declare @buffer as app_pkids
		if @queue_id is null
			insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')
		else
			insert into @buffer select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'mfc'

	exec mfr_items_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

	if exists(
		select 1
		from mfr_sdocs_contents c 
			join @buffer buf on buf.id = c.content_id
		where c.supplier_id is null
			or c.manager_id is null
		)
	begin
		raiserror('Есть материальная потребность без поставщика и/или менеджера закупок. Воспользуйтесь фильтром для поиска и устраните проблему.', 16, 1)
		return
	end

	if @checkonly = 1 return

	if @ignore_stoplist = 0
		delete x from @buffer x
			join mfr_sdocs_contents c on c.content_id = x.id
				join supply_r_stoplist sl on sl.mfr_doc_id = c.mfr_doc_id

BEGIN TRY
BEGIN TRANSACTION
	declare @attr_id int = (select top 1 attr_id from prodmeta_attrs where name = 'закупка.Цена')

	declare @products table(
		product_id int primary key,
		price_pure float
		)
		insert into @products(product_id, price_pure)
		select c.item_id, min(pa.attr_value_number/(1.2))
		from mfr_sdocs_contents c 
			join @buffer buf on buf.id = c.content_id
			join products_attrs pa on pa.product_id = c.item_id and pa.attr_id = @attr_id
		group by c.item_id

	declare @docs table(
		doc_id int, agent_id int, mol_id int,
		primary key(agent_id, mol_id)
		)

	declare @details table(
		agent_id int,
		mol_id int,
		product_id int,
		mfr_number varchar(50),
		unit_id int,
		quantity float,
		plan_q float,
		due_date date,
		price_pure float,
		nds_ratio decimal(5,4),
		index ix (agent_id,mol_id,product_id)
		)

	exec invoices_calc_orders @contents = @buffer

	insert into @details(
		agent_id, mol_id, product_id, mfr_number, unit_id, quantity, plan_q, due_date, nds_ratio, price_pure
		)
	select
		c.supplier_id, c.manager_id, c.item_id, mfr.number, max(u.unit_id), sum(r.plan_q), sum(r.plan_q), min(c.opers_to),
		0.2, min(p.price_pure)
	from mfr_sdocs_contents c 
		join @buffer buf on buf.id = c.content_id
		join (
			select content_id, plan_q = sum(plan_q)
			from supply_r_provides 
			where slice = 'left'
			group by content_id
		) r on r.content_id = c.content_id
		join sdocs mfr on mfr.doc_id = c.mfr_doc_id
		join products_units u on u.name = c.unit_name
		left join @products p on p.product_id = c.item_id
	group by c.supplier_id, c.manager_id, c.item_id, mfr.number

	declare @subject_id int = (
		select top 1 sd.subject_id
		from sdocs_mfr_contents c
			join sdocs sd on sd.doc_id = c.mfr_doc_id
		where content_id in (select id from @buffer)
		)

	if (select count(*) from @details) > 0
	begin		
		insert into sdocs(
			subject_id, type_id, status_id, d_doc, agent_id, mol_id, ccy_id, add_mol_id, add_date
			)
			output inserted.doc_id, inserted.agent_id, inserted.mol_id into @docs
		select 
			@subject_id, 8, 0, @today, agent_id, mol_id, 'RUR', @mol_id, getdate()
		from @details
		group by agent_id, mol_id
		
		print concat('created ', @@rowcount, ' invoices')

		insert into sdocs_products(
			doc_id, mfr_number, product_id, unit_id, quantity, plan_q, due_date, price_pure, nds_ratio
			)
		select
			d.doc_id, x.mfr_number, x.product_id, x.unit_id, x.quantity, x.plan_q, x.due_date, x.price_pure, x.nds_ratio
		from @details x
			join @docs d on d.agent_id = x.agent_id and d.mol_id = x.mol_id

		declare @ids as app_pkids; insert into @ids select doc_id from @docs
		exec invoices_calc_milestones @docs = @ids
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
GO
