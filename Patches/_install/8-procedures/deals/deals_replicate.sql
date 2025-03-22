if object_id('deals_replicate') is not null drop procedure deals_replicate
go
-- exec deals_replicate '2019-04-25', '2019-05-31'
-- exec deals_replicate '2018-11-22', '2018-11-22', @subject_id = 7, @number_mask = '%Л18-171%'
create proc deals_replicate
	@date_from datetime = null,
	@date_to datetime = null,
	@subject_id int = 15134,
	@number_mask varchar(30) = null,
	@skip_prepare_deals bit = 0,
	@skip_map_stages bit = 0,
	@is_admin bit = 0,
	@echo bit = 0
as
begin
	
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	if @date_from is null set @date_from = dbo.today() - 1
	if @date_to is null set @date_to = dbo.today()

	if datediff(d, @date_from, @date_to) > 5
		and @is_admin = 0
	begin
		raiserror('Репликация бюджетов сделок за период более 5 дней осуществляется вручную администратором.', 16, 1)
		return
	end

	declare @OBSOLETE bit = case when object_id('tempdb.dbo.#deals') is null then 1 else 0 end

	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @echo

	declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
		' @date_from=', dbo.date2str(@date_from, default),
		' @date_to=', dbo.date2str(@date_to, default),
		' @subject_id=', @subject_id,
		' @number_mask=', @number_mask
		)
	exec tracer_log @tid, @tid_msg

-- Подготовка данных	
	declare @today datetime = dbo.today()
	
	declare @template_id int = 101

	if @OBSOLETE = 1
	begin
		if @skip_prepare_deals = 0 begin
			exec tracer_log @tid, 'prepare_deals'
			exec cf.dbo.prepare_deals @date_from = @date_from, @date_to = @date_to, @subject_id = @subject_id, @with_bs = 1,
				@with_files = 0
		end
	end

-- goto heads?	
	if @OBSOLETE = 0 goto mapColumns

exec tracer_log @tid, 'проверка mappings'

	-- deals_map_instants
	if exists(select 1 from cf..deals_pays
		where InstantID not in (select x.instant_id from deals_map_instants x))
	begin
		select distinct InstantID, InstantName from cf..deals_pays 
			where InstantID not in (select x.instant_id from deals_map_instants x)
		raiserror('Есть строки deals_pays, для которых не указан mapping.<end>', 16, 1)
		return
	end

	-- deals_map_aliases
	if exists(select 1 from cf..deals_expanses
		where AliasID not in (select x.alias_id from deals_map_aliases x))
	begin
		select distinct AliasID, AliasName from cf..deals_expanses
			where AliasID not in (select x.alias_id from deals_map_aliases x)
		raiserror('Есть строки deals_expanses, для которых не указан mapping.<end>', 16, 1)
		return
	end

	-- deals_map_grosses
	if exists(select 1 from cf..deals_costs
		where AccGrossID not in (select x.gross_id from deals_map_grosses x))
	begin
		select distinct AccGrossID, AccGrossName from cf..deals_costs
			where AccGrossID not in (select x.gross_id from deals_map_grosses x)
		raiserror('Есть строки deals_costs, для которых не указан mapping.<end>', 16, 1)
		return
	end

heads: -- шапки сделок
exec tracer_log @tid, 'формирование пула сделок'

	select
		h.subject_id,
		h.DocID,			
			-h.DocID as project_id,
			h.DocID as external_id,
			cast(null as int) as deal_id,
			cast(null as varbinary(32)) as uid,
		h.DocDate as d_doc,
			h.DocNo as number,
		isnull(map_states.status_id, 20) as status_id,
		h.MfrName as place_name,
			cast(null as int) as vendor_id,
		h.BuhPrincipalAgreeID as buh_principal_agree_id,
			h.BuhPrincipalAgreeNo as buh_principal_number,
			h.BuhPrincipalAgreeDate as buh_principal_agree_date,
			h.BuhPrincipalAgreeCommission as buh_principal_agree_commission,
			h.BuhPrincipalSpecNo as buh_principal_spec,
		h.AgreeID as dogovor_id,
			ltrim(rtrim(h.AgreeNo)) as dogovor_number,
			h.AgreeDate as dogovor_date,
			h.AgreeCurrencyTypeID as dogovor_ccy_id,
		h.ApprovalSheetNo as appoval_sheet_number,
			h.ApprovalSheetDate as appoval_sheet_date,
		h.SpecID as spec_id,
			ltrim(rtrim(h.SpecNo)) as spec_number,
			h.SpecDate as spec_date,
		h.CRM_No as crm_number,
			h.CRM_Date as crm_date,
		h.AgentID as customer_id,
			h.AgentName as customer_name,
			h.AgentAddr as customer_city,
			cast(null as varchar(50)) as customer_country,
			cast(h.AgentTypeID as varchar) as customer_type_id,
			h.AgentTypeName as customer_type_name,
		h.AgentDst as consumer_id,
			h.AgentDstName as consumer_name,
		h.CurrencyTypeId as ccy_id,
		cast(0 as decimal(18,2)) as value_ccy,
		h.RateFin as rate_fin,
		h.DeliveryBase as delivery_basis_id,
			h.DeliveryTerm as delivery_basis_note,
			h.DeliveryStart as duration_delivery_from,
			cast(null as varchar(16)) as duration_delivery_from_id,
			h.DeliveryPeriod as duration_delivery,
			h.DeliveryDay as delivery_days_shipping,
			h.MiscTerm as delivery_misc_term,
			h.MfrDay as duration_manufacture,
			h.ReserveDay as duration_reserveshipping,
			h.MountDay as delivery_days_mounting,
		h.DepID as direction_id,
			h.DepName as direction_name,
			cast(null as int) as direction_boss_id,
		cast(null as int) as manager_id,
			h.ManagerName as manager_name,
		cast(null as int) as admin_id,
			h.VerDate as ver_date,
			h.VerNo as ver_number,
		cast(h.Memo as varchar(max)) as note,
		h.ProjectID as eProjectID,
		h.ProjectName as eProjectName
	into #deals
	from cf..deals h
		left join deals_map_states map_states on map_states.State = h.State
	where @number_mask is null or h.DocNo like @number_mask

	alter table #deals add constraint pk_deals primary key (DocID)

mols: -- участники сделки
	select distinct
		h.DocID,
		cast(h.ManagerID as int) as manager_id, -- nullable
		mgr.ManagerName as manager_name,
		h.Kv,
		h.Kc,
		cast(null as varchar(50)) as note
	into #mols
	from cf.dbo.deals_mols h
		join cf.dbo.st_Manager mgr on mgr.ManagerID = h.ManagerID
	where h.DocID in (select DocID from #deals)
		and h.Kv > 0
		and h.Kc > 0
	
		create index ix_mols on #mols(DocId, manager_id)

products: -- товарная часть
	select
		h.DocID,
		h.ExtID,
		h.ProductName as name,
		h.ProductID,
		h.UnitName,
		h.MfrDocList,
		h.Q as quantity,
		h.Pc as price_pure,
		h.PcTrf as price_transfer_pure,
		h.SumPc as value_bdr,
		h.SumTrf as value_transfer_pure,
		cast(null as decimal(5,2)) as nds_ratio,
		cast(null as decimal(18,2)) as value_nds,
		h.SumTotal as value_bds,
		h.SumTrfTotal as value_transfer
	into #products 
	from cf.dbo.deals_products h
	where h.DocID in (select DocID from #deals)

		create index ix_products on #products(DocId, ExtID)

pays: -- условия оплаты покупателем
	select
		h.DocID,
		h.PayNo,
		h.InstantID as instant_id,
		h.InstantName as instant_name,
		cast(null as int) as task_id,
		24 as article_id,
		h.PeriodDay as date_lag,
		h.PortionPercent/100. as ratio,
		cast(0 as decimal(18,2)) as value_bdr,
		cast(0 as decimal(18,2)) as value_nds,
		cast(0 as decimal(18,2)) as value_bds
	into #pays
	from cf..deals_pays h
	where h.DocID in (select DocID from #deals)

		create index ix_pays on #pays(DocId, PayNo)

expenses: -- доп.расходы
	select
		h.DocID,		
		h.AliasID as alias_id,
		h.AliasName as alias_name,
		cast(null as int) as task_id,
		cast(null as int) as article_id,
		h.SumPc as value_bdr,
		cast(null as decimal(5,2)) as nds_ratio,
		cast(null as decimal(18,2)) as value_nds,
		h.SumTotal as value_bds,
		cast(null as varchar(50)) as note
	into #expenses
	from cf.dbo.deals_expanses h
	where h.DocID in (select DocID from #deals)

		create index ix_expenses on #expenses(DocId, alias_id)

costs: -- материалы и работы
	select
		h.DocID,
		h.ExtID,
		h.AccGrossID as gross_id,
		h.AccGrossName as gross_name,
		h.MfrName as mfr_name,
		cast(1 as bit) as is_automap,
		cast(null as int) as task_id,
		cast(null as int) as article_id,
		h.SumPc as value_bdr,		
		cast(null as decimal(5,2)) as nds_ratio,
		cast(null as decimal(18,2)) as value_nds,
		h.SumPcT as value_bds,
		cast(null as varchar(50)) as note
	into #costs
	from cf.dbo.deals_costs h
	where h.DocID in (select DocID from #deals)

		create index ix_costs on #costs(DocId, ExtID, gross_id)

mapColumns:
	exec deals_replicate;2 -- mapping xxx_IDs, calc some props

BEGIN TRY
BEGIN TRANSACTION

exec tracer_log @tid, 'auto creating docs'
	insert into deals_docs(type_id, d_doc, number, external_id)
	select 1, d_doc, number, external_id
	from (
		select d_doc = isnull(dogovor_date,0), number = dogovor_number, external_id = max(dogovor_id)
		from #deals
		group by dogovor_date, dogovor_number
	) x
	where isnull(number, '') <> ''
		and not exists(select 1 from deals_docs where type_id = 1 and d_doc = x.d_doc and number = x.number)

	insert into deals_docs(type_id, d_doc, number, external_id)
	select 2, d_doc, number, external_id
	from (
		select d_doc = isnull(spec_date,0), number = spec_number, external_id = max(spec_id)
		from #deals
		group by spec_date, spec_number
	) x
	where isnull(number, '') <> ''
		and not exists(select 1 from deals_docs where type_id = 2 and d_doc = x.d_doc and number = x.number)

	if @OBSOLETE = 1
	begin
		insert into documents(parent_id, d_doc, number, name, node, tags, refkey, external_id)
		select 
			-2, d_doc, number,
			'Договор комиссии №' + number,
			concat('/1.6/', row_number() over (order by number), '/'),
			'Договор с Принципалом',
			concat('~', row_number() over (order by number)),
			external_id
		from (
			select 
				coalesce(
					d_doc
					, try_parse(
						reverse(substring(reverse(number), 1, charindex('то', reverse(number), 1) -2))
						as datetime using 'Ru-RU'
						)
					, 0
				) as d_doc,
				number, 
				external_id
			from (
				select
					d_doc = buh_principal_agree_date,
					number = buh_principal_number,
					external_id = max(buh_principal_agree_id)
				from #deals
				where isnull(buh_principal_number,'') <> ''
					and buh_principal_agree_id is not null
				group by buh_principal_agree_date, buh_principal_number
				) dd
			) d
		where not exists(select 1 from deals_docs_principals where d_doc = d.d_doc and number = d.number)
	end

	-- map buh_principal_agree_id
	update x set buh_principal_agree_id = xx.document_id
	from #deals x
		left join deals_docs_principals xx on xx.number = x.buh_principal_number

	-- map dogovor_id
	update x set dogovor_id = xx.doc_id
	from #deals x
		left join deals_docs_dogovors xx on xx.d_doc = isnull(x.dogovor_date,0) and xx.number = x.dogovor_number

	-- map spec_id
	update x set spec_id = xx.doc_id
	from #deals x
		left join deals_docs_specs xx on xx.d_doc = isnull(x.spec_date,0) and xx.number = x.spec_number

exec tracer_log @tid, 'creating projects'
	create table #map_projects (DocId int primary key, project_id int, is_new bit)
	create unique index ix_map_projects on #map_projects(project_id)

	SET IDENTITY_INSERT CISP_SHARED..PROJECTS ON
	EXEC SYS_SET_TRIGGERS 0

		-- append
		insert into projects(
			project_id, template_id, type_id, budget_type_id, subject_id, status_id, name, d_from, add_date, number, agent_id, curator_id, chief_id, admin_id, note
			)
			output inserted.template_id, inserted.project_id, 1 into #map_projects
		select 
			project_id, DocID, 
			3, -- type_id
			2, -- budget_type_id
			x.subject_id,
			isnull(x.status_id, 20),
			number + ' ' + x.customer_name,
			isnull(x.spec_date, @today),
			isnull(x.spec_date, @today),
			number, customer_id,
			x.direction_boss_id,
		    x.manager_id,
			x.admin_id,
			note
		from #deals x
		where x.deal_id is null
			and not exists(select 1 from projects where project_id = x.project_id)

	SET IDENTITY_INSERT CISP_SHARED..PROJECTS OFF
	EXEC SYS_SET_TRIGGERS 1

		set @tid_msg = concat(@@rowcount, ' projects inserted')
		exec tracer_log @tid, @tid_msg

		-- update
		update x set number = xx.number
			output 
				case
					when inserted.project_id < 0 then -inserted.project_id
					else inserted.project_id
				end
				, inserted.project_id, 0 
				into #map_projects
		from projects x
			join #deals xx on xx.project_id = x.project_id		
		where not exists(select 1 from #map_projects where DocId = xx.DocID)

		-- mapping
		update x
		set template_id = @template_id
		from projects x
			join #map_projects m on m.project_id = x.project_id

		update x
		set deal_id = m.project_id
		from #deals x
			join #map_projects m on m.DocId = x.DocID

		-- projects_mols
		insert into projects_mols(project_id, name, mol_id, response)
		select distinct u.project_id, mols.name, mols.mol_id, response
		from (
			select project_id, direction_boss_id as mol_id, 'Куратор проекта' as response from #deals
			union select project_id, 261, 'Администратор проекта' from #deals
			union select project_id, 700, null from #deals
			) u
			join mols on mols.mol_id = u.mol_id
		where not exists(select 1 from projects_mols where project_id = u.project_id and mol_id = u.mol_id)

if exists(select 1 from #map_projects where is_new = 1)
begin
exec tracer_log @tid, 'creating projects_tasks'
	create table #map (
		project_id int, source_id int, target_id int,
		constraint pk_map primary key (project_id, source_id)
		)
			
	exec sys_set_triggers 0
		insert into projects_tasks(project_id, template_task_id, parent_id, task_number, name, duration, duration_input, duration_id, predecessors, node, has_childs, outline_level, sort_id)
			output inserted.project_id, inserted.template_task_id, inserted.task_id into #map
		select m.project_id, task_id, parent_id, task_number, name, duration, duration_input, duration_id, predecessors, node, has_childs, outline_level, sort_id
		from projects_tasks as tpl
			join #map_projects m on m.is_new = 1
		where tpl.project_id = @template_id
		order by m.project_id, tpl.node
	exec sys_set_triggers 1

	set @tid_msg = concat(@@rowcount, ' projects tasks inserted')
	exec tracer_log @tid, @tid_msg
	
		-- mapping
		update x
		set parent_id = m.target_id
		from projects_tasks x
			join #map m on m.project_id = x.project_id and m.source_id = x.parent_id
	
		-- links
		insert into projects_tasks_links(project_id, source_id, target_id, type_id)
		select m1.project_id, m1.target_id, m2.target_id, l.type_id
		from projects_tasks_links l			
			join #map m1 on m1.source_id = l.source_id
			join #map m2 on m2.project_id = m1.project_id and m2.source_id = l.target_id
		where l.project_id = @template_id			

	drop table #map

	set @tid_msg = concat(@@rowcount, ' projects tasks links inserted')
	exec tracer_log @tid, @tid_msg

end

exec tracer_log @tid, 'mapping stages'
	if @skip_map_stages = 0	exec deals_replicate;10 @tid

exec tracer_log @tid, 'mapping projects_tasks'
	exec tracer_log @tid, '    #pays.task_id'

	update x
	set task_id = t.task_id
	from #pays x
		join deals_map_instants xx on xx.instant_id = x.instant_id
			join #map_projects p on p.DocId = x.DocID
				join projects_tasks t on t.project_id = p.project_id and t.name = xx.task_name

	if exists(select 1 from #pays where task_id is null)
	begin
		select * from #pays where task_id is null
		raiserror('Не удалось идентифицировать Ганта с графиком платежей (#pays).<end>', 16, 1)
	end
	
	exec tracer_log @tid, '    #expenses.task_id'
	update x
	set task_id = t.task_id,
		article_id = isnull(xx.article_id, 18), -- прочие расходы
		note = case when xx.article_id is null then xx.alias_name end
	from #expenses x
		join deals_map_aliases xx on xx.alias_id = x.alias_id
			join #map_projects p on p.DocId = x.DocID
				join projects_tasks t on t.project_id = p.project_id and t.name = xx.task_name

	exec tracer_log @tid, '    #costs.task_id'
	declare @subj_article_id int
	update x
	set task_id = t.task_id,
		@subj_article_id = 
			case
				when v.subject_id is not null then (
					select top 1 article_id from bdr_articles
					where short_name = a.short_name
						and subject_id = v.subject_id
					)
			end,
		article_id = coalesce(@subj_article_id, a.article_id, 18),
		is_automap = case when @subj_article_id is not null then 0 else 1 end,
		note = case when xx.article_id is null then xx.gross_name end
	from #costs x
		left join subjects v on v.short_name = x.mfr_name
		join deals_map_grosses xx on xx.gross_id = x.gross_id
			left join bdr_articles a on a.article_id = xx.article_id
		join #map_projects p on p.DocId = x.DocID
			join projects_tasks t on t.project_id = p.project_id and t.name = xx.task_name

exec tracer_log @tid, 'creating deals'
	select * into #deleted from deals where deal_id in (select deal_id from #deals)
	delete from deals where deal_id in (select deal_id from #deals)

	insert into deals(
		uid, deal_id, external_id,
		status_id,
		subject_id,
		budget_id,
		program_id,
		--
		d_doc, number, vendor_id, mfr_name,
		--
		buh_principal_number,
		buh_principal_agree_date,
		buh_principal_agree_commission,
		buh_principal_spec,
		--
		dogovor_id,
		dogovor_number,
		dogovor_date,
		dogovor_ccy_id,
		--
		spec_id, spec_number, spec_date,
		--
		appoval_sheet_number, appoval_sheet_date, crm_number, crm_date, 
		customer_id, customer_city, customer_country, customer_type_id, consumer_id, 
		direction_id, manager_id, ccy_id, value_ccy, rate_fin,
		--
		delivery_basis_id,
		delivery_basis_note,
		duration_delivery, delivery_days_shipping, duration_manufacture, duration_reserveshipping, delivery_days_mounting, duration_delivery_from_id,
		delivery_misc_term,
		--
		ver_date, ver_number,
		--
		note,
		--
		eProjectID, eProjectName
		)
	select 
		d.uid, d.deal_id, d.external_id,
		coalesce(dd.status_id, d.status_id, 20),
		d.subject_id,
		dd.budget_id,
		dd.program_id,
		--
		d.d_doc, 
		substring(d.number, 1, 50),
		d.vendor_id,
		d.place_name,
		--
		d.buh_principal_number,
		d.buh_principal_agree_date,
		d.buh_principal_agree_commission,
		d.buh_principal_spec,
		--
		isnull(dd.dogovor_id, d.dogovor_id),
		substring(d.dogovor_number, 1, 50),
		isnull(dd.dogovor_date, d.dogovor_date),
		isnull(dd.dogovor_ccy_id, d.dogovor_ccy_id),
		--
		d.spec_id,
		substring(d.spec_number, 1, 50),
		d.spec_date,
		--
		substring(d.appoval_sheet_number, 1, 50),
		d.appoval_sheet_date,
		substring(d.crm_number, 1, 50),
		d.crm_date,
		--
		d.customer_id,
		substring(d.customer_city, 1, 50),
		substring(d.customer_country, 1, 50),
		isnull(dd.customer_type_id, d.customer_type_id),
		d.consumer_id, 
		--
		isnull(dd.direction_id, d.direction_id),
		isnull(dd.manager_id, d.manager_id),
		--
		d.ccy_id, d.value_ccy, d.rate_fin,
		--
		substring(d.delivery_basis_id, 1, 16),
		substring(d.delivery_basis_note, 1, 50),
		d.duration_delivery, d.delivery_days_shipping, d.duration_manufacture, d.duration_reserveshipping, d.delivery_days_mounting, d.duration_delivery_from_id,
		d.delivery_misc_term,
		--
		d.ver_date, d.ver_number,
		--
		d.note,
		d.eProjectID, d.eProjectName
	from #deals d
		left join #deleted dd on dd.deal_id = d.deal_id

	set @tid_msg = concat(@@rowcount, ' deals inserted')
	exec tracer_log @tid, @tid_msg
	
	drop table #deleted

exec tracer_log @tid, 'deals_mols'
	insert into deals_mols(deal_id, mol_id, kv, kc, note)
	select xd.deal_id, x.manager_id, x.Kv, x.Kc, x.note
	from #mols x
		join #deals xd on xd.DocID = x.DocID

exec tracer_log @tid, 'deals_products'
	insert into deals_products(
		deal_id, row_id, name, 
		eProductID, eUnitName, eMfrDocList,
		quantity, price_pure, price_transfer_pure, value_bdr, value_transfer_pure, nds_ratio, value_nds, value_bds, value_transfer
		)
	select 
		xx.deal_id, x.extid, name,
		x.ProductID, x.UnitName, x.MfrDocList,
		quantity, price_pure, price_transfer_pure, value_bdr, value_transfer_pure, nds_ratio, value_nds, value_bds, value_transfer
	from #products x
		join #deals xx on xx.DocID = x.DocID

exec tracer_log @tid, 'deals_costs'
	insert into deals_costs(deal_id, task_id, article_id, deal_product_id, deal_product_name, value_bdr, nds_ratio, value_nds, value_bds, note, is_automap)
	select xx.deal_id, x.task_id, x.article_id, x.extid, pr.name, x.value_bdr, x.nds_ratio, x.value_nds, x.value_bds, x.note, x.is_automap
	from #costs x
		join #deals xx on xx.DocID = x.DocID
		join #products pr on pr.DocID = x.DocID and pr.extid = x.extid

exec tracer_log @tid, 'deals_budgets'
	-- #pays
	insert into deals_budgets(deal_id, type_id,  task_id, date_lag, article_id, ratio, value_bdr, value_nds, value_bds)
	select xx.deal_id, 1, task_id, date_lag, article_id, ratio, value_bdr, value_nds, value_bds
	from #pays x
		join #deals xx on xx.DocID = x.DocID

	-- #costs
	insert into deals_budgets(deal_id, type_id, task_id, article_id, value_bdr, value_nds, value_bds)
	select xx.deal_id, 2, task_id, article_id, sum(value_bdr), sum(value_nds), sum(value_bds)
	from #costs x
		join #deals xx on xx.DocID = x.DocID
	group by xx.deal_id, task_id, article_id
		
	-- #expenses
	insert into deals_budgets(deal_id, type_id, task_id, article_id, value_bdr, nds_ratio, value_nds, value_bds, note)
	select xx.deal_id, 3, task_id, article_id, value_bdr, x.nds_ratio, value_nds, value_bds, x.note
	from #expenses x
		join #deals xx on xx.DocID = x.DocID
		
	-- task_name
	update x set task_name = t.name
	from deals_budgets x
		join #deals xx on xx.deal_id = x.deal_id
		join projects_tasks t on t.task_id = x.task_id

exec tracer_log @tid, 'recalc deals'
	declare @deal_ids as app_pkids
	insert into @deal_ids select deal_id from #deals
	exec deal_calc @mol_id = -25, @ids = @deal_ids, @tid = @tid

-- map budget_id
	update x
	set budget_id = b.budget_id
	from deals x
		join budgets b on b.project_id = x.deal_id
	where x.budget_id is null

exec tracer_log @tid, 'auto-create budgets'
	exec deals_replicate;20 @tid = @tid

-- deals_files
	if object_id('deals_files') is not null
	begin
		delete from deals_files where deal_id in (select deal_id from #deals)

		insert into deals_files(
			deal_id, deal_doc_id, add_date, name, file_type, file_data, update_date
			)
		select 
			d.deal_id, f.DocID, f.FileRowDate, f.FileRowName, f.FileType, f.FileData, f.DateUpd
		from cf.dbo.deals_files f
			join #deals d on d.DocID = f.DocID
	end

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	exec sys_set_triggers 1
	declare @err varchar(max) = error_message()
	raiserror (@err, 16, 1)
END CATCH

-- clear
	if @OBSOLETE = 1
	begin
		if object_id('tempdb.dbo.#deals') is not null drop table #deals
		if object_id('tempdb.dbo.#mols') is not null drop table #mols
		if object_id('tempdb.dbo.#pays') is not null drop table #pays
		if object_id('tempdb.dbo.#products') is not null drop table #products
		if object_id('tempdb.dbo.#costs') is not null drop table #costs
		if object_id('tempdb.dbo.#expenses') is not null drop table #expenses
	end

	if object_id('tempdb.dbo.#map_projects') is not null drop table #map_projects

-- close log
	exec tracer_close @tid
	-- exec tracer_view @tid

end
go
-- mapping xxx_IDs, calc some props
create proc deals_replicate;2--
as
begin

	declare @admin_id int = 700 -- ' Васильев Д.А.
	
	declare @map_managers table(manager_name varchar(50), new_manager_name varchar(50))
	insert into @map_managers values
		('Князева Ю.В. (Павлова Ю.В.)', 'Князева Ю.В.'),
		('Суркова Т.А.(Харитонова Т.А.)', 'Суркова Т.А.'),
		('Дмитриевский Д.Л.', 'Васильев Д.А.')

-- #deals
	update #deals set admin_id = @admin_id

	-- map existed deals
	update x
	set project_id = xx.deal_id,
		deal_id = xx.deal_id,
		status_id = isnull(x.status_id, p.status_id)
	from #deals x
		join deals xx on isnull(xx.external_id, xx.uid) = isnull(x.external_id, x.uid)
			left join projects p on p.project_id = xx.deal_id

	update x
	set direction_boss_id = isnull(m_dep.mol_id, 700),
		manager_id = mgr.ManagerID,
		manager_name = isnull(map_m.new_manager_name, x.manager_name)
	from #deals x
		join cf..st_Department dep on dep.DepName = x.direction_name
			left join (
				select name, max(mol_id) as mol_id
				from mols
				group by name
			) m_dep on m_dep.name = dep.DepBoss
		left join cf.dbo.st_Manager mgr on mgr.ManagerID = x.manager_id
			left join @map_managers map_m on map_m.manager_name = mgr.ManagerName

	-- vendor_id
	update x
	set vendor_id = isnull(xx.subject_id, -12),
		note = concat(x.note,
			case 
				when xx.subject_id is null then concat(case when x.note is null then '' else ' ,' end, 'площадка=', x.place_name) 
				else '' end
			)
	from #deals x
		left join subjects xx on xx.name = x.place_name or isnull(xx.short_name, '') = isnull(x.place_name, '')

	-- #agents
	insert into agents(name, name_print)
	select distinct name, name
	from (
		select customer_name as name from #deals
		union select consumer_name from #deals
		) u
	where name is not null
		and not exists(select 1 from agents where name = u.name)

	-- customer_id
	update x
	set customer_id = a.agent_id
	from #deals x
		join agents a on a.name = x.customer_name

	-- consumer_id
	update x
	set consumer_id = a.agent_id
	from #deals x
		join agents a on a.name = x.consumer_name

	-- customer_type_id
	insert into options_lists(l_group, id, name)
	select distinct 'DealMarketing', 'DealMark' + customer_type_id, customer_type_name from #deals
	where customer_type_id is not null
		and customer_type_name not in (select name from options_lists where l_group = 'DealMarketing')

	update x
	set customer_type_id = xx.id,
		note = isnull(x.note,'') + case when xx.id is null then ', тип покупателя=' + x.customer_type_name else '' end
	from #deals x
		left join options_lists xx on xx.l_group = 'DealMarketing' and xx.name = x.customer_type_name
	
	-- duration_delivery_from_id
	update x
	set duration_delivery_from_id = xx.id
	from #deals x
		left join options_lists xx on xx.l_group = 'DeliveryFrom' and xx.name = x.duration_delivery_from

	update x
	set direction_id = xx.dept_id
	from #deals x
		join deals_map_directions xx on xx.depid = x.direction_id

	-- manager_id
	update x
	set manager_id = isnull(xx.mol_id, 700),
		note = concat(
			x.note, 
			case when isnull(x.note,0) = '' then '' else ', ' end,
			case when xx.mol_id is null then 'менеджер=' + x.manager_name + ', ' else '' end
			)
	from #deals x
		left join mols xx on xx.name = replace(x.manager_name, '. ', '.')

-- #mols
	if object_id('tempdb.dbo.#mols') is not null
	begin
		-- defaults
		insert into #mols(DocID, manager_id, manager_name, Kv, Kc)
		select x.DocID, x.manager_id, x.manager_name, 1, 1
		from #deals x
		where not exists(select 1 from #mols where DocId = x.DocID)

		-- manager_id
		update x
		set manager_id = xx.mol_id,
			note = case when xx.mol_id is null then x.manager_name end
		from #mols x
			left join mols xx on xx.name = x.manager_name
	end

	declare @value_nds decimal(18,2)

-- #products
	if object_id('tempdb.dbo.#products') is not null
	begin	
		update #products
		set @value_nds = value_bds - value_bdr,
			nds_ratio = @value_nds / nullif(value_bdr,0),
			value_nds = @value_nds
		
		-- value_ccy
		update x
		set value_ccy = (select sum(value_bds) from #products where DocID = x.DocID)
		from #deals x
	end

-- #pays
	if object_id('tempdb.dbo.#pays') is not null
	begin
		update x
		set instant_id = m.instant_id
		from #pays x
			join deals_map_instants m on m.instant_name = x.instant_name

		-- value_bdr, value_nds, value_bds
		declare @nds_ratio decimal(18,2), @value_bdr decimal(18,2), @value_bds decimal(18,2)

		update x
		set @nds_ratio = (select max(nds_ratio) from #products where DocID = x.DocID),		
			@value_bds = x.ratio * xx.value_ccy,
			@value_bdr = @value_bds / ( 1 + @nds_ratio),
			value_bdr = @value_bdr,
			value_nds = @value_bds - @value_bdr,
			value_bds = @value_bds
		from #pays x
			join #deals xx on xx.DocID = x.DocID
	end

-- #expenses
	if object_id('tempdb.dbo.#expenses') is not null
	begin
		update #expenses
		set @value_nds = value_bds - value_bdr,
			nds_ratio = isnull(@value_nds / nullif(value_bdr,0), 0),
			value_nds = @value_nds

		update x
		set alias_id = m.alias_id,
			article_id = m.article_id
		from #expenses x
			join deals_map_aliases m on m.alias_name = x.alias_name
	end

-- #cost
	if object_id('tempdb.dbo.#costs') is not null
	begin
		update #costs
		set @value_nds = value_bds - value_bdr,
			nds_ratio = isnull(@value_nds / nullif(value_bdr,0), 0),
			value_nds = @value_nds

		update x
		set gross_id = m.gross_id
		from #costs x
			join deals_map_grosses m on m.gross_name = x.gross_name
	end

-- dogovor_number

end
go
-- mapping stages
create proc deals_replicate;10
	@tid int
as
begin

	declare @d_from datetime, @d_to datetime
	declare @today datetime = dbo.today()

exec tracer_log @tid, '    set duration'
	declare @duration int
	update x
	set @duration = 
			isnull(
				nullif(
					case
						when meta.option_key = 'duration_manufacture' then d.duration_manufacture
						when meta.option_key = 'delivery_days_shipping' then d.delivery_days_shipping
					end
				, 0)					 
			, 1),
		duration = @duration,
		duration_input = @duration,
		duration_id = 3
	from projects_tasks x
		join #deals d on d.deal_id = x.project_id
		join deals_meta_tasks meta on meta.task_name = x.name

exec tracer_log @tid, '    #stages'
	select
		row_number() over (order by h.DocId, h.StageId) as row_id,
		h.DocID,
		h.StageId,
		h.StageDate as d_from,
		cast(null as datetime) as d_to,
		s.StageName
	into #stages
	from cf..doc_BomAgreeS h
		join #deals x on x.DocID = h.DocID
		join cf..doc_BomAgree_Stage s on s.StageID = h.StageID
	
		create unique index ix_stages on #stages(row_id)

	update x
	set d_to = n.d_from - 1
	from #stages x
		join (
			select 
				row_id,
				d_from = lead(d_from, 1, null) over (partition by DocId order by row_id)
			from #stages
		) n on n.row_id = x.row_id

exec tracer_log @tid, '    deals_map_stages'
	declare c_stages cursor local read_only for select stage_id, task_name from deals_map_stages
	declare @stage_id int, @task_name varchar(64)
	
	open c_stages; fetch next from c_stages into @stage_id, @task_name
		while (@@fetch_status <> -1)
		begin
			if (@@fetch_status <> -2)
			begin			
				update x
				set @d_from = s.d_from,
					@d_to = dbo.work_day_add(@d_from, duration),
					d_from = @d_from, d_from_fact = @d_from,
					d_to = @d_to, d_to_fact = @d_to,
					progress = 1
				from projects_tasks x
					join #deals d on d.deal_id = x.project_id
						join #stages s on s.DocID = d.DocId and s.StageId = @stage_id
				where x.name = @task_name
			end
			--
			fetch next from c_stages into @stage_id, @task_name
		end
	close c_stages; deallocate c_stages

exec tracer_log @tid, '    Доставка'
	-- "Доставка": начало = окончание "Отгрузка", окончание = начало + длительность
	update x
	set @d_from = x2.d_to + 1,
		@d_to = dateadd(d, x.duration, x2.d_to + 1),
		d_from = @d_from, d_from_fact = @d_from,
		d_to = @d_to, d_to_fact = @d_to,
		progress = case when x2.d_from is not null then 1 else 0 end
	from projects_tasks x
		join #deals d on d.deal_id = x.project_id
		join projects_tasks x2 on x2.project_id = x.project_id and x2.name = 'Отгрузка' and x2.d_from is not null
	where x.name = 'Доставка'

exec tracer_log @tid, '    Пусконаладка'
-- "Пусконаладка" (если нет стадии): начало = "Акт выполненных работ", окончание = начало
	update x
	set @d_from = x2.d_from,
		@d_to = x2.d_from + 1,
		d_from = @d_from, d_from_fact = @d_from,
		d_to = @d_to, d_to_fact = @d_to,
		progress = case when x2.d_from is not null then 1 else 0 end
	from projects_tasks x
		join #deals d on d.deal_id = x.project_id
			left join #stages s on s.DocID = d.DocID and s.StageID = 7
		join projects_tasks x2 on x2.project_id = x.project_id and x2.name = 'Акт выполненных работ' and x2.d_from is not null
	where x.name = 'Пусконаладка'
		and s.d_from is null -- если нет стадии 'CE. Шеф-монтаж'

exec tracer_log @tid, '    tasks queue'
	declare c_list cursor local read_only for 
		select task_number from projects_tasks 
		where project_id = (select top 1 deal_id from #deals) and has_childs = 0
		order by task_number desc

	declare @task_number int, @prev_number int
	
	open c_list; fetch next from c_list into @task_number
		while (@@fetch_status <> -1)
		begin
			if (@@fetch_status <> -2) and @prev_number is not null
			begin
				update x
				set @d_from = x2.d_from - 1,
					@d_to  = @d_from,
					d_from = @d_from, d_from_fact = @d_from,
					d_to = @d_to, d_to_fact = @d_to,
						duration = 0, duration_input = 0,
					progress = 1
				from projects_tasks x
					join #deals d on d.deal_id = x.project_id
					join projects_tasks x2 on x2.project_id = x.project_id and x2.task_number = @prev_number and x2.progress = 1
				where x.task_number = @task_number
					and x.progress = 0
			end
			--
			set @prev_number = @task_number
			fetch next from c_list into @task_number
		end
	close c_list; deallocate c_list

exec tracer_log @tid, '    Финансирование материалов и работ'
	-- "Финансирование материалов и работ": после "Запуск" (если он 100%)
	update x
	set @d_from = x2.d_to + 1,
		@d_to = dbo.work_day_add(@d_from, x.duration),
		d_from = @d_from, d_from_fact = @d_from,
		d_to = @d_to, d_to_fact = @d_to,
		progress = x2.progress
	from projects_tasks x
		join #deals d on d.deal_id = x.project_id
		join projects_tasks x2 on x2.project_id = x.project_id and x2.name = 'Запуск' and x2.d_from is not null
	where x.name = 'Финансирование материалов и работ'

exec tracer_log @tid, '    Дополнительные расходы'
	-- "Дополнительные расходы": после "Изготовление" (если он 100%)
	update x
	set @d_from = x2.d_to + 1,
		@d_to = dbo.work_day_add(@d_from, x.duration),
		d_from = @d_from, d_from_fact = @d_from,
		d_to = @d_to, d_to_fact = @d_to,
		progress = x2.progress
	from projects_tasks x
		join #deals d on d.deal_id = x.project_id
		join projects_tasks x2 on x2.project_id = x.project_id and x2.name = 'Изготовление' and x2.d_from is not null
	where x.name = 'Дополнительные расходы'

exec tracer_log @tid, '    Окончательный расчет'
	-- "Окончательный расчет": после 'Финансирование материалов и работ', 'Дополнительные расходы'
	update x
	set @d_from = x2.d_to + 1,
		@d_to = dbo.work_day_add(@d_from, x.duration),
		d_from = @d_from, d_from_fact = @d_from,
		d_to = @d_to, d_to_fact = @d_to,
		progress = case when @d_to is not null then 1 else 0 end
	from projects_tasks x
		join #deals d on d.deal_id = x.project_id
		join (
			select project_id, max(d_to) as d_to
			from projects_tasks
			where name in ('Акт выполненных работ')
			group by project_id
		) x2 on x2.project_id = x.project_id and x2.d_to is not null
	where x.name = 'Окончательный расчет'

exec tracer_log @tid, '    Корректировка % на текущую дату'
	update x
	set @d_from = case when d_from < @today then d_from end,
		@d_to = case when d_to < @today then d_to end,
		d_from = @d_from, d_from_fact = @d_from,
		progress =
			case 
				when @d_from is not null and @d_to is null then datediff(d, @d_from, @today) / nullif(duration, 0)
				when @d_to is not null then 1
				else 0
			end
	from projects_tasks x
		join #deals d on d.deal_id = x.project_id

exec tracer_log @tid, '    Суммарные задачи'
	update x
	set @d_from = xx.d_from,
		@d_to = xx.d_to,
		d_from = @d_from, d_from_fact = @d_from,
		d_to = @d_to, d_to_fact = @d_to,
		progress = xx.progress
	from projects_tasks x		
		join (
			select 
				t.project_id, t.parent_id, 
				min(t.d_from) as d_from,
				max(t.d_to) as d_to,
			    sum(tt.duration) / nullif(sum(t.duration),0) as progress
			from projects_tasks t
				left join (
					select project_id, parent_id, sum(duration) as duration
					from projects_tasks 
					where progress = 1	
					group by project_id, parent_id
				) tt on tt.project_id = t.project_id and tt.parent_id = t.parent_id
			group by t.project_id, t.parent_id
		) xx on xx.project_id = x.project_id and xx.parent_id = x.task_id
	where x.has_childs = 1
		and x.project_id in (select deal_id from #deals)

end
go
-- авто-создание бюджетов [+ классификация приходов по бюджетам]
create proc deals_replicate;20
	@tid int = 0
as
begin

	set nocount on;

	declare @tid_msg varchar(max)	

	if not exists(
		select 1 from deals 
		where deal_id in (select deal_id from #deals)
			and budget_id is null
		)
	begin
		return -- nothing todo
	end

	SET IDENTITY_INSERT CISP_SHARED..BUDGETS ON
		-- convention: budget_id = project_id = deal_id
		insert into budgets(budget_id, type_id, name, project_id, mol_id)
		select deal_id, 3, number, deal_id, manager_id
		from #deals x
		where not exists(select 1 from budgets where budget_id = x.deal_id)
	SET IDENTITY_INSERT CISP_SHARED..BUDGETS OFF

set @tid_msg = concat(@@rowcount, ' budgets inserted') 
exec tracer_log @tid, @tid_msg

exec tracer_log @tid, 'call budgets_by_vendors_calc'
	update x
	set budget_id = b.budget_id
	from deals x
		join budgets b on b.project_id = x.deal_id
		join #deals xd on xd.deal_id = x.deal_id

	exec budgets_by_vendors_calc @news_only = 1
	exec deals_calc
	
end
go
