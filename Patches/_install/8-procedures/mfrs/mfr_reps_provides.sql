if object_id('mfr_reps_provides') is not null drop proc mfr_reps_provides
go
-- exec mfr_reps_provides 1000, @folder_id = -1, @context = 'docs', @trace = 1
create proc mfr_reps_provides
	@mol_id int,
	@folder_id int = null,
	@context varchar(50) = 'items', -- items, docs, sdocs, stock
	@items_d_from date = null,
	@items_d_to date = null,
	@d_from date = null,
	@d_to date = null,
	@items_name varchar(255) = null,
	@version_id int = null,
	@use_archive bit = 0,
	@trace bit = 0
as
begin
	set nocount on;

	declare @today date = dbo.today()

	-- print '-- params'
		if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

		create table #docs(id int primary key)
		create table #materials(id int primary key)

		if @context = 'items'
        begin
			insert into #materials exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfc'
            if not exists(select 1 from #materials) set @context = null
        end
        else if @context = 'docs'
			insert into #docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'
		else if @context = 'sdocs' begin
            insert into #docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mftrf'
            if exists(select 1 from #docs) 
                set @context = 'mftrf'
            else begin
                insert into #docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'inv'
                if exists(select 1 from #docs)
                    set @context = 'inv'
                else
                    insert into #docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'sd'
            end
            set @use_archive = 1
        end
        
        if @items_d_from is not null and @items_d_to is not null
        begin
            set @context = 'items'
            create table #contents(id int index ix_id)
            
            -- не сделанные детали
            insert into #contents
            select content_id
            from sdocs_mfr_contents c
                join mfr_sdocs mfr on mfr.doc_id = c.mfr_doc_id and mfr.plan_status_id = 1 and mfr.status_id between 0 and 99
            where c.status_id != 100
                and c.is_buy = 0
                and cast(c.opers_from_plan as date) between @items_d_from and @items_d_to

            -- + дочерние детали
            insert into #contents
            select distinct cc.content_id 
            from sdocs_mfr_contents c
                join #contents i on i.id = c.content_id
                join sdocs_mfr_contents cc on cc.mfr_doc_id = c.mfr_doc_id and cc.product_id = c.product_id
                    and cc.node.IsDescendantOf(c.node) = 1
            where cc.is_buy = 0 and cc.status_id != 100

            delete from #materials
            
            -- связанные материалы
            insert into #materials
            select distinct m.content_id
            from sdocs_mfr_contents m
                join sdocs_mfr_contents c on c.mfr_doc_id = m.mfr_doc_id and c.product_id = m.product_id and c.child_id = m.parent_id
                    join #contents cc on cc.id = c.content_id
        end

        else if @d_from is not null and @d_to is not null
        begin
            set @context = 'docs' 
            delete from #docs
            insert into #docs select doc_id from mfr_sdocs where plan_status_id = 1 and status_id >= 0
        end

        if @context is null set @context = 'stock'

		declare @filter_items bit
		create table #items(id int primary key)
		if @items_name is not null
		begin
			set @items_name = '%' + replace(@items_name, ' ', '%') + '%'
			insert into #items select top 1000 product_id from products where name like @items_name			
			set @filter_items = 1
            set @context = null
		end		

		if @version_id is null set @version_id = (select max(version_id) from mfr_r_planfact)
	-- print '-- result'
		create table #result(
			ACC_REGISTER_ID INT,
			CONTENT_ID INT,
			MFR_DOC_ID INT,
			MFR_NUMBER VARCHAR(50),
			DEAL_NUMBER VARCHAR(50),
			D_DELIVERY DATE,
			MFR_PRIORITY INT,
			MFR_STATUS_NAME VARCHAR(30),
			PLACE_ID INT INDEX IX_PLACE,
			D_ISSUE_PLAN DATE,
			AGENT_NAME VARCHAR(255),
			PRODUCT_ID INT,
			PRODUCT_NAME VARCHAR(255),
			PRODUCT_GROUP_NAME VARCHAR(255),
			PRODUCT_SUPPLIER_NAME VARCHAR(255),
			ITEM_ID INT INDEX IX_ITEM_ID,
			ITEM_TYPE_NAME VARCHAR(150),
			ITEM_GROUP1_NAME VARCHAR(255),
			ITEM_GROUP2_NAME VARCHAR(255),
			ITEM_NAME VARCHAR(255),
			IS_MANUAL_PROGRESS BIT,
			STATUS_NAME VARCHAR(30),
			UNIT_NAME VARCHAR(20),
			OPERS_FROM DATE,
			OPERS_TO DATE,
			OPERS_FROM_PLAN DATE,
			OPERS_TO_PLAN DATE,
			D_SHIP DATE,
			D_SHIP_DIFF INT,
			ISSUE_PLAN_WEEK VARCHAR(10),
			ISSUE_PLAN_MONTH VARCHAR(10),
			WEEK_FROM VARCHAR(10),
			WEEK_TO VARCHAR(10),
			WEEK_FROM_PLAN VARCHAR(10),
			WEEK_TO_PLAN VARCHAR(10),
			PRICE FLOAT,
			PRICE_SHIP FLOAT,
			Q_PRODUCT_PLAN FLOAT,
			Q_PRODUCT_FACT FLOAT,
			Q_MFR FLOAT,
			V_MFR FLOAT,
			Q_INVOICE FLOAT,
			V_INVOICE FLOAT,
			Q_SHIP FLOAT,
			V_SHIP FLOAT,
			Q_JOB FLOAT,
			V_JOB FLOAT,
			Q_PROVIDED FLOAT,
			V_PROVIDED FLOAT,
			MFR_DOC_HID VARCHAR(30),
			CONTENT_HID VARCHAR(30),
			INVOICE_HID VARCHAR(30),
			SHIP_HID VARCHAR(30),
			JOB_HID VARCHAR(30),
			XSLICE VARCHAR(20),
			-- 
			INDEX IX_JOIN (ITEM_ID)
			)
    
		declare @query nvarchar(max) = N'
		insert into #result(
			ACC_REGISTER_ID,
			CONTENT_ID,
			mfr_doc_id, mfr_number, deal_number, d_delivery, mfr_priority, mfr_status_name, d_issue_plan,
			agent_name, place_id, 
			product_id, product_name, product_supplier_name,
			item_id, item_type_name, item_name, is_manual_progress,
			status_name,
			opers_from, opers_to, opers_from_plan, opers_to_plan, d_ship,
            week_from, week_to,
			q_mfr, q_invoice, q_ship, q_job, unit_name, price, price_ship,
			xslice, mfr_doc_hid, content_hid, invoice_hid, ship_hid, job_hid
			)
		select
			r.acc_register_id,
			r.id_mfr,
			r.mfr_doc_id,
			sd.number,
			sd.deal_number,
			sd.d_delivery,
			mfr_priority = sd.priority_final,
			mfr_status_name = sdst.name,
			sd.d_issue_plan,
			agent_name = a.name,
			c.place_id,
			pp.product_id,
			product_name = pp.name,
			product_supplier_name = a2.name,
			r.item_id,
            item_type_name = itp.name,
			item_name = p.name,
			c.is_manual_progress,
			status_name = isnull(st.name, ''-''),			
			c.opers_from,
			c.opers_to,
			c.opers_from_plan,
			c.opers_to_plan,
            d_ship = sd2.d_doc,
			week_from = cast(datepart(yyyy, c.opers_from) as varchar(4)) + ''.'' + right(''0'' + cast(datepart(iso_week, c.opers_from) as varchar(2)),2),
			week_to = cast(datepart(yyyy, c.opers_to) as varchar(4)) + ''.'' + right(''0'' + cast(datepart(iso_week, c.opers_to) as varchar(2)),2),
			r.q_mfr,
			r.q_invoice,
			r.q_ship,
			r.q_job,
			r.unit_name,
			r.price,
			price_ship = isnull(nullif(r.price_ship, 0), r.price),
			r.xslice,
			concat(''#'', sd.doc_id),
			concat(''#'', r.id_mfr),
			concat(''#'', r.id_invoice),
			concat(''#'', r.id_ship),
			concat(''#'', r.id_job)
		from ?mfr_r_provides r
			join products p on p.product_id = r.item_id
			left join sdocs_mfr_contents c on c.content_id = r.id_mfr
				left join products pp on pp.product_id = c.product_id
                left join mfr_items_types itp on itp.type_id = c.item_type_id
			left join sdocs sd on sd.doc_id = r.mfr_doc_id
				left join sdocs_statuses sdst on sdst.status_id = sd.status_id
				left join agents a on a.agent_id = sd.agent_id
			left join sdocs sd2 on sd2.doc_id = r.id_ship
				left join agents a2 on a2.agent_id = sd2.agent_id
			left join mfr_items_statuses st on st.status_id = c.status_id
            ?join_docs
		where (@filter_items is null or r.item_id in (select id from #items))
			and (@d_from is null or c.opers_to_plan >= @d_from)
			and (@d_to is null or c.opers_to_plan <= @d_to)
            ?where
		'

		declare @sql_cmd nvarchar(max) = @query
		set @sql_cmd = replace(@sql_cmd, '?mfr_r_provides', 'mfr_r_provides')
        set @sql_cmd = replace(@sql_cmd, '?join_docs',
            case 
                when @context = 'items' then 'join #materials i on i.id = r.id_mfr'
                when @context = 'docs' then 'join #docs i on i.id = r.mfr_doc_id'
                when @context = 'mftrf' then 'join #docs i on i.id = r.id_job'
                when @context = 'inv' then 'join #docs i on i.id = r.id_invoice'
                when @context = 'sdocs' then 'join #docs i on i.id = r.id_ship'
                else ''
            end
            )
        
        if @context = 'stock'
            set @sql_cmd = replace(@sql_cmd, '?where', 'and (r.xslice in (''ship'', ''stock''))')

        set @sql_cmd = replace(@sql_cmd, '?where', '')

        declare @params nvarchar(max) = N'@folder_id int, @context varchar(20), @filter_items bit, @d_from date, @d_to date'
		
        exec sp_executesql @sql_cmd, @params,
			@folder_id, @context, @filter_items, @d_from, @d_to

		if @use_archive = 1
		begin
			set @sql_cmd = @query
			set @sql_cmd = replace(@sql_cmd, '?mfr_r_provides', 'mfr_r_provides_archive')
            set @sql_cmd = replace(@sql_cmd, '?join_docs',
                case 
                    when @context = 'items' then 'join #materials i on i.id = r.id_mfr'
                    when @context = 'docs' then 'join #docs i on i.id = r.mfr_doc_id'
                    when @context = 'mftrf' then 'join #docs i on i.id = r.id_job'
                    when @context = 'inv' then 'join #docs i on i.id = r.id_invoice'
                    when @context = 'sdocs' then 'join #docs i on i.id = r.id_ship'
                    else ''
                end
                )
            set @sql_cmd = replace(@sql_cmd, '?where', ' and (r.archive = 1)')
			exec sp_executesql @sql_cmd, @params,
				@folder_id, @context, @filter_items, @d_from, @d_to
		end

    -- calc diff of version
        create table #docs_diff(mfr_doc_id int primary key, d_issue_plan date, diff int)
            insert into #docs_diff(mfr_doc_id, d_issue_plan, diff)
            select mfr.doc_id, pl.d_doc, datediff(d, mfr.d_issue_plan, pl.d_doc)
            from mfr_sdocs mfr
                join (
                    select distinct mfr_doc_id from #result
                ) d on d.mfr_doc_id = mfr.doc_id
                join (
                    select mfr_doc_id, d_doc = min(d_doc)
                    from mfr_r_plans_rates
                    where version_id = @version_id
                    group by mfr_doc_id
                ) pl on pl.mfr_doc_id = mfr.doc_id

        update r set 
            d_issue_plan = dd.d_issue_plan,
            opers_from_plan = dateadd(d, dd.diff, opers_from_plan),
            opers_to_plan = dateadd(d, dd.diff, opers_to_plan)
        from #result r
            join #docs_diff dd on dd.mfr_doc_id = r.mfr_doc_id

        update #result set 
			issue_plan_month = left(convert(date, d_issue_plan, 104), 7),
			issue_plan_week = cast(datepart(yyyy, d_issue_plan) as varchar(4)) + '.' + right('0' + cast(datepart(iso_week, d_issue_plan) as varchar(2)),2),
            week_from_plan = cast(datepart(yyyy, opers_from_plan) as varchar(4)) + '.' + right('0' + cast(datepart(iso_week, opers_from_plan) as varchar(2)),2),
            week_to_plan = cast(datepart(yyyy, opers_to_plan) as varchar(4)) + '.' + right('0' + cast(datepart(iso_week, opers_to_plan) as varchar(2)),2),
            d_ship_diff = datediff(d, opers_to_plan, d_ship)
	-- print '-- цены'
		update x set
			v_mfr = price * q_mfr,
			v_invoice = isnull(price_ship, price) * q_invoice,
			v_ship = isnull(price_ship, price) * q_ship,
			v_job = isnull(price_ship, price) * q_job,
			q_provided = dbo.maxof(x.q_ship, x.q_job, 0),
			v_provided = dbo.maxof(x.q_ship, x.q_job, 0) * price
		from #result x
	-- print '-- группировка номенклатуры'
        declare @attr_product int = (select top 1 attr_id from prodmeta_attrs where code = dbo.app_registry_varchar('MfrRepProductGroupAttr'))
        declare @attr_group1 int = (select top 1 attr_id from prodmeta_attrs where code = dbo.app_registry_varchar('MfrRepMaterialGroup1Attr'))
        declare @attr_group2 int = (select top 1 attr_id from prodmeta_attrs where code = dbo.app_registry_varchar('MfrRepMaterialGroup2Attr'))
        declare @attr_supplier int = (select top 1 attr_id from prodmeta_attrs where name = 'закупка.КодПоставщика')

        update x set product_group_name = isnull(g.attr_value, '-')
        from #result x
            join products_attrs g on g.attr_id = @attr_product and g.product_id = x.product_id

        update x set item_group1_name = isnull(g.attr_value, '-')
        from #result x
            join products_attrs g on g.attr_id = @attr_group1 and g.product_id = x.item_id

        update x set item_group1_name = isnull(g.attr_value, '-')
        from #result x
            join products_attrs g on g.attr_id = @attr_group1 and g.product_id = x.item_id

        update x set item_group2_name = isnull(g.attr_value, '-')
        from #result x
            join products_attrs g on g.attr_id = @attr_group2 and g.product_id = x.item_id

		update x set product_supplier_name = a.name
		from #result x
			join (
				select product_id, attr_value_number from products_attrs
                where attr_id = @attr_supplier
			) g on g.product_id = x.product_id
        join agents a on a.agent_id = g.attr_value_number
        where x.product_supplier_name is null
    -- select
        if @trace = 1
            select count(*) from #result
        else
            select x.*,
                ACC_REGISTER_NAME = REG.NAME,
                PLACE_NAME = PL.FULL_NAME,
                MANAGER_NAME = PGM.NAME,
                XSLICE_NAME = XS.NAME			
            from #result x
                left join mfr_r_provides_xslices xs on xs.xslice = x.xslice
                left join mfr_places pl on pl.place_id = x.place_id
                left join v_products_managers pgm on pgm.product_id = x.item_id
                left join accounts_registers reg on reg.acc_register_id = x.acc_register_id
	-- final
		exec drop_temp_table '#docs,#contents,#materials,#items,#result,#docs_diff'

end
go
