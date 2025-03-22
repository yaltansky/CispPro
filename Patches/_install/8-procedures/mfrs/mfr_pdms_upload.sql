if object_id('mfr_pdms_upload') is not null drop proc mfr_pdms_upload
go
create proc mfr_pdms_upload
	@mol_id int,
	@group_id uniqueidentifier
as
begin
	set nocount on;

	-- tables
		create table #pdm(
			upload_id int,
			extern_id int identity primary key,
      VersionNo varchar(30),
			DrawingNo varchar(255),
			PdmItemName varchar(255),
			PdmItemType varchar(100),
			PdmItemWeight varchar(100),
			BaseUnitName varchar(30),
			DocsData xml,
			ItemsData xml,
			--
			pdm_id int index ix_pdm,
			item_id int,
			item_name varchar(255)
			)
		create table #pdm_docs(
		 	extern_pdm_id int,
			pdm_doc_id int,
			RowId int identity primary key,
			DocVersionNo varchar(30),
			FileName nvarchar(255),
			Url nvarchar(max)
			)
		create table #pdm_options(
			extern_pdm_id int,
			extern_id varchar(50),
			pdm_option_id int,
			group_name varchar(50),
			name varchar(255)
			)
		create table #pdm_items(
		 	extern_pdm_id int,
			RowId int identity primary key,
			OptionType varchar(50),
			OptionId varchar(50),
			ItemType varchar(255),
			ParentDrwPosNo varchar(50),
			DrwPosNo varchar(50),
			DrawingNo varchar(255) index ix_drawing,
			ItemName varchar(255),
			ItemVersionNo varchar(30),
			ItemDescription varchar(255),
			UnitName varchar(50),
			QNetto float,
			UnitNameKoeff varchar(50),
			Qkoeff float,
			ExternalId varchar(255) index ix_external,
    	ItemWeight varchar(50),
			-- идентификация
			id int,
			parent_id int,
			pdm_option_id int,
			item_type_id int,
			item_id int,
			item_name varchar(500)
			)

	-- parse xml
		declare c_uploads cursor local read_only for 
			select upload_id from mfr_pdms_uploads where group_id = @group_id
		
		declare @upload_id int
		
		open c_uploads; fetch next from c_uploads into @upload_id
			while (@@fetch_status != -1)
			begin
				if (@@fetch_status != -2) exec mfr_pdms_upload;2 @upload_id
				fetch next from c_uploads into @upload_id
			end
		close c_uploads; deallocate c_uploads

	-- process #-tables
		if not exists(select 1 from mfr_pdms_uploads where group_id = @group_id and errors is not null) 
		begin
			exec mfr_pdms_upload;10 @mol_id = @mol_id
		end
		
		exec drop_temp_table '#pdm,#pdm_docs,#pdm_options,#pdm_items'

	select * from mfr_pdms_uploads where group_id = @group_id
end
go
-- helper: parse xml
create procedure mfr_pdms_upload;2
	@upload_id int
as
begin
	declare @data xml = (select data from mfr_pdms_uploads where upload_id = @upload_id)

	-- #pdm
		insert into #pdm(
			upload_id, DrawingNo, PdmItemName, PdmItemType, VersionNo, PdmItemWeight, BaseUnitName, DocsData, ItemsData
			)
		select
			@upload_id,
			DrawingNo     = x.data.value('@DrawingNo', 'varchar(255)'),
			PdmItemName   = x.data.value('@PdmItemName', 'varchar(255)'),
			PdmItemType   = x.data.value('@PdmItemType', 'varchar(255)'),
			VersionNo     = x.data.value('@VersionNo', 'varchar(255)'),
			PdmItemWeight = x.data.value('@ItemWeight', 'varchar(255)'),
			BaseUnitName  = x.data.value('@BaseUnitName', 'varchar(255)'),
			DocsData  	  = x.data.query('./Docs'),
			ItemsData 	  = x.data.query('./Items')
			from (
				select DataValue = x.data.query('./*')
					from (
					select DataValue = x.data.query('./*')
						from (
						select DataValue = @data
						) f cross apply f.DataValue.nodes('/PdmData') x(data)
					) f cross apply f.DataValue.nodes('/Products') x(data)
				) f cross apply f.DataValue.nodes('/PdmProductData') x(data)
	
	-- документы
		insert into #pdm_docs(extern_pdm_id, [FileName], DocVersionNo, [Url])
		select
		  h.extern_id,
			[FileName] = d.data.value('@FileName', 'nvarchar(255)'),
			VersionNo  = d.data.value('@VersionNo', 'varchar(255)'),
			[Url]      = d.data.value('@Url', 'nvarchar(max)')
		from #pdm h
			cross apply h.DocsData.nodes('/Docs/PdmDocData') d(data)
		where h.upload_id = @upload_id

	-- спецификации
		insert into #pdm_items(
			extern_pdm_id, OptionType, OptionId, ItemType, ParentDrwPosNo, DrwPosNo, DrawingNo, 
            ItemName, ItemVersionNo, ItemWeight, ItemDescription, UnitName, QNetto, UnitNameKoeff, Qkoeff, ExternalId
			)
		select
			h.extern_id,
			OptionType      = d.data.value('@OptionType', 'varchar(255)'),
			OptionId        = d.data.value('@OptionId', 'varchar(255)'),
			ItemType        = d.data.value('@ItemType', 'varchar(255)'),
			ParentDrwPosNo  = d.data.value('@ParentPosNo', 'varchar(255)'),
			DrwPosNo        = d.data.value('@PosNo', 'varchar(255)'),
			DrawingNo       = d.data.value('@DrawingNo', 'varchar(255)'),
			ItemName        = d.data.value('@ItemName', 'varchar(255)'),
			ItemVersionNo   = d.data.value('@VersionNo', 'varchar(255)'),
      ItemWeight      = d.data.value('@ItemWeight', 'varchar(255)'),
			ItemDescription = d.data.value('@Description', 'varchar(255)'),
			UnitName        = d.data.value('@UnitName', 'varchar(255)'),
			QNetto          = cast(replace(d.data.value('@Q', 'varchar(255)'), 'х', '') as float),
			UnitNameKoeff   = d.data.value('@UnitNameKoeff', 'varchar(255)'),
			Qkoeff          = cast(d.data.value('@Qkoeff', 'varchar(255)') as float),
			ExternalId      = d.data.value('@ExternalId', 'varchar(255)')
		from #pdm h
			cross apply h.ItemsData.nodes('/Items/PdmItemData') d(data)
		where h.upload_id = @upload_id
		order by right('00000000000' + d.data.value('@PosNo', 'varchar(255)'), 10)

	-- ошибки
		update mfr_pdms_uploads set errors = (
			select error + '; '  [text()] from (
				select error = d.data.value('(text())[1]', 'varchar(255)')
				from @data.nodes('*/Errors/string') d(data)
			) x
			for xml path('')
			)
		where upload_id = @upload_id
end
go
-- helper: process data
create procedure mfr_pdms_upload;10
	@mol_id int
as
begin

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

	-- print 'addon'
		declare @proc_addon sysname = 'mfr_pdms_upload_addon'
		if object_id(@proc_addon) is not null
		begin
			set @proc_addon = 'exec ' + @proc_addon
			exec sp_executesql @proc_addon
		end

	-- print '#pdm_options'
		insert into #pdm_options(extern_pdm_id, extern_id, group_name, name)
		select distinct extern_pdm_id, OptionId, OptionType, concat(OptionType, ' #', OptionId) 
		from #pdm_items
		where OptionId is not null

	-- print 'seeds'
		declare @seed int

		-- print '#pdm'
            update x set pdm_id = pdm.pdm_id
            from #pdm x
                join mfr_pdms pdm on pdm.item_id = x.item_id and pdm.version_number = x.versionno

			set @seed = isnull((select max(pdm_id) from mfr_pdms), 0)

			update x
			set pdm_id = @seed + xx.id
			from #pdm x
				join (
					select row_number() over (order by extern_id) as id, extern_id
					from #pdm
				) xx on xx.extern_id = x.extern_id
			where x.pdm_id is null


		-- print '#pdm_docs'
			set @seed = isnull((select max(pdm_doc_id) from mfr_pdm_docs), 0)

			update x
			set pdm_doc_id = @seed + xx.id
			from #pdm_docs x
				join (
					select row_number() over (order by extern_pdm_id, FileName) as id,
						extern_pdm_id,
						[FileName]
					from #pdm_docs
				) xx on xx.extern_pdm_id = x.extern_pdm_id and xx.[FileName] = x.[FileName]

		-- print '#pdm_options'
			set @seed = isnull((select max(pdm_option_id) from mfr_pdm_options), 0)

			update x
			set pdm_option_id = @seed + xx.id
			from #pdm_options x
				join (
					select row_number() over (order by extern_pdm_id, extern_id) as id,
						extern_pdm_id,
						extern_id
					from #pdm_options
				) xx on xx.extern_pdm_id = x.extern_pdm_id and xx.extern_id = x.extern_id

			update x set pdm_option_id = o.pdm_option_id
			from #pdm_items x
				join #pdm_options o on o.extern_pdm_id = x.extern_pdm_id and o.extern_id = x.OptionId

		-- print '#pdm_items'
			set @seed = isnull((select max(id) from mfr_pdm_items), 0)
			update #pdm_items set id = @seed + RowId

			update x set parent_id = pp.id
			from #pdm_items x
				join #pdm_items pp on pp.extern_pdm_id = x.extern_pdm_id
					and pp.DrwPosNo = x.ParentDrwPosNo

    -- print 'check identify products'
        declare @names table(name varchar(500), upload_id int)
            insert into @names(upload_id, name)
            select distinct upload_id, item_name
            from (
                select upload_id, item_name from #pdm where item_id is null
                UNION ALL
                select p.upload_id, i.item_name from #pdm_items i
                    join #pdm p on p.extern_id = i.extern_pdm_id
                where i.item_id is null
                ) x
            
        if exists(select 1 from @names)
        begin
            update x set errors = 'Требуется провести сопоставление справочников номенклатуры.'
            from mfr_pdms_uploads x
                join (
                    select distinct upload_id from @names
                 ) n on n.upload_id = x.upload_id

            insert into products_maps(slice, name)
			select distinct 'pdm', name
			from @names x
            where not exists(select 1 from products_maps where slice = 'pdm' and name = x.name)

            return
        end

	BEGIN TRY
	BEGIN TRANSACTION
		-- print 'dictionary'
			exec mfr_pdms_upload;20 @mol_id

		-- print 'mfr_pdms'
            -- delete olds
            delete from mfr_pdms where pdm_id in (select pdm_id from #pdm where pdm_id is not null)
            delete from mfr_pdm_items where pdm_id in (select pdm_id from #pdm where pdm_id is not null)

			SET IDENTITY_INSERT MFR_PDMS ON;

				insert into mfr_pdms(		
					pdm_id, item_id, number, version_number, item_weight, unit_name, status_id, d_doc, add_mol_id
					)
				select
					h.pdm_id, h.item_id, h.DrawingNo, h.VersionNo, h.PdmItemWeight, isnull(u1.name, h.BaseUnitName), 0, dbo.today(), @mol_id
				from #pdm h left join products_units u on (h.BaseUnitName = u.name)
                    left join products_units u1 on (u.main_id = u1.unit_id)

				exec objs_buffer_clear @mol_id, 'mfpdm'

				insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
				select @buffer_id, 'mfpdm', pdm_id, 0
				from #pdm
			
			SET IDENTITY_INSERT MFR_PDMS OFF;
		
		-- print 'mfr_pdm_docs'
			SET IDENTITY_INSERT MFR_PDM_DOCS ON;
			
                delete x from mfr_pdm_docs x where pdm_id in (select pdm_id from #pdm where pdm_id is not null)
                    and exists(select 1 from #pdm_docs where pdm_id = x.pdm_id)

				insert into mfr_pdm_docs(pdm_id, pdm_doc_id, doc_version, name, url)
				select h.pdm_id, d.pdm_doc_id, d.DocVersionNo, d.[FileName], d.Url
				from #pdm_docs d
					join #pdm h on h.extern_id = d.extern_pdm_id

			SET IDENTITY_INSERT MFR_PDM_DOCS OFF;

		-- print 'mfr_pdm_options'
			SET IDENTITY_INSERT MFR_PDM_OPTIONS ON;
			
				insert into mfr_pdm_options(pdm_id, pdm_option_id, extern_id, group_name, name)
				select h.pdm_id, d.pdm_option_id, d.extern_id, d.group_name, d.name
				from #pdm_options d
					join #pdm h on h.extern_id = d.extern_pdm_id

			SET IDENTITY_INSERT MFR_PDM_OPTIONS OFF;

		-- print 'mfr_pdm_items'
			SET IDENTITY_INSERT MFR_PDM_ITEMS ON;

				insert into mfr_pdm_items(
					id, parent_id,
					pdm_id,
					pdm_option_id,
					item_type_id, item_id, numpos, item_version,
					unit_name, q_brutto, q_netto
					)
				select
					d.id, d.parent_id,
					h.pdm_id,
					pdm_option_id,
					item_type_id, d.item_id, d.DrwPosNo, d.ItemVersionNo,
					isnull(u1.name, d.UnitName), d.QNetto, d.QNetto
				from #pdm_items d
					join #pdm h on h.extern_id = d.extern_pdm_id
          left join products_units u on (d.UnitName = u.name)
          left join products_units u1 on (u.main_id = u1.unit_id)
				order by h.pdm_id, d.DrwPosNo

			SET IDENTITY_INSERT MFR_PDM_ITEMS OFF;

	COMMIT TRANSACTION
	END TRY	

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max) = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION
end
go
-- helper: auto-dictionary
create procedure mfr_pdms_upload;20
	@mol_id int
as
begin
	
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

	-- products_units
		declare @seed int = isnull((select max(unit_id) from products_units), 0)
		insert into products_units(unit_id, name)
		select 
            @seed + (row_number() over (order by name)), name
        from (
            select distinct u.name
            from (
                select name = UnitName from #pdm_items where UnitName is not null
                union all select UnitNameKoeff from #pdm_items where UnitNameKoeff is not null
                ) u
            where not exists(select 1 from products_units where name = u.name)
            ) u
	
	-- -- products
	-- 	-- auto-insert
	-- 	insert into products(name, name_print, status_id)
	-- 	select distinct item_name, item_name, 0
	-- 	from #pdm
	-- 	where item_name is not null

	-- 	insert into products(name, name_print, status_id, unit_id)
	-- 	select distinct x.item_name, x.item_name, 0, u.unit_id
	-- 	from #pdm_items x
	-- 		join products_units u on u.name = x.unitname
	-- 	where x.item_name is not null

	-- 	-- back updates
	-- 	update x set item_id = p.product_id
	-- 	from #pdm x
	-- 		join products p on p.name = x.item_name

	-- 	update x set item_id = p.product_id
	-- 	from #pdm_items x
	-- 		join products p on p.name = x.item_name

	-- 	exec objs_buffer_clear @mol_id, 'pdm'

	-- 	insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
	-- 	select distinct @buffer_id, 'p', item_id, 0 
	-- 	from (
	-- 		select item_id from #pdm where item_name is not null
	-- 		union select distinct item_id from #pdm_items where item_name is not null
	-- 		) u

	-- mfr_items_types
		update x set item_type_id = isnull(xx.type_id, 0)
		from #pdm_items x
			left join mfr_items_types xx on xx.name = x.ItemType
end
go

-- truncate table mfr_pdms_uploads
-- select * from mfr_pdms_uploads
-- exec mfr_pdms_upload 1000, 'a2c07eaa-c07c-407e-b0e0-cf677ebffe9f'
-- delete from products_maps
