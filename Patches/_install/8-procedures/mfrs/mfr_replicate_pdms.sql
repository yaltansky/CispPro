if object_id('mfr_replicate_pdms') is not null drop proc mfr_replicate_pdms
go
-- exec mfr_replicate_pdms @mol_id = 1000, @trace = 1
create proc mfr_replicate_pdms
	@mol_id int = null,	
	@trace bit = 1
as
begin
	set nocount on;

    declare @subjectId int = cast(dbo.app_registry_value('MfrReplSubjectId') as int)
    declare @channelName varchar(max) = dbo.app_registry_varchar('MfrReplChannelPdm')
	
	-- prepare
		set @mol_id = isnull(@mol_id, -25)
		
		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

		declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
			' @mol_id=', @mol_id
			)
		exec tracer_log @tid, @tid_msg
	-- packages
		create table #packages(PackId int primary key)
			insert into #packages select PackId
			from cisp_gate..packs
			where ChannelName in (@channelName)
				and ProcessedOn is null

		if not exists(select 1 from #packages)
		begin
			exec tracer_log @tid, 'Нет пакетов для обработки'
			goto final
		end

		set @tid_msg = concat('Будет обработано ', (select count(*) from #packages), ' пакетов')
		exec tracer_log @tid, @tid_msg

		create table #package(
			PackId int,
			PdmId varchar(100),
			primary key (PackId, PdmId)
			)
	-- #tables
		create table #pdm(
			EXTERN_ID VARCHAR(50) PRIMARY KEY,
			PdmId VARCHAR(50) INDEX IX_PdmId,
			PDM_ID INT,
			VERSION_NUMBER VARCHAR(30),
			IS_DEFAULT BIT,
			NUMBER VARCHAR(100),
			EXTERN_ITEM_ID VARCHAR(32),
			ITEM_ID INT,
			ITEM_NAME VARCHAR(500),
			NOTE VARCHAR(MAX)
		)
		create table #pdm_docs(
			EXTERN_PDM_ID VARCHAR(100) INDEX IX_EXTERN,
			EXTERN_ID VARCHAR(50),
			PDM_DOC_ID INT,
			NUMBER VARCHAR(100),
			NAME VARCHAR(255),
			URL VARCHAR(1024)
		)
		create table #pdm_options(
			EXTERN_PDM_ID VARCHAR(100) INDEX IX_EXTERN,
			EXTERN_ID VARCHAR(50),
			PDM_OPTION_ID INT,
			GROUP_NAME VARCHAR(50),
			NAME VARCHAR(255),
			IS_DEFAULT BIT NOT NULL DEFAULT(0)
		)
		create table #pdm_items(
			-- ids
			ID INT,
			EXTERN_ID VARCHAR(50) INDEX IX_EXTERN,
			PARENT_ID INT,
			PARENT_EXTERN_ID VARCHAR(32) INDEX IX_EXTERN_PARENT,
			EXTERN_PDM_ID VARCHAR(50) INDEX IX_EXTERN_PDM,
			-- options
			PDM_OPTION_ID INT,
			OPTION_ID VARCHAR(50),
			-- item
			IS_BUY BIT,
			ITEM_TYPE_ID INT,
			ITEM_TYPE VARCHAR(255),
			EXTERN_ITEM_ID VARCHAR(32),
			ITEM_ID INT,
			ITEM_NAME VARCHAR(500),
			NUMPOS VARCHAR(50),
			PLACE_ID INT,
			-- q
			UNIT_NAME VARCHAR(20),
			Q_BRUTTO FLOAT,
			Q_NETTO FLOAT
		)
		create table #pdm_opers(
			-- logical primary key
			EXTERN_PDM_ID VARCHAR(50) INDEX IX_EXTERN,
			VARIANT_NUMBER INT,
			NUMBER INT,
			OPERKEY VARCHAR(10),
			-- 
			OPER_ID INT INDEX IX_OPER,
			--
			PLACE_ID INT,
			NAME VARCHAR(100),
			--
			DURATION FLOAT,
			DURATION_ID INT,
			DURATION_WK FLOAT,
			DURATION_WK_ID INT,
			PART_Q FLOAT,
			COUNT_WORKERS INT,
		)
		create table #pdm_opers_executors(
			EXTERN_PDM_ID VARCHAR(50) INDEX IX_EXTERN,
			VARIANT_NUMBER INT,
			OPER_NUMBER INT,
			--
			POST_EXTERN_ID VARCHAR(32),
			POST_NAME VARCHAR(255),
			POST_ID INT, -- Код специальности
			DURATION_WK FLOAT, -- Оценка трудоёмкости
			DURATION_WK_ID INT, -- Единица измерения трудоёмкости (в днях, [часах, минутах])
			RATE_PRICE FLOAT, -- Стоимость работ
			NOTE VARCHAR(MAX), -- Описание работ
		)
		create table #pdm_opers_resources(
			EXTERN_PDM_ID VARCHAR(50) INDEX IX_EXTERN,
			VARIANT_NUMBER INT,
			OPER_NUMBER INT,
			-- 
			RESOURCE_EXTERN_ID VARCHAR(32),
			RESOURCE_NAME VARCHAR(255),
			RESOURCE_ID INT, -- Код ресурса
			LOADING FLOAT, -- Использование ресурса
			LOADING_PRICE FLOAT, -- Цена за единицу
			LOADING_VALUE DECIMAL(18,2), -- Стоимость использования ресурса
		)
	
    -- fill #tables
		exec tracer_log @tid, '#pdm'
			delete from #package;
			insert into #package(PdmId, PackId)		
				select PdmId, max(PackId) from cisp_gate..mfr_pdm
				where PackId in (select PackId from #packages)
				group by PdmId

			insert into #pdm(
				PdmId, extern_id,
				version_number, is_default,
				extern_item_id, item_name,
				number, note
				)
			select
				concat(h.PdmId, '-v', v.VariantNo),
				concat(h.PdmId, '-v', v.VariantNo),
				v.VariantNo,
				case when v.VariantNo = 1 then 1 else 0 end,
				concat(@subjectId, '-', h.ItemId),
				h.ItemName,
				h.DrawingNo,
        h.DocNote
			from cisp_gate..mfr_pdm h
				join cisp_gate..mfr_pdm_variants v on v.PackId = h.PackId and v.PdmId = h.PdmId
				join #package hh on hh.PackId = h.PackId and hh.PdmId = h.PdmId
			
			set @tid_msg = concat('    pdm: ', @@rowcount, ' rows')
			exec tracer_log @tid, @tid_msg
		exec tracer_log @tid, '#pdm_docs'
			insert into #pdm_docs(
				extern_pdm_id,
				number, name, url
				)
			select distinct
				concat(d.PdmId, '-v', d.VariantNo),
			    d.FileId, d.FileName, d.Url
			from cisp_gate..mfr_pdm_docs d
				join #package hh on hh.PackId = d.PackId and hh.PdmId = d.PdmId
		exec tracer_log @tid, '#pdm_options'
			insert into #pdm_options(
				extern_pdm_id, extern_id,
				group_name, name, is_default
				)
			select distinct
				concat(d.PdmId, '-v', d.VariantNo),
				concat(d.OptionId, '-', d.OptionType),
				d.OptionType, d.OptionName, d.OptionIsDefault
			from cisp_gate..mfr_pdm_items d
				join #package hh on hh.PackId = d.PackId and hh.PdmId = d.PdmId
			where d.OptionName is not null
		exec tracer_log @tid, '#pdm_items'
			insert into #pdm_items(
				extern_pdm_id,
				extern_id, parent_extern_id,
				option_id,
				place_id,
				is_buy, item_type, extern_item_id, item_name, numpos,
				unit_name, q_brutto, q_netto
				)
			select
				concat(d.PdmId, '-v', d.VariantNo),
				-- 
				d.ChildId, nullif(d.ParentId, ''),
				-- 
				case
					when d.OptionId = '0' then null
					else concat(d.OptionId, '-', d.OptionType)
				end,
				-- 
				pl.place_id,
				d.IsBuy,
				d.ItemType, 
				concat(@subjectId, '-', d.ItemId),
				d.ItemName, d.DrwPosNo,
				-- 
				d.UnitName, d.QBrutto, d.QNetto
			from cisp_gate..mfr_pdm_items d
				join #package hh on hh.PackId = d.PackId and hh.PdmId = d.PdmId
				left join mfr_places pl on nullif(pl.name, '') = d.DivisionTo

		exec tracer_log @tid, '#pdm_opers'
			insert into #pdm_opers(
				extern_pdm_id, variant_number,
				place_id, number, name, operkey,
				duration, duration_id,
				part_q, count_workers
				)
			select
				concat(d.PdmId, '-v', d.VariantNo),
				d.VariantNumber,
				pl.place_id, d.OperNumber, d.OperName, d.OperKey,
				d.Duration,
				case d.DurationType
					when 'min' then 1 when 'м' then 1 when 'мин' then 1
					when 'h' then 2 when 'ч' then 2 when 'час' then 2
					when 'd' then 3 when 'д' then 3 when 'дн' then 3
				end,
				d.BatchProduction, d.Workers
			from cisp_gate..mfr_pdm_opers d
				join #package hh on hh.PackId = d.PackId and hh.PdmId = d.PdmId
				left join mfr_places pl on pl.name = d.DivisionNumber
		exec tracer_log @tid, '#pdm_opers_executors'
			insert into #pdm_opers_executors(
				extern_pdm_id, variant_number, oper_number,
				post_extern_id, post_name,
				duration_wk, duration_wk_id,
				rate_price
				)
			select
				concat(d.PdmId, '-v', d.VariantNo),
				d.VariantNumber, d.OperNumber,
				ProfessionId = concat(d.CodeProfession, 'р.', d.Qualification),
				ProfessionName = concat(rtrim(ltrim(ProfessionName)),
				case when Qualification is not null then ' ' end, Qualification, case when Qualification is not null then 'р.' end),
				d.Labour,
				case d.LabourType
					when 'min' then 1 when 'м' then 1 when 'мин' then 1
					when 'h' then 2 when 'ч' then 2 when 'час' then 2
					when 'd' then 3 when 'д' then 3 when 'дн' then 3
				end,
				d.JobPrice / nullif(d.Labour,0)
			from cisp_gate..mfr_pdm_opers_executors d
				join #package hh on hh.PackId = d.PackId and hh.PdmId = d.PdmId
		exec tracer_log @tid, '#pdm_opers_resources'
			insert into #pdm_opers_resources(
				extern_pdm_id, variant_number, oper_number,
				resource_extern_id, resource_name,
				loading
				)
			select
				concat(d.PdmId, '-v', d.VariantNo),
				d.VariantNumber, d.OperNumber,
				concat(@subjectId, '-', d.EquipmentId), 
				d.EquipmentName,
				d.MachineTime
			from cisp_gate..mfr_pdm_opers_resources d
				join #package hh on hh.PackId = d.PackId and hh.PdmId = d.PdmId

	BEGIN TRY
	BEGIN TRANSACTION
		exec tracer_log @tid, 'dictionaries'
			exec mfr_replicate_pdms;2 @subjectId
            declare @seed int
        exec tracer_log @tid, 'build ids'
            update x set pdm_id = sd.pdm_id
            from #pdm x
                join mfr_pdms sd on sd.extern_id = x.extern_id

            set @seed = isnull((select max(pdm_id) from mfr_pdms), 0)

            update x
            set pdm_id = @seed + xx.id
            from #pdm x
                join (
                    select row_number() over (order by number) as id, extern_id
                    from #pdm
                ) xx on xx.extern_id = x.extern_id
            where x.pdm_id is null
			-- seed mfr_pdms_options
				update x set pdm_option_id = xx.pdm_option_id
				from #pdm_options x
					join #pdm y on y.extern_id = x.extern_pdm_id
						join mfr_pdm_options xx on xx.pdm_id = y.pdm_id and xx.extern_id = x.extern_id

				set @seed = isnull((select max(pdm_option_id) from mfr_pdm_options), 0)

				update x
				set pdm_option_id = @seed + xx.id
				from #pdm_options x
					join (
						select row_number() over (order by extern_pdm_id, group_name, name) as id,
							extern_pdm_id,
							extern_id
						from #pdm_options
					) xx on xx.extern_pdm_id = x.extern_pdm_id and xx.extern_id = x.extern_id
				where x.pdm_option_id is null

				update x set pdm_option_id = o.pdm_option_id
				from #pdm_items x
					join #pdm_options o on o.extern_pdm_id = x.extern_pdm_id and o.extern_id = x.option_id
			-- seed mfr_pdms_items
				update x set id = xx.id
				from #pdm_items x
					join #pdm y on y.extern_id = x.extern_pdm_id
						join mfr_pdm_items xx on xx.pdm_id = y.pdm_id and xx.extern_id = x.extern_id and isnull(xx.is_deleted, 0) = 0

				set @seed = isnull((select max(id) from mfr_pdm_items), 0)

				update x
				set id = @seed + xx.id
				from #pdm_items x
					join (
						select row_number() over (order by extern_pdm_id, numpos, extern_id) as id,
							extern_pdm_id,
							extern_id
						from #pdm_items
					) xx on xx.extern_pdm_id = x.extern_pdm_id and xx.extern_id = x.extern_id
				where x.id is null

				update x set id = xx.id
				from #pdm_items x
					join #pdm_items xx on xx.extern_pdm_id = x.extern_pdm_id and xx.extern_id = x.extern_id

				update x set parent_id = xx.id
				from #pdm_items x
					join #pdm_items xx on xx.extern_pdm_id = x.extern_pdm_id and xx.extern_id = x.parent_extern_id

				-- delete unknown
				delete from #pdm_items where nullif(parent_extern_id, '') is not null and parent_id is null
			-- seed mfr_pdms_opers
				update x set oper_id = xx.oper_id
				from #pdm_opers x
					join #pdm y on y.extern_id = x.extern_pdm_id
						join mfr_pdm_opers xx on xx.pdm_id = y.pdm_id 
							and xx.variant_number = x.variant_number
							and xx.number = x.number

				set @seed = isnull((select max(oper_id) from mfr_pdm_opers), 0)

				update x
				set oper_id = @seed + xx.id
				from #pdm_opers x
					join (
						select row_number() over (order by extern_pdm_id, variant_number, number) as id,
							extern_pdm_id,
							variant_number, number
						from #pdm_opers
					) xx on xx.extern_pdm_id = x.extern_pdm_id 
						and xx.variant_number = x.variant_number
						and xx.number = x.number
				where x.oper_id is null

        exec tracer_log @tid, 'mfr_pdms'

            delete x from #pdm x
                join mfr_pdms xx on xx.pdm_id = x.pdm_id
            where xx.source_id = 1 -- источник "КИСП" не реплицируется

            delete from mfr_pdms where pdm_id in (select pdm_id from #pdm)

            SET IDENTITY_INSERT MFR_PDMS ON;

                insert into mfr_pdms(		
                    extern_id, pdm_id, version_number, is_default, status_id, d_doc, number, item_id, note, add_mol_id
                    )
                select
                    extern_id, pdm_id, version_number, is_default, 0, dbo.today(), number, item_id, note, @mol_id
                from #pdm

                set @tid_msg = concat('    mfr_pdms: ', @@rowcount, ' rows inserted')
                exec tracer_log @tid, @tid_msg
            
            SET IDENTITY_INSERT MFR_PDMS OFF;
        exec tracer_log @tid, 'mfr_pdm_docs'
            delete x from mfr_pdm_docs x where pdm_id in (select pdm_id from #pdm)
                and exists(
                        select 1 
                        from #pdm_docs d
                            join #pdm h on h.extern_id = d.extern_pdm_id
                        where h.pdm_id = x.pdm_id)

            insert into mfr_pdm_docs(
                pdm_id, number, name, url
                )
            select
                h.pdm_id, d.number, d.name, d.url
            from #pdm_docs d
                join #pdm h on h.extern_id = d.extern_pdm_id
        exec tracer_log @tid, 'mfr_pdm_options'
            delete x from mfr_pdm_options x where pdm_id in (select pdm_id from #pdm)
                and exists(
                        select 1 
                        from #pdm_options d
                            join #pdm h on h.extern_id = d.extern_pdm_id
                        where h.pdm_id = x.pdm_id)

            SET IDENTITY_INSERT MFR_PDM_OPTIONS ON;
            
            insert into mfr_pdm_options(
                pdm_id, pdm_option_id, extern_id,
                group_name, name, is_default
                )
            select
                h.pdm_id, d.pdm_option_id, d.extern_id,
                d.group_name, d.name, d.is_default
            from #pdm_options d
                join #pdm h on h.extern_id = d.extern_pdm_id

            SET IDENTITY_INSERT MFR_PDM_OPTIONS OFF;
        exec tracer_log @tid, 'mfr_pdm_items'
            delete x from mfr_pdm_items x where pdm_id in (select pdm_id from #pdm)
                and exists(
                        select 1 
                        from #pdm_items d
                            join #pdm h on h.extern_id = d.extern_pdm_id
                        where h.pdm_id = x.pdm_id)

            SET IDENTITY_INSERT MFR_PDM_ITEMS ON;

            insert into mfr_pdm_items(
                id, extern_id, parent_id,
                pdm_id,
                pdm_option_id,
                is_buy, item_type_id, item_id, numpos, place_id,
                unit_name, q_brutto, q_netto
                )
            select
                d.id, d.extern_id, d.parent_id,
                h.pdm_id,
                pdm_option_id,
                is_buy, item_type_id, d.item_id, d.numpos, d.place_id,
                unit_name, q_brutto, q_netto
            from #pdm_items d
                join #pdm h on h.extern_id = d.extern_pdm_id
            order by h.pdm_id, d.numpos

            SET IDENTITY_INSERT MFR_PDM_ITEMS OFF;

            update x set item_type_id = xp.item_type_id
            from mfr_pdm_items x
                join mfr_pdm_items xp on xp.id = x.parent_id
            where x.item_type_id != xp.item_type_id
        exec tracer_log @tid, 'mfr_pdm_opers'
            delete x from mfr_pdm_opers x where pdm_id in (select pdm_id from #pdm)
                and exists(
                        select 1 
                        from #pdm_opers d
                            join #pdm h on h.extern_id = d.extern_pdm_id
                        where h.pdm_id = x.pdm_id)

            SET IDENTITY_INSERT MFR_PDM_OPERS ON;

            insert into mfr_pdm_opers(
                oper_id,
                pdm_id, variant_number,
                place_id, number, name, operkey,
                duration, duration_id, part_q, count_workers,
                work_type_id,
                predecessors
                )
            select
                d.oper_id,
                h.pdm_id, d.variant_number,
                place_id, d.number, d.name, d.operkey,
                --
                d.duration,
                d.duration_id,
                d.part_q,
                d.count_workers,
                p.work_type_id,
                -- 
                predecessors = lag(d.number, 1, null) over (partition by d.extern_pdm_id, d.variant_number order by d.number)
            from #pdm_opers d
                join #pdm h on h.extern_id = d.extern_pdm_id
                  left join mfr_places p on p.place_id = d.place_id

            update h set status_id = 10 -- Принят
            from mfr_pdms h
                join (
                    select h.pdm_id
                    from #pdm_opers d
                        join #pdm h on h.extern_id = d.extern_pdm_id
                    group by h.pdm_id
                ) d on d.pdm_id = h.pdm_id

            SET IDENTITY_INSERT MFR_PDM_OPERS OFF;
        exec tracer_log @tid, 'mfr_pdm_opers_executors'
            delete x from mfr_pdm_opers_executors x where pdm_id in (select pdm_id from #pdm)
                and exists(
                        select 1 
                        from #pdm_opers_executors d
                            join #pdm h on h.extern_id = d.extern_pdm_id
                        where h.pdm_id = x.pdm_id)

            insert into mfr_pdm_opers_executors(
                pdm_id, oper_id,
                duration_wk, duration_wk_id,
                post_id, rate_price
                )
            select
                h.pdm_id, o.oper_id,
                d.duration_wk, d.duration_wk_id,
                d.post_id, d.rate_price
            from #pdm_opers_executors d
                join #pdm h on h.extern_id = d.extern_pdm_id
                join #pdm_opers o on o.extern_pdm_id = d.extern_pdm_id
                    and o.variant_number = d.variant_number
                    and o.number = d.oper_number
        exec tracer_log @tid, 'mfr_pdm_opers_resources'
            delete x from mfr_pdm_opers_resources x where pdm_id in (select pdm_id from #pdm)
                and exists(
                        select 1 
                        from #pdm_opers_resources d
                            join #pdm h on h.extern_id = d.extern_pdm_id
                        where h.pdm_id = x.pdm_id)

            insert into mfr_pdm_opers_resources(
                pdm_id, oper_id,
                resource_id,
                loading
                )
            select
                h.pdm_id, o.oper_id,
                d.resource_id,
                d.loading
            from #pdm_opers_resources d
                join #pdm h on h.extern_id = d.extern_pdm_id
                join #pdm_opers o on o.extern_pdm_id = d.extern_pdm_id
                    and o.variant_number = d.variant_number
                    and o.number = d.oper_number

		set @tid_msg = concat('Успешно обработано ', (select count(*) from #packages), ' пакетов')
		exec tracer_log @tid, @tid_msg
		
		update cisp_gate..packs set ProcessedOn = getdate()
		where PackId in (select PackId from #packages)
	COMMIT TRANSACTION
	END TRY	
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

    declare @pdms app_pkids; insert into @pdms select pdm_id from #pdm where pdm_id is not null;
    exec mfr_pdm_calc @mol_id = @mol_id, @pdms = @pdms;

	exec drop_temp_table '#packages,#package,#pdm,#pdm_variants,#pdm_options,#pdm_items,#pdm_opers,#pdm_opers_executors,#pdm_opers_resources'

	final:
		-- close log	
		exec tracer_close @tid
		if @trace = 1 exec tracer_view @tid
		return

	mbr:
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		RAISERROR('MANUAL BREAK', 16, 1)
end
GO

-- helper: авто-справочники
create proc mfr_replicate_pdms;2
	@subjectId int
as
begin
	declare @seed int

	-- PRODUCTS
		-- @products
			declare @products table(extern_id varchar(32), name varchar(500))
			
			insert into @products(extern_id, name)
			select extern_id, name = min(name)
			from (
				select extern_id = extern_item_id, name = min(item_name) from #pdm group by extern_item_id
				union all
				select extern_id = extern_item_id, name = min(item_name) from #pdm_items group by extern_item_id
				) u
			group by extern_id

		-- нормализация имён
			update x set
				name = xx.name
			from mfr_replications_products x
				join @products xx on xx.extern_id = x.extern_id
			where x.name != xx.name

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

			-- завершаем mapping
			update x set product_id = p.product_id
			from mfr_replications_products x
				join products p on p.name = x.name
			where x.product_id is null

		-- back updates
			update x set item_id = p.product_id
			from #pdm x
				join mfr_replications_products p on p.extern_id = x.extern_item_id

			update x set item_id = p.product_id
			from #pdm_items x
				join mfr_replications_products p on p.extern_id = x.extern_item_id

	-- UNIT_NAME
		-- auto-insert
			set @seed = isnull((select max(unit_id) from products_units), 0)
			insert into products_units(unit_id, name)
			select @seed + (row_number() over (order by unit_name)), u.unit_name
			from (
				select distinct x.unit_name
				from #pdm_items x
				where not exists(select 1 from products_units where name = x.unit_name)
				) u

	-- MOLS_POSTS
		insert into mols_posts(subject_id, name, extern_id, rate_price)
		select @subjectid, post_name, max(post_extern_id), max(rate_price) from #pdm_opers_executors x
		where not exists(select 1 from mols_posts where name = x.post_name)
			and not exists(select 1 from mols_posts where extern_id = x.post_extern_id)
		group by post_name

		update x set post_id = xx.post_id
		from #pdm_opers_executors x
			join mols_posts xx on xx.subject_id = @subjectid and xx.extern_id = x.post_extern_id

		update x set post_id = xx.post_id
		from #pdm_opers_executors x
			join mols_posts xx on xx.subject_id = @subjectid and xx.name = x.post_name
		where x.post_id is null

	-- MFR_RESOURCES
		insert into mfr_resources(name, extern_id)
		select resource_name, max(resource_extern_id)
		from #pdm_opers_resources x
		where isnull(resource_name,'') != ''
			and not exists(select 1 from mfr_resources where name = x.resource_name)
			and not exists(select 1 from mfr_resources where extern_id = x.resource_extern_id)
		group by resource_name

		-- sync name
		update x set name = resource_name
		from mfr_resources x
			join (
				select resource_name, extern_id = max(resource_extern_id)
				from #pdm_opers_resources
				group by resource_name
			) xx on xx.extern_id = x.extern_id
		where name != resource_name

		update x set resource_id = xx.resource_id
		from #pdm_opers_resources x
			join mfr_resources xx on xx.extern_id = x.resource_extern_id

		update x set resource_id = xx.resource_id
		from #pdm_opers_resources x
			join mfr_resources xx on xx.name = x.resource_name
		where x.resource_id is null
		
	-- MFR_ITEMS_TYPES
		update x set item_type_id = isnull(xx.type_id, 0)
		from #pdm_items x
			left join mfr_items_types xx on xx.name = x.item_type
end
GO

-- update cisp_gate..packs set processedon = null where packid = 909809
-- update cisp_gate..packs set processedon = null where PackId = 708185
-- exec mfr_replicate_pdms @mol_id = 1000, @trace = 1
