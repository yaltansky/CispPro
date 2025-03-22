if object_id('mfr_items_create_lzk') is not null drop proc mfr_items_create_lzk
go
-- exec mfr_items_create_lzk 1000, 127
create proc mfr_items_create_lzk
	@mol_id int,
	@subject_id int,
	@d_doc date = null,
	@place_id int = null,
	@place_mol_id int = null,
	@group_by_principal bit = 1,
	@group_by_mfr_number bit = 0,
	@group_by_materials bit = 0,
	@queue_id uniqueidentifier = null,
    @trace bit = 0
as
begin
    set nocount on;

    -- trace start
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids
	declare @zero float = 0.000001
	
	if @queue_id is null
		insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')
	else
		insert into @buffer select obj_id from queues_objs where queue_id = @queue_id and obj_type = 'mfc'

    -- remove locked
        delete x from @buffer x
            join sdocs_mfr_contents c on c.content_id = x.id
        where c.status_id = 10 -- lock status

	create table #details1(
		mfr_doc_id int,
		principal_dogovor_id int,
        product_id int,
		parent_id int,
		content_id int,
		parent_content_id int,
		item_id int,
		item_keeper_id int,
		due_date date,
		place_to_id int,
		unit_id int,
		quantity float,
        primary key (
            content_id,
            principal_dogovor_id
            ),
        index ix_join (mfr_doc_id, product_id, parent_id)
		)

	create table #details2(
		group_id varchar(100),
			acc_register_id int,
            principal_dogovor_id int,
			plan_id int,
			place_to_id int,
			keeper_id int,
		item_id int,
		due_date date,
		mfr_number varchar(100),
		unit_id int,
		quantity float
		)

	set @d_doc = isnull(@d_doc, dbo.today())

	-- provides
		create table #provide(
			content_id int,
            principal_dogovor_id int,
			unit_name varchar(20),
			q_mfr float, q_ship float, q_lzk float, q_job float,
            primary key (
                content_id,
                principal_dogovor_id
                )
			)

		insert into #provide(
            content_id, principal_dogovor_id, unit_name, q_mfr, q_ship, q_lzk, q_job
            )
		select 
			r.id_mfr,
            coalesce(sd1.principal_dogovor_id, sd2.principal_dogovor_id, 0),
			max(r.unit_name),
			sum(q_mfr),
			isnull(sum(r.q_ship), 0),
			isnull(sum(r.q_lzk), 0),
			isnull(sum(r.q_job), 0)
		from mfr_r_provides r
			join @buffer i on i.id = r.id_mfr
			left join sdocs sd1 on sd1.doc_id = r.id_ship
			left join sdocs sd2 on sd2.doc_id = r.id_job
		group by
			r.id_mfr,
            coalesce(sd1.principal_dogovor_id, sd2.principal_dogovor_id, 0)
		having 
            sum(r.q_mfr) > @zero

	-- #details1
		insert into #details1(
            mfr_doc_id, principal_dogovor_id,
            place_to_id, product_id, parent_id, content_id, item_id, due_date, unit_id, quantity
            )
		select
			c.mfr_doc_id, 
            r.principal_dogovor_id,
            c.place_id, c.product_id, c.parent_id, c.content_id, c.item_id, 
			c.opers_from_plan,			
			u.unit_id,
			r.q_ship - (r.q_lzk + r.q_job)
		from #provide r
			join @buffer i on i.id = r.content_id
			join sdocs_mfr_contents c on c.content_id = r.content_id
                join mfr_sdocs mfr on mfr.doc_id = c.mfr_doc_id and mfr.ext_type_id is null
			join products_units u on u.name = r.unit_name
		where (r.q_ship - (r.q_lzk + r.q_job)) > @zero

		exec drop_temp_table '#provide'

		-- bind закупка.КодКладовщика
		declare @attr_keeper int = (select top 1 attr_id from prodmeta_attrs where code = 'закупка.КодКладовщика')

		update x set item_keeper_id = isnull(try_cast(pa.attr_value_id as int), 0)
		from #details1 x
			left join products_attrs pa on pa.attr_id = @attr_keeper and pa.product_id = x.item_id

		-- place_to_id (из первой операции родительской детали)
		update x set place_to_id = o.place_id, parent_content_id = c.content_id
		from #details1 x
			join sdocs_mfr_contents c on c.mfr_doc_id = x.mfr_doc_id and c.product_id = x.product_id and c.child_id = x.parent_id
				left join sdocs_mfr_opers o on o.content_id = c.content_id and o.is_first = 1
		where place_to_id is null

	-- #details2
		insert into #details2(
			group_id, acc_register_id, principal_dogovor_id, plan_id, keeper_id, place_to_id, item_id, mfr_number, unit_id, due_date, quantity
			)
		select 
			group_id, acc_register_id, principal_dogovor_id, plan_id, item_keeper_id, place_to_id, item_id, mfr_number, unit_id, min(due_date), sum(quantity)
		from (
			select 
				group_id = concat(
					mfr.acc_register_id, '-',
                    x.principal_dogovor_id, '-',
					mfr.plan_id, '-',
					case when @group_by_mfr_number = 1 then mfr.number else 'X' end, '-',
					case when @group_by_materials = 1 then item_id else 0 end, '-',
					place_to_id, '-',
					item_keeper_id
					),
				acc_register_id = isnull(mfr.acc_register_id, 0),
                x.principal_dogovor_id,
				mfr.plan_id,
				item_keeper_id,
				place_to_id,
				x.item_id,
				mfr_number = mfr.number,
				unit_id, x.due_date, quantity
			from #details1 x
				join mfr_sdocs mfr on mfr.doc_id = x.mfr_doc_id
			) x
		group by 
			group_id, acc_register_id, principal_dogovor_id, plan_id, item_keeper_id, place_to_id, item_id, mfr_number, unit_id

		if not exists(select 1 from #details2)
		begin
			raiserror('Нет материальной потребности для создания документов "Выдача в производство".', 16, 1)
			return
		end

		if exists(select 1 from #details1 where place_to_id is null)
		begin
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfc'

			-- materials
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'mfc', content_id, @mol_id from #details1 where place_to_id is null
			-- items (parents)
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select distinct @buffer_id, 'mfc', parent_content_id, @mol_id from #details1 where place_to_id is null
				and parent_content_id is not null

			raiserror('Не удалось определить цех-получатель по некоторым позициям (материалы и детали помещены в буфер).', 16, 1)
			return
		end

	BEGIN TRY
	BEGIN TRANSACTION
		
		create table #docs(
			group_id varchar(100) primary key,
			doc_id int, acc_register_id int, principal_dogovor_id int, plan_id int, place_to_id int, keeper_id int
			)
			insert into #docs(group_id, acc_register_id, principal_dogovor_id, plan_id, place_to_id, keeper_id)
			select distinct group_id, acc_register_id, principal_dogovor_id, plan_id, place_to_id, keeper_id
			from #details2

		declare @seed int = isnull((select max(doc_id) from sdocs), 0)
		update x set doc_id = @seed + xx.row_id
		from #docs x
			join (
				select group_id, row_id = row_number() over (order by group_id)
				from #docs					
			) xx on xx.group_id = x.group_id

		-- @place_id
			if @place_id is null
				select top 1 @place_id = place_id
				from sdocs_mfr_opers o
					join @buffer i on i.id = o.content_id
				where o.is_first = 1

		-- sdocs			
			SET IDENTITY_INSERT SDOCS ON;
			
			insert into sdocs(
				ACC_REGISTER_ID, PRINCIPAL_DOGOVOR_ID, PLAN_ID,
				doc_id, type_id, subject_id, d_doc, number,
				status_id, place_id, place_to_id,
				note,
				mol_id, add_date, add_mol_id
				)
			select 
				x.acc_register_id,
                nullif(x.principal_dogovor_id, 0),
				x.plan_id,
				doc_id, 12, @subject_id, @d_doc, 
				concat(s.short_name, '/ЛЗК-', doc_id),
				0, @place_id, place_to_id,
				concat('plan=', p.number, ';'),
				isnull(nullif(keeper_id, 0), @place_mol_id),
				getdate(), @mol_id
			from #docs x
				join subjects s on s.subject_id = @subject_id
				join mfr_plans p on p.plan_id = x.plan_id

			SET IDENTITY_INSERT SDOCS OFF;

		-- sdocs_products
			insert into sdocs_products(doc_id, product_id, mfr_number, due_date, unit_id, plan_q, quantity)
			select d.doc_id, x.item_id, mfr_number, due_date, unit_id, quantity, quantity
			from #details2 x
				join #docs d on d.group_id = x.group_id

        -- read prices
            declare @docs app_pkids; insert into @docs select doc_id from #docs
            exec mfr_docs_trf_readprices @mol_id = @mol_id, @docs = @docs

		-- results
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'MFTRF'
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'MFTRF', doc_id, @mol_id from #docs

        -- lock (temporary)
            update c set status_id = 10
            from sdocs_mfr_contents c
                join @buffer i on i.id = c.content_id

	COMMIT TRANSACTION

		-- recalc		
		if (select count(*) from sdocs_mfr_contents where status_id = 10) > 20
		begin
			declare @items as app_pkids;
                insert into @items
                select distinct item_id from sdocs_mfr_contents
                where status_id = 10;
			exec mfr_provides_calc @mol_id = @mol_id, @items = @items, @queue_id = @queue_id
		end

		exec drop_temp_table '#details1,#details2,#provide,#docs'
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

    -- trace end
        exec tracer_close @tid
end
go
