-- dbcontext: CISP_KCL | CISP_IVA | CISP_SNRG
	if db_name() not in ('CISP_KCL', 'CISP_IVA', 'CISP_SNRG')
		begin
			raiserror('This procedure is implemented only in CISP_SEZ', 16, 1)
			return
		end
		if object_id('mfr_replicate') is not null drop proc mfr_replicate
go
create proc mfr_replicate
	@mol_id int,
	@doc_id int = null,
    @docs app_pkids readonly,
	@channel varchar(50) = null,
	@trace bit = 0
as
begin
	declare @call_docs app_pkids

    if @doc_id is not null insert into @call_docs select @doc_id
    else insert into @call_docs select id from @docs

    if not exists(select 1 from @call_docs)
	begin
		declare @sql_cmd nvarchar(max) = concat('exec mfr_replicate;10 @mol_id = ', @mol_id,
			', @trace = 1', 
			case when @channel is not null then ', @channel = ''' + @channel + '''' end
			)
		exec queue_append @thread_id = 'mfrs', @group_name = 'replication', @name = 'Репликация заказов',
			@sql_cmd = @sql_cmd, @use_buffer = 0
	end

	else
		exec mfr_replicate;10 @mol_id = @mol_id, @docs = @call_docs, @channel = @channel, @trace = @trace
end
go
create proc mfr_replicate;10
	@mol_id int,
	@docs app_pkids readonly,
	@channel varchar(50) = null,
	@trace bit = 0
as
begin
	set nocount on;

    -- params
        declare @subjectId int = cast(dbo.app_registry_value('MfrReplSubjectId') as int)
        declare @branchName varchar(10) = dbo.app_registry_varchar('MfrReplProductsBranchName')
        declare @channelOrders varchar(30) = dbo.app_registry_varchar('MfrReplChannelOrders')
        declare @channelContents varchar(30) = dbo.app_registry_varchar('MfrReplChannelContents')

		declare @type varchar(30)
		declare @date_start datetime = getdate()	
		declare @today datetime = dbo.today()

		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

		declare @tid_msg varchar(max) = concat(@proc_name, '.params:',
			'@channel=', @channel
			)
		exec tracer_log @tid, @tid_msg		
	-- imports contents by docs
		if @channel = 'ImportContents'
		begin
			if (select count(*) from @docs) > 100
			begin
				raiserror('Можно обновлять не более 10 заказов. Повторите операцию.', 16, 1)
				return
			end

			declare @numbers varchar(max) = (
				select number + ','  [text()] 
				from mfr_sdocs where doc_id in (select id from @docs)
				for xml path('')
				)
			set @numbers = substring(@numbers, 1, len(@numbers) - 1)

			if @numbers is null
			begin
				raiserror('Нет заказов для обновления. Скорее всего, по указанным заказам обновление запрещено.', 16, 1)
			end
			else begin
				update sdocs set status_id = 3 -- Обновление
				where doc_id in (select id from @docs)

                declare @sql_cmd nvarchar(max) = concat('exec ', db_name(), '..mfr_replicate @mol_id = 1000, @channel = "', @channelContents, '", @trace = 1')

				exec cisp_gate..cisp_sdocs_mfr_contents_prepare
					@branch_name = @branchName,
					@numbers = @numbers,
					@sql_cmd = @sql_cmd
			end
			return
		end
	-- auto-create mfr_plans
		if not exists(select 1 from mfr_plans)
		begin
			set identity_insert mfr_plans on;			
			insert into mfr_plans(subject_id, plan_id, number, status_id) values(@subjectId, 1, 'Производственный план', 1)
			set identity_insert mfr_plans off;
		end
	-- tables
		create table #sdocs(
			DocId VARCHAR(100),
			DOC_ID INT,		
			EXTERN_ID VARCHAR(50) PRIMARY KEY,
			PLAN_ID INT,
			PRIORITY_ID INT,
			SUBJECT_ID INT,
			TYPE_ID INT,
			STATUS_ID INT,
			STOCK_ID INT,
			STOCK_NAME VARCHAR(50),
			D_DOC DATE,
			D_DELIVERY DATE,
			D_SHIP DATE,
			D_ISSUE_PLAN DATE,
			D_ISSUE DATE,
			NUMBER VARCHAR(50),
			AGENT_ID INT,
			AGENT_NAME VARCHAR(250),
			NOTE VARCHAR(MAX)		
			)
			create unique index ix_docid on #sdocs(DocId)

		create table #sdocs_products(
			EXTERN_DOC_ID VARCHAR(50) INDEX IX_EXTERN,
			EXTERN_PRODUCT_ID VARCHAR(32),
			PRODUCT_ID INT,
			PRODUCT_NAME VARCHAR(500),
			UNIT_ID INT,
			UNIT_NAME VARCHAR(20),
			QUANTITY FLOAT,
			D_PLAN DATE,
			PRICE FLOAT,
			PRICE_PURE FLOAT,
			PRICE_PURE_TRF FLOAT,
			PRICE_LIST FLOAT,
			NDS_RATIO DECIMAL(18,4),
			VALUE_PURE DECIMAL(18,2),
			VALUE_NDS DECIMAL(18,2),
			VALUE_CCY DECIMAL(18,2),
			VALUE_RUR DECIMAL(18,2),
			VALUE_TRF_PURE DECIMAL(18,2),
			VALUE_TRF DECIMAL(18,2),
			VALUE_WORK DECIMAL(18,2),
			NOTE VARCHAR(MAX),
			INDEX IX_PRODUCT (EXTERN_DOC_ID, EXTERN_PRODUCT_ID)
			)
		create table #sdocs_contents(
			ROW_ID INT IDENTITY PRIMARY KEY,
			MFR_DOC_ID INT,
			PRODUCT_ID INT,
			CONTENT_ID INT INDEX IX_CONTENT,
			EXTERN_ID VARCHAR(32) INDEX IX_EXTERN,		
			EXTERN_DOC_ID VARCHAR(50) INDEX IX_EXTERN_DOC,
			EXTERN_PRODUCT_ID VARCHAR(32),
			PRODUCT_NAME VARCHAR(500),
			--
			PLACE_ID INT,
			EXTERN_ITEM_ID VARCHAR(32),			
			ITEM_ID INT,
			ITEM_TYPE_ID INT,
			ITEM_NAME VARCHAR(500),
			ITEM_STATUS_ID INT,
			ITEM_NUMPOS INT,
			UNIT_NAME VARCHAR(20),
			Q_NETTO FLOAT,
			Q_BRUTTO FLOAT,
			W_NETTO FLOAT,
			W_BRUTTO FLOAT,
			ITEM_PRICE0 DECIMAL(18,2),
			ITEM_VALUE0 DECIMAL(18,2),
			IS_BUY BIT,
			HAS_CHILDS BIT,
			--
			PARENT_ID VARCHAR(255),
			CHILD_ID VARCHAR(255),
			NAME VARCHAR(500),
			UPDATE_DATE DATETIME,
			--
			INDEX IX_NODES1 (MFR_DOC_ID, PARENT_ID),
			INDEX IX_NODES2 (MFR_DOC_ID, CHILD_ID),
			INDEX IX_NODES3 (MFR_DOC_ID, PRODUCT_ID, ITEM_ID)
			)
		create table #sdocs_contents_attrs(
			ROW_ID INT IDENTITY PRIMARY KEY,
			EXTERN_DOC_ID VARCHAR(50) INDEX IX_EXTERN_DOC,
			CHILD_ID VARCHAR(255),
			ATTR_ID INT,
			ATTR_NAME VARCHAR(150),
			ATTR_VALUE VARCHAR(MAX),
			--
			INDEX IX_ATTRS (EXTERN_DOC_ID, CHILD_ID)
			)
		create table #sdocs_opers(
			OPER_ID INT,
			EXTERN_DOC_ID VARCHAR(50),
			EXTERN_PRODUCT_ID VARCHAR(32),
			PRODUCT_ID INT,
			CHILD_ID VARCHAR(255),
			--
			TYPE_ID INT,
			NUMBER INT,
			OPERKEY VARCHAR(10),
			EXTERN_ID VARCHAR(50),
			NAME VARCHAR(100),
			PLACE_ID INT,
			PLACE_NAME VARCHAR(150),
			DURATION FLOAT,
			DURATION_ID INT,
			DURATION_WK FLOAT,
			DURATION_WK_ID INT,
			RESOURCE_EXTERN_ID VARCHAR(32),
			RESOURCE_ID INT,
			RESOURCE_NAME VARCHAR(255),
			RESOURCE_LOADING FLOAT,
			POST_EXTERN_ID VARCHAR(32),
			POST_ID INT,
			POST_NAME VARCHAR(255),
			RATE_PRICE FLOAT,
			--
			INDEX IX_CHILD (EXTERN_DOC_ID, CHILD_ID),
			)
	-- packages
		exec tracer_log @tid, 'prepare packs info'

		declare @filterDocs table(DocId varchar(100) primary key)
		declare @packagesDocs table(PackId int primary key)
		declare @packagesContents table(PackId int primary key)
		declare @packages table(PackId int primary key)
		declare @docsOfPackages table(DocId varchar(100) primary key, PackId int, index ix (PackId, DocId))
		declare @package table(PackId int, DocId varchar(100), primary key (PackId, DocId))

		-- @filterDocs
			insert into @filterDocs
			select distinct d.DocId from cisp_gate..doc_mfr d with(nolock)
				join (
					select packid from cisp_gate..packs with(nolock) where ChannelName = @channelOrders
				) p on p.PackId = d.PackId
				join (
					select DocId = substring(extern_id, 3, 50) from sdocs where doc_id in (select id from @docs)
				) dd on dd.DocId = d.DocId

		if exists(select 1 from @docs)
			set @type = 'lastContents'

		-- @packagesDocs
			if isnull(@type, 'packs') = 'packs' and isnull(@channel,@channelOrders) = @channelOrders
				insert into @packagesDocs select PackId
				from cisp_gate..packs with(nolock)
				where ChannelName = @channelOrders and ProcessedOn is null

		-- @packagesContents
			if isnull(@type, 'packs') = 'packs' and isnull(@channel,@channelContents) = @channelContents
				insert into @packagesContents select PackId
				from cisp_gate..packs with(nolock)
				where ChannelName = @channelContents and ProcessedOn is null
			else if @type = 'lastContents'
				insert into @packagesContents
				select distinct PackId from (
					select c.DocId, PackId = max(PackId)
					from cisp_gate..doc_mfr_contents c with(nolock)
						join @filterDocs f on f.DocId = c.DocId
					group by c.DocId
				) x

		-- @packages
			insert into @packages
			select PackId from cisp_gate..packs with(nolock)
			where PackId in (
				select PackId from @packagesDocs
				union select PackId from @packagesContents
				)
		
		-- @docsOfPackages
			insert into @docsOfPackages(DocId, PackId)
			select DocId, PackId = max(PackId)
			from cisp_gate..doc_mfr with(nolock)
			where PackId in (select PackId from @packagesDocs)
				or DocId in (
					select distinct DocId
					from cisp_gate..doc_mfr_contents with(nolock)
					where PackId in (select PackId from @packagesContents)
					)
			group by DocId

		if exists(select 1 from @filterDocs)
			delete x from @docsOfPackages x where not exists(select 1 from @filterDocs where DocId = x.DocId)

		-- /**DEBUG**/
		-- DELETE FROM @DOCSOFPACKAGES WHERE DOCID NOT IN ('65878', '66051')
		-- /**DEBUG**/

		if not exists(select 1 from @packages)
		begin
			set @tid_msg = concat(@proc_name, ': нет пакетов для обработки')
			exec tracer_log @tid, @tid_msg
			goto final
		end

		set @tid_msg = concat('Будет обработано ', (select count(*) from @packages), ' пакетов')
		exec tracer_log @tid, @tid_msg
	-- fill #tables
		exec tracer_log @tid, 'Fill #tables'
		exec tracer_log @tid, '    #sdocs'
			insert into @package(DocId, PackId)		
			select DocId, PackId from @docsOfPackages

			insert into #sdocs_products(
				extern_doc_id,
				extern_product_id, product_name, unit_name, quantity,
				value_pure, value_rur, value_trf_pure, value_trf, value_work
				)
			select
				DocId = concat('5.', d.DocId),
				concat(@subjectId, '-', d.ProductID),
				d.ProductName,
				lower(ltrim(rtrim(d.UnitName))),
				d.Q,
				d.SaleRur,
				d.SaleRurT,
				d.TrfSumPc,
				d.TrfSumPcT,
				d.SrvSumPcT
			from cisp_gate..doc_mfr_products d with(nolock)
				join @package hh on hh.PackId = d.PackId and hh.DocId = d.DocId			

			declare @nds_ratio decimal(10,4)

			update #sdocs_products
			set @nds_ratio = value_trf / nullif(value_trf_pure,0) - 1.00,
				price = value_rur / nullif(quantity,0),
				price_pure = value_pure / nullif(quantity,0),
				price_pure_trf = value_trf_pure / nullif(quantity,0),
				price_list = value_trf / nullif(quantity,0),
				nds_ratio = @nds_ratio,
				value_nds = value_rur - value_pure,
				value_ccy = value_rur

			set @tid_msg = concat('    #sdocs_products ', @@rowcount)
			exec tracer_log @tid, @tid_msg

			insert into #sdocs(
				DocId, extern_id, type_id, status_id,
				subject_id,
				priority_id,
				d_doc, d_delivery, d_ship, d_issue_plan, d_issue,
				number,
				agent_name,
				note
				)
			select 
				h.DocId,
				concat('5.', h.DocId),
				5, -- Пр.заказ
				case when h.IsDeleted = 0 then 10 else -1 end, -- Статус
				@subjectId,
				isnull(try_parse(h.PriorityPlan as int), 500),
				h.DocDate, h.DeliveryDate, h.DeliveryDate, h.MfrPlanDate, h.MfrDate,
				h.DocNo,
				h.ClientName,
				h.DocNote
			from cisp_gate..doc_mfr h with(nolock)
				join @package hh on hh.PackId = h.PackId and hh.DocId = h.DocId

			set @tid_msg = concat('    #sdocs ', @@rowcount)
			exec tracer_log @tid, @tid_msg
		exec tracer_log @tid, '    #sdocs_contents'
			delete from @package;

			insert into @package(DocId, PackId)		
			select DocId, max(PackId)
			from cisp_gate..doc_mfr_contents with(nolock)
			where PackId in (select PackId from @packagesContents)
				and DocId in (select DocId from @docsOfPackages)
			group by DocId

			insert into #sdocs_contents(
				extern_doc_id,
				extern_product_id, product_name,
				parent_id, child_id, name,
				place_id,
				extern_item_id, item_name, item_type_id, item_numpos,
				unit_name, q_netto, q_brutto,
				item_price0, item_value0,
				is_buy, has_childs,
				update_date
				)
			select
				concat('5.', d.DocId),
				concat(@subjectId, '-', d.ProductID),
				d.ProductName,
				d.ParentId, d.ChildId, d.ItemName,
				pl.place_id,
				concat(@subjectId, '-', d.ItemId),
				d.ItemName,
				case d.ChildTypeId
					when 8 then 7 -- Вспомогательные материалы --> Материалы
					when 51 then 6 -- Крепеж --> Стандартные изделия
					else d.ChildTypeId
				end,
                d.DrawingPosition,
				lower(ltrim(rtrim(d.UnitName))),
				d.QNetto, d.QBrutto,
				d.MaterialPc, d.MaterialPc,
				case when d.IsMade = 1 then 0 else 1 end,
				1, -- has_childs
				d.UpdatedOn
			from cisp_gate..doc_mfr_contents d with(nolock)
				join @package hh on hh.PackId = d.PackId and hh.DocId = d.DocId
				left join mfr_places pl on pl.name = d.DivisionTo
			where d.IsDeleted = 0

			set @tid_msg = concat('    #sdocs_contents ', @@rowcount)
			exec tracer_log @tid, @tid_msg

			-- has_childs = 0 - терминальные узлы
				update x set has_childs = 0
				from #sdocs_contents x
				where not exists(
					select 1 from #sdocs_contents
					where extern_doc_id = x.extern_doc_id 
						and extern_product_id = x.extern_product_id
						and parent_id = x.child_id
					)				

			-- is_buy = 1 - терминальные узлы суть материалы
				update x set is_buy = 1
				from #sdocs_contents x
				where is_buy is null
					and has_childs = 0	

			-- иначе is_buy = 0
				update #sdocs_contents set is_buy = 0 where is_buy is null
		exec tracer_log @tid, '    #sdocs_contents_attrs'
			insert into #sdocs_contents_attrs(
				extern_doc_id, child_id, attr_name, attr_value
				)
			select
				concat('5.', d.DocId), d.ChildId,
				d.AttrName, d.AttrValue
			from cisp_gate..doc_mfr_contents_attrs d with(nolock)
				join @package hh on hh.PackId = d.PackId and hh.DocId = d.DocId
			
			set @tid_msg = concat('    #sdocs_contents_attrs ', @@rowcount)
			exec tracer_log @tid, @tid_msg
		exec tracer_log @tid, '    #sdocs_opers'
			insert into #sdocs_opers(
				extern_doc_id, extern_product_id, child_id,
				type_id, number, operkey, extern_id, name,
				place_name,
				duration, duration_id, duration_wk, duration_wk_id,
				post_extern_id, post_name, rate_price,
				resource_extern_id, resource_name, resource_loading
				)
			select
				concat('5.', d.DocId),
				concat(@subjectId, '-', d.ProductID),
				d.ChildId,
				d.OperTypeId, d.OperNumber, d.OperKey, d.OperCode, rtrim(ltrim(d.OperName)),
				d.DivisionNumber,
				d.Duration,
				d.duration_id,
				d.Labour,
				2, -- часы
				d.ProfessionId,
				d.ProfessionName,
				d.JobPrice / nullif(d.Labour,0),
				d.EquipmentId,
				d.EquipmentName,
				d.MachineTime
			from (
				select 
					o.PackId, o.DocId, o.ProductID, o.ChildId, o.OperTypeId, o.OperNumber, o.OperKey, o.OperCode, o.OperName, o.DivisionNumber,
					Duration = o.Duration / nullif(c.QBrutto,0),
					case o.DurationType
						when 'min' then 1 when 'м' then 1 when 'мин' then 1
						when 'h' then 2 when 'ч' then 2 when 'час' then 2
						when 'd' then 3 when 'д' then 3 when 'дн' then 3
					end as duration_id,
					Labour = o.Labour / nullif(c.QBrutto,0),
					ProfessionId = concat(o.CodeProfession, 'р.', o.Qualification),
					ProfessionName = concat(rtrim(ltrim(ProfessionName)), case when Qualification is not null then ' ' end, Qualification, case when Qualification is not null then 'р.' end),
					o.JobPrice,
					EquipmentId = concat(@subjectId, '-', o.EquipmentId),
					EquipmentName = rtrim(ltrim(o.EquipmentName)),
					MachineTime = o.MachineTime / nullif(c.QBrutto,0)
				from cisp_gate..doc_mfr_opers o with(nolock)
					join cisp_gate..doc_mfr_contents c with(nolock) on 
							c.PackId = o.PackId 
						and c.DocId = o.DocId
						and c.ProductId = o.ProductId
						and c.ChildId = o.ChildId
				where o.IsDeleted = 0
				) d
				join @package hh on hh.PackId = d.PackId and hh.DocId = d.DocId
				join projects_durations dur on dur.duration_id = d.duration_id			

			update #sdocs_opers set name = '-' where name = ''

			set @tid_msg = concat('    #sdocs_opers ', @@rowcount)
			exec tracer_log @tid, @tid_msg
            
	BEGIN TRY
	BEGIN TRANSACTION
		-- seed sdocs
			exec tracer_log @tid, 'seed doc_id'

			update x set doc_id = sd.doc_id, plan_id = sd.plan_id
			from #sdocs x
				join sdocs sd on sd.extern_id = x.extern_id
			
			update x set doc_id = sd.doc_id, plan_id = sd.plan_id
			from #sdocs x
				join sdocs sd on sd.type_id = 5 and sd.number = x.number

			-- default plan_id
			update #sdocs set plan_id = 1 where plan_id is null

			declare @seed_id int = isnull((select max(doc_id) from sdocs), 0)

			update x
			set doc_id = @seed_id + xx.id
			from #sdocs x
				join (
					select row_number() over (order by (select 0)) as id, extern_id
					from #sdocs
				) xx on xx.extern_id = x.extern_id
			where x.doc_id is null

			update x set mfr_doc_id = h.doc_id
			from #sdocs_contents x
				join #sdocs h on h.extern_id = x.extern_doc_id
		-- dictionaries
			exec tracer_log @tid, 'Dictionaries'	
			exec mfr_replicate;2 @subjectId = @subjectId
		-- sdocs
			exec tracer_log @tid, 'Process SDOCS'

			-- exclude SDOCS.SOURCE_ID = 1
			declare @docs_noreplicate as app_pkids
				insert into @docs_noreplicate select doc_id from #sdocs
				where doc_id in (select doc_id from sdocs where isnull(source_id,2) = 1)

			delete from #sdocs where doc_id in (select id from @docs_noreplicate)
			delete x from #sdocs_products x where not exists(select 1 from #sdocs where extern_id = x.extern_doc_id)
			delete x from #sdocs_contents x where not exists(select 1 from #sdocs where extern_id = x.extern_doc_id)
			delete x from #sdocs_contents_attrs x where not exists(select 1 from #sdocs where extern_id = x.extern_doc_id)
			delete x from #sdocs_opers x where not exists(select 1 from #sdocs where extern_id = x.extern_doc_id)

			select * into #old_sdocs_products from sdocs_products where doc_id in (select doc_id from #sdocs)
            delete from sdocs_products where doc_id in (select doc_id from #sdocs)

			SET IDENTITY_INSERT SDOCS ON;

				insert into sdocs(
					source_id, type_id,
					extern_id, doc_id, plan_id, priority_id,
					subject_id, stock_id, status_id,
					d_doc, d_delivery, d_ship, d_issue_plan,
					number, agent_id, note,
                    add_mol_id
					)
				select
					2, -- EXTERNAL SYSTEM
                    type_id,
					extern_id, doc_id, plan_id, priority_id,
					subject_id, stock_id,
					0, -- Черновик
					-- 
                    d_doc, d_delivery, d_ship, d_issue_plan,
					--
					number, agent_id, note,
                    -25
				from #sdocs x
                where not exists(select 1 from sdocs where doc_id = x.doc_id)

				set @tid_msg = concat('    SDOCS: ', @@rowcount, ' rows')
				exec tracer_log @tid, @tid_msg

			SET IDENTITY_INSERT SDOCS OFF;
		-- sdocs_products
			exec tracer_log @tid, 'Process SDOCS_PRODUCTS'

			insert into sdocs_products(
				doc_id, product_id,
				unit_id, quantity, w_netto, w_brutto,
				nds_ratio, 
				price, price_pure, price_pure_trf, price_list,
				value_nds, value_pure, value_ccy, value_rur, value_work,
				note
				)
			select
				h.doc_id, d.product_id,
				d.unit_id, d.quantity, ox.w_netto, ox.w_brutto,
				isnull(d.nds_ratio, ox.nds_ratio), 
				isnull(d.price, ox.price),
				isnull(d.price_pure, ox.price_pure),
				isnull(d.price_pure_trf, ox.price_pure_trf),
				isnull(d.price_list, ox.price_list),
				isnull(d.value_nds, ox.value_nds),
				isnull(d.value_pure, ox.value_pure),
				isnull(d.value_ccy, ox.value_ccy),
				isnull(d.value_rur, ox.value_rur),
				isnull(d.value_work, ox.value_work),				
				d.note
			from #sdocs_products d
				join #sdocs h on h.extern_id = d.extern_doc_id
				left join #old_sdocs_products ox on ox.doc_id = h.doc_id and ox.product_id = d.product_id
			
			set @tid_msg = concat('    SDOCS_PRODUCTS: ', @@rowcount, ' rows')
			exec tracer_log @tid, @tid_msg

			exec drop_temp_table '#old_sdocs_products'
		-- contents
			if not exists(select 1 from #sdocs_contents) goto skip_contents
			exec tracer_log @tid, 'Process MFR_DRAFTS'

			-- drafts
				create table #drafts(
					row_id int identity primary key,
					draft_id int index ix_draft,
					mfr_doc_id int, -- код производственного заказа (документ)
					product_id int, -- код продукции
					item_id int, -- код детали/материала
					content_child_id varchar(255), -- ссылка на узел
					is_buy bit not null default(0), -- делаем/покупаем
					has_childs bit,
					is_new bit,
					--	
					status_id int, -- статус чертежа
					number varchar(50), -- номер чертежа
					d_doc datetime, -- дата чертежа
					mol_id int, -- автор (ответственный) чертежа
					note varchar(max),
					item_price0 decimal(18,2), -- цена без ндс
					item_value0 decimal(18,2), -- сумма без ндс
					unit_name varchar(20),
					is_deleted bit,
					chksum int
					)
				
				select top 0 * into #drafts_items from mfr_drafts_items
					;create index ix_drafts on #drafts_items(draft_id, item_id)

				insert into #drafts(
					is_buy, has_childs,
					content_child_id, mfr_doc_id, product_id, item_id, status_id, number, d_doc, mol_id, note, is_deleted
					)
				select distinct 
					0, -- is_buy
					c.has_childs,
					cc.child_id, c.mfr_doc_id, c.product_id, c.item_id,
					0, -- status_id
					'-', @today, -25, 'сформировано автоматически', 0
				from #sdocs_contents c
					join (
						select mfr_doc_id, item_id, min(child_id) as child_id
						from #sdocs_contents
						where is_buy = 0
						group by mfr_doc_id, item_id
					) cc on cc.mfr_doc_id = c.mfr_doc_id and cc.child_id = c.child_id
				where c.is_buy = 0

				insert into #drafts(
					is_buy, content_child_id, mfr_doc_id, product_id, item_id, status_id, number, d_doc, mol_id, note, item_price0, unit_name, is_deleted
					)
				select distinct 
					1, -- is_buy
					cc.child_id, c.mfr_doc_id, c.product_id, c.item_id,
					0, -- status_id
					'-', @today, -25, 'сформировано автоматически (материалы)',
					c.item_price0,
					c.unit_name,
					0
				from #sdocs_contents c
					join (
						select mfr_doc_id, item_id, min(child_id) as child_id
						from #sdocs_contents
						where is_buy = 1
						group by mfr_doc_id, item_id
					) cc on cc.mfr_doc_id = c.mfr_doc_id and cc.child_id = c.child_id
				where c.is_buy = 1
					and not exists(select 1 from #drafts where mfr_doc_id = c.mfr_doc_id and item_id = c.item_id)

				-- seed
					set @seed_id = isnull((select max(draft_id) from mfr_drafts), 0)

					update x set 
						draft_id = d.draft_id
					from #drafts x
						join mfr_drafts d on d.mfr_doc_id = x.mfr_doc_id and d.item_id = x.item_id
					where isnull(d.is_deleted, 0) = 0

					update x set draft_id = @seed_id + xx.new_row_id, is_new = 1
					from #drafts x
						join (
							select row_id, row_number() over (order by row_id) as new_row_id
							from #drafts
							where draft_id is null
						) xx on xx.row_id = x.row_id
			-- drafts, items
				exec tracer_log @tid, '  drafts/items'

				-- #drafts_items (is_buy = 0)
					insert into #drafts_items(draft_id, place_id, item_id, is_buy, item_type_id, numbers, unit_name, q_netto, q_brutto, add_date, is_deleted)
					select 
						d.draft_id, min(c2.place_id), c2.item_id, 0, min(c2.item_type_id), min(c2.item_numpos), min(c2.unit_name), sum(c2.q_netto), sum(c2.q_brutto), min(c2.update_date), 0
					from #drafts d
						join #sdocs_contents c2 on c2.mfr_doc_id = d.mfr_doc_id and c2.product_id = d.product_id and c2.parent_id = d.content_child_id
					where c2.is_buy = 0
					group by d.draft_id, c2.item_id

				-- #drafts_items (is_buy = 1)
					insert into #drafts_items(draft_id, place_id, item_id, is_buy, item_type_id, numbers, unit_name, q_netto, q_brutto, add_date, is_deleted)
					select 
						d.draft_id, c2.place_id, c2.item_id, 1, min(c2.item_type_id), min(c2.item_numpos), min(c2.unit_name), sum(c2.q_netto), sum(c2.q_brutto), min(c2.update_date), 0
					from #drafts d
						join #sdocs_contents c2 on c2.mfr_doc_id = d.mfr_doc_id and c2.product_id = d.product_id and c2.parent_id = d.content_child_id
					where c2.is_buy = 1
					group by d.draft_id, c2.item_id, c2.place_id

				-- build news set
					declare @drafts_inserted as app_pkids
					insert into @drafts_inserted select x.draft_id from #drafts x
					where not exists(select 1 from mfr_drafts where draft_id = x.draft_id)

				-- build changed set
					declare @drafts_updated as app_pkids
					insert into @drafts_updated select x.draft_id from #drafts x
						join mfr_drafts d on d.draft_id = x.draft_id 
							-- and isnull(d.chksum,0) != isnull(x.chksum,1)
					where isnull(d.source_id,2) != 1

				-- build deleted set
					declare @drafts_deleted as app_pkids
					insert into @drafts_deleted select x.draft_id from mfr_drafts x
					where x.mfr_doc_id in (select mfr_doc_id from #drafts)
						and not exists(select 1 from #drafts where draft_id = x.draft_id)
						and x.type_id = 1 -- тех. выписки
						and x.is_deleted = 0
						and isnull(x.source_id,2) != 1

				-- build affected set
					declare @drafts_affected as app_pkids
					insert into @drafts_affected select distinct id from (
						select id from @drafts_updated
						union select id from @drafts_inserted
						) u

				-- if @trace = 1
				-- 	select
				-- 		(select count(*) from @drafts_inserted) 'drafts_inserted',
				-- 		(select count(*) from @drafts_deleted) 'drafts_deleted',
				-- 		(select count(*) from @drafts_updated) 'drafts_updated',
				-- 		(select count(*) from @drafts_affected) 'drafts_affected'

				-- save olds (for update)
					select * into #old_drafts from mfr_drafts where draft_id in (select id from @drafts_updated)
						;create unique index ix_draft on #old_drafts(draft_id)
					select * into #old_drafts_items from mfr_drafts_items where draft_id in (select id from @drafts_updated)
						;create index ix_draft on #old_drafts_items(draft_id,item_id,place_id)

				delete x from mfr_drafts x
					join #old_drafts o on o.draft_id = x.draft_id
				delete x from mfr_drafts_items x 
					join #old_drafts o on o.draft_id = x.draft_id
								
				SET IDENTITY_INSERT SDOCS_MFR_DRAFTS ON
				EXEC SYS_SET_TRIGGERS 0

					insert into mfr_drafts(
						draft_id, extern_id,
						is_root, is_product, is_buy, work_type_1, work_type_2,
						d_doc, number, part_q,
						template_id, status_id, context,
						mfr_doc_id, product_id, item_id, item_price0, unit_name, mol_id, note,
						prop_size, prop_weight,
						executor_id, chksum
						)
					select
						x.draft_id, x.content_child_id,
						isnull(old.is_root,0), isnull(old.is_product,0),
						x.is_buy,
						case when x.is_buy = 0 then 1 end,
						case when x.is_buy = 1 then 1 end,
						isnull(old.d_doc, x.d_doc), isnull(old.number, x.number),
						1, -- PART_Q
						old.template_id,
						isnull(nullif(old.status_id, -1), x.status_id),
						old.context,
						x.mfr_doc_id, x.product_id, x.item_id,
						case
							when isnull(old.context,'') = 'protected' then old.item_price0
							else x.item_price0
						end,
						x.unit_name,
						x.mol_id, isnull(old.note, x.note),
						old.prop_size, old.prop_weight,
						old.executor_id,
						x.chksum
					from #drafts x
						left join #old_drafts old on old.draft_id = x.draft_id
					where x.draft_id in (select id from @drafts_affected)

					insert into mfr_drafts_items(
						draft_id, place_id, item_id, is_buy, item_type_id, numbers, unit_name, q_netto, q_brutto,
						add_mol_id, add_date
						)
					select 
						d.draft_id, i.place_id, i.item_id,
                        min(case when i.is_buy = 1 then 1 else 0 end),
                        min(i.item_type_id), min(i.numbers), i.unit_name,
						sum(i.q_netto), sum(i.q_brutto),
						@mol_id, max(isnull(old.add_date, getdate()))
					from #drafts_items i
						join #drafts d on d.draft_id = i.draft_id
						left join (
							select draft_id, item_id, place_id, add_date = max(add_date)
							from #old_drafts_items 
							group by draft_id, item_id, place_id
						) old on old.draft_id = i.draft_id and old.item_id = i.item_id
							and isnull(old.place_id,0) = isnull(i.place_id,0)
						join products pr on pr.product_id = i.item_id
					where d.draft_id in (select id from @drafts_affected)
					group by d.draft_id, i.item_id, pr.name, i.place_id, i.unit_name
					order by d.draft_id, pr.name
				
				EXEC SYS_SET_TRIGGERS 1
				SET IDENTITY_INSERT SDOCS_MFR_DRAFTS OFF

				-- mark as deleted
					update mfr_drafts set is_deleted = 1 where draft_id in (select id from @drafts_deleted)

				-- remove self-reference
					delete di from mfr_drafts_items di
						join mfr_drafts d on d.draft_id = di.draft_id
							join @drafts_affected i on i.id = d.draft_id
					where di.item_id = d.item_id
			-- opers
				EXEC SYS_SET_TRIGGERS 0

				exec tracer_log @tid, '  opers'
				
				exec tracer_log @tid, '  ...#drafts_opers'
					select o.*
						, d.draft_id
						, lag(o.number, 1, null) over (partition by d.draft_id order by o.number) as predecessors
					into #drafts_opers
					from #sdocs_opers o
						join #sdocs sd on sd.extern_id = o.extern_doc_id
						join #drafts d on d.mfr_doc_id = sd.doc_id and d.content_child_id = o.child_id
					where o.place_id is not null	 -- ТОЛЬКО СУЩЕСТВУЮЩИЕ УЧАСТКИ

						; create index ix_opers1 on #drafts_opers(draft_id, number)
						; create index ix_opers2 on #drafts_opers(oper_id)

				exec tracer_log @tid, '  ...seed'
					update x set oper_id = c.oper_id
					from #drafts_opers x
						join mfr_drafts_opers c on c.draft_id = x.draft_id and c.operkey = x.operkey

					set @seed_id = isnull((select max(oper_id) from mfr_drafts_opers), 0)
				
					update x
					set oper_id = @seed_id + xx.id
					from #drafts_opers x
						join (
							select row_number() over (order by number) as id, draft_id, operkey
							from #drafts_opers
						) xx on xx.draft_id = x.draft_id and xx.operkey = x.operkey
					where x.oper_id is null

				exec tracer_log @tid, '  ...insert opers'
					SET IDENTITY_INSERT SDOCS_MFR_DRAFTS_OPERS ON;
						insert into mfr_drafts_opers(
							DRAFT_ID, OPER_ID, WORK_TYPE_ID,
							place_id, type_id,
							number, operkey, extern_id, name,
							predecessors,
							duration, duration_id, duration_wk, duration_wk_id
							)
						select
							x.draft_id, x.oper_id,
							case when d.is_buy = 0 then 1 else 2 end,
							x.place_id, x.type_id,
							x.number, x.operkey, x.extern_id, x.name,
							x.predecessors,
							x.duration, x.duration_id, x.duration_wk, x.duration_wk_id
						from #drafts_opers x
							join #drafts d on d.draft_id = x.draft_id
						where not exists(select 1 from mfr_drafts_opers where draft_id = x.draft_id)

					set @tid_msg = concat('  SDOCS_MFR_DRAFTS_OPERS ', @@rowcount, ' rows')
					exec tracer_log @tid, @tid_msg
					
					SET IDENTITY_INSERT SDOCS_MFR_DRAFTS_OPERS OFF;

				exec tracer_log @tid, '  ...sdocs_mfr_drafts_opers_executors'
					insert into sdocs_mfr_drafts_opers_executors(
						draft_id, oper_id, post_id, duration_wk, duration_wk_id, rate_price
						)
					select
						draft_id, oper_id, post_id, duration_wk, duration_wk_id, rate_price
					from #drafts_opers x
					where post_id is not null
						and not exists(select 1 from sdocs_mfr_drafts_opers_executors where oper_id = x.oper_id)

				exec tracer_log @tid, '  ...sdocs_mfr_drafts_opers_resources'
					insert into sdocs_mfr_drafts_opers_resources(draft_id, oper_id, resource_id, loading)
					select draft_id, oper_id, resource_id, resource_loading
					from #drafts_opers x
					where resource_id is not null
						and not exists(select 1 from sdocs_mfr_drafts_opers_resources where oper_id = x.oper_id)
				
				EXEC SYS_SET_TRIGGERS 1
			-- attrs
				exec tracer_log @tid, '  attrs'

				-- @attrMfrRoute
				select distinct d.draft_id, ca.attr_id, ca.attr_name, ca.attr_value
				into #drafts_attrs
				from #drafts d
					join #sdocs sd on sd.doc_id = d.mfr_doc_id
					join #sdocs_contents_attrs ca on ca.extern_doc_id = sd.extern_id and ca.child_id = d.content_child_id

				EXEC SYS_SET_TRIGGERS 0
					update x
					set number = a.attr_value
					from mfr_drafts x
						join #drafts_attrs a on a.draft_id = x.draft_id and a.attr_name = 'узел.ЧертёжСП'

					delete x from mfr_drafts_attrs x
						join #drafts c on c.draft_id = x.draft_id

					insert into mfr_drafts_attrs(draft_id, attr_id, note)
					select draft_id, attr_id, attr_value from #drafts_attrs

					set @tid_msg = concat('  MFR_DRAFTS_ATTRS ', @@rowcount, ' rows')
					exec tracer_log @tid, @tid_msg

				EXEC SYS_SET_TRIGGERS 1

			exec drop_temp_table '#old_drafts,#old_drafts_items'
			exec drop_temp_table '#drafts,#drafts_items,#drafts_opers,#drafts_attrs'
			
			skip_contents:
		-- packs processed
			update cisp_gate..packs set ProcessedOn = getdate()
			where PackId in (select PackId from @packages)
	COMMIT TRANSACTION

        -- post-process
            declare @docs_calc as app_pkids; 
                insert into @docs_calc
                select distinct doc_id from #sdocs where doc_id is not null
            
            if (select count(*) from @docs_calc) < 500
            begin
                exec tracer_log @tid, 'build contents'
                exec mfr_drafts_calc @mol_id = @mol_id, @docs = @docs_calc

                exec tracer_log @tid, 'normalize data'
                exec mfr_replicate_normalize @docs = @docs_calc
            end
            else
                exec tracer_log @tid, '  build contents MUST BE manually'

	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		exec tracer_log @tid, @err
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

	final:
		exec drop_temp_table '#sdocs,#sdocs_products,#sdocs_contents,#sdocs_contents_attrs,#sdocs_opers'

		-- close log	
		exec tracer_close @tid
		if @trace = 1 exec tracer_view @tid
		return

	mbr:
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		raiserror('manual break', 16, 1)
end
GO
-- helper: auto-dictionaries
create proc mfr_replicate;2
	@subjectId int
as
begin
	-- AGENTS
		insert into agents(name, name_print, inn)
		select distinct agent_name, agent_name, '-'
		from #sdocs
		where agent_name not in (select name from agents)
			and agent_name != '-'

		update x
		set agent_id = isnull(a.main_id, a.agent_id)
		from #sdocs x
			join agents a on a.name = x.agent_name
	-- PRODUCTS
		-- @products
			declare @products table(extern_id varchar(32), name varchar(500))
			
			insert into @products(extern_id, name)
			select extern_id, name = min(name)
			from (
				select extern_id = extern_product_id, name = min(product_name) from #sdocs_products group by extern_product_id
				union select extern_product_id, min(product_name) from #sdocs_contents group by extern_product_id
				union select extern_item_id, min(item_name) from #sdocs_contents group by extern_item_id
				) u
			group by extern_id

		-- нормализация имён
			update x set
				name = xx.name
			from mfr_replications_products x
				join @products xx on xx.extern_id = x.extern_id
			where x.name != xx.name

			update p set p.name = r.name
			from mfr_replications_products r
				join products p on p.product_id = r.product_id
			where r.name != p.name

		-- auto-insert
			-- пополняем mapping
			insert into mfr_replications_products(extern_id, name)
			select x.extern_id, x.name
			from @products x
			where not exists(select 1 from mfr_replications_products where extern_id = x.extern_id)

			update r set product_id = p.product_id
			from mfr_replications_products r
				join products p on p.name = r.name
			where r.product_id is null

			-- пополняем справочник
			insert into products(name, name_print, status_id)
			select distinct name, name, 5
			from mfr_replications_products x
			where product_id is null
                and not exists(select 1 from products where name = x.name)

			-- завершаем mapping
			update x set product_id = p.product_id
			from mfr_replications_products x
				join products p on p.name = x.name
			where x.product_id is null

		-- back updates
			update x set product_id = isnull(pp.main_id, pp.product_id)
			from #sdocs_products x
				join mfr_replications_products p on p.extern_id = x.extern_product_id
					join products pp on pp.product_id = p.product_id
			where x.product_id is null

			update x set product_id = isnull(pp.main_id, pp.product_id)
			from #sdocs_contents x
				join mfr_replications_products p on p.extern_id = x.extern_product_id
					join products pp on pp.product_id = p.product_id
			where x.product_id is null

			update x set item_id = isnull(pp.main_id, pp.product_id)
			from #sdocs_contents x
				join mfr_replications_products p on p.extern_id = x.extern_item_id
					join products pp on pp.product_id = p.product_id

	declare @seed_id int

	-- UNIT_NAME
		-- auto-insert
			set @seed_id = isnull((select max(unit_id) from products_units), 0)
			insert into products_units(unit_id, name)
			select @seed_id + (row_number() over (order by unit_name)), u.unit_name
			from (
				select distinct x.unit_name
				from #sdocs_products x
				where not exists(select 1 from products_units where name = x.unit_name)
				) u

		-- back updates
			update x set unit_id = u.unit_id
			from #sdocs_products x
				join products_units u on u.name = x.unit_name

	-- MFR_ATTRS
		if not exists(select 1 from mfr_attrs where attr_key = 'MfrRoute')
			insert into mfr_attrs(slice, group_key, group_name, attr_key, name)
			values ('Base', 'Misc', 'Прочие', 'MfrRoute', 'Маршрут')

		declare @attrs table(row_id int identity primary key, attr_id int, name varchar(150))
			insert into @attrs(name)
			select distinct attr_name
			from #sdocs_contents_attrs x
			where not exists(
				select 1 from mfr_attrs where group_key = 'AttrItems' and name = x.attr_name
				)

		set @seed_id = isnull((select max(attr_id) from mfr_attrs), 0)
		update x
		set attr_id = @seed_id + number_id
		from @attrs x
			join (
				select row_id, row_number() over (order by row_id) as number_id
				from @attrs
			) xx on xx.row_id = x.row_id

		insert into mfr_attrs(slice, group_name, group_key, attr_key, name, value_type)
		select 'content', 'АтрибутыДеталей', 'AttrItems', concat('AttrItem', attr_id), name, 'list'
		from @attrs

		update x set attr_id = a.attr_id
		from #sdocs_contents_attrs x
			join mfr_attrs a on a.group_key = 'AttrItems' and a.name = x.attr_name

	-- MFR_PLACES
		insert into mfr_places(subject_id, name, full_name)
		select distinct @subjectId, place_name, place_name from #sdocs_opers x
		where not exists(select 1 from mfr_places where name = x.place_name)

		update x set place_id = xx.place_id
		from #sdocs_opers x
			join mfr_places xx on xx.name = x.place_name

	-- MOLS_POSTS
		insert into mols_posts(subject_id, name, extern_id, rate_price)
		select @subjectid, post_name, max(post_extern_id), max(rate_price) from #sdocs_opers x
		where not exists(select 1 from mols_posts where name = x.post_name)
			and not exists(select 1 from mols_posts where extern_id = x.post_extern_id)
		group by post_name

		update x set post_id = xx.post_id
		from #sdocs_opers x
			join mols_posts xx on xx.subject_id = @subjectid and xx.extern_id = x.post_extern_id

		update x set post_id = xx.post_id
		from #sdocs_opers x
			join mols_posts xx on xx.subject_id = @subjectid and xx.name = x.post_name
		where x.post_id is null

	-- MFR_RESOURCES
		insert into mfr_resources(name, extern_id)
		select resource_name, max(resource_extern_id)
		from #sdocs_opers x
		where isnull(resource_name,'') != ''
			and not exists(select 1 from mfr_resources where name = x.resource_name)
			and not exists(select 1 from mfr_resources where extern_id = x.resource_extern_id)
		group by resource_name

		update x set resource_id = xx.resource_id
		from #sdocs_opers x
			join mfr_resources xx on xx.extern_id = x.resource_extern_id

		update x set resource_id = xx.resource_id
		from #sdocs_opers x
			join mfr_resources xx on xx.name = x.resource_name
		where x.resource_id is null
end
GO

-- update cisp_gate..packs set processedon = null where PackId = 828075
-- exec mfr_replicate;10 @mol_id=1000, @channel = 'kcl.mfrorders'
