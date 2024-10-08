if object_id('app_export') is not null drop proc app_export
go
create proc app_export
  @group_id uniqueidentifier
as
begin
	set nocount on;

  -- build xml
		declare c_exports cursor local read_only for 
			select export_id from app_exports where group_id = @group_id
		
		declare @export_id int
		
		open c_exports; fetch next from c_exports into @export_id
			while (@@fetch_status != -1)
			begin
				if (@@fetch_status != -2) exec app_export;2 @export_id
				fetch next from c_exports into @export_id
			end
		close c_exports; deallocate c_exports

  -- results
    select * from app_exports where group_id = @group_id
end
GO
CREATE proc [app_export];2
  @export_id int
as
begin
	set nocount on;

  -- параметры
    declare
      @date_from date,
      @date_to date,
      @folder_id int,
      @obj_type varchar(20)

      select
        @date_from = d_from,
        @date_to = d_to,
        @folder_id = folder_id,
        @obj_type = obj_type
      from app_exports
      where export_id = @export_id 

    declare @result table(data xml)

  -- материалы: поступление на склад
    if (@obj_type = 'SD') 
      insert into @result
      exec app_export;20 @export_id, @date_from, @date_to, @folder_id

  -- материалы: выдача в производство
    if (@obj_type = 'MFTRF') 
      insert into @result
      exec app_export;30 @export_id, @date_from, @date_to, @folder_id

  -- табельное время
    if (@obj_type = 'MFW') 
      insert into @result
      exec app_export;50 @export_id, @date_from, @date_to, @folder_id

  -- save result
    update app_exports set data = (select top 1 data from @result)
    where export_id = @export_id
end
GO
-- материалы: выдача в производство
CREATE procedure [app_export];3
  @date_from date = null,
  @date_to date = null,
  @folder_id int = null
as
begin
  --
  create table #docs (
    DOC_ID int,
    D_DOC datetime,
    NUMBER varchar(50),
    DIVISION_FROM varchar(50),
    MOL_ID int,
    MOL_NAME varchar(255),
    MOL_EXTERN_ID varchar(100),
    DIVISION_TO varchar(50),
    MOL_TO_ID int,
    MOL_TO_NAME varchar(255),
    MOL_TO_EXTERN_ID varchar(100),
    ACC_REGISTER_NAME varchar(255),
    ACC_REGISTER_NOTE varchar(max),
    NOTE varchar(max)
  )
  create table #docs_details (
    DOC_ID int,
    PRODUCT_ID int,
    ITEM_ID varchar(32),
    ITEM_NAME varchar(500),
    MFR_DOC_NO varchar(50),
    UNIT_NAME varchar(20),
    QUANTITY float
  )

  --
  if (@folder_id is not null) begin
    insert into #filter_objs (obj_id)
      select OBJ_ID
        from CISP_SEZ..OBJS_FOLDERS_DETAILS
        where (FOLDER_ID = @folder_id)
  end else begin
    insert into #filter_objs (obj_id)
      select obj_id = DOC_ID
        from CISP_SEZ..SDOCS h
        where
          ([TYPE_ID] = 12) and
          (D_DOC between @date_from and @date_to)
  end

  -- список документов
  insert into #docs (DOC_ID, D_DOC, NUMBER, DIVISION_FROM, MOL_ID, MOL_NAME, MOL_EXTERN_ID, DIVISION_TO, MOL_TO_ID, MOL_TO_NAME, MOL_TO_EXTERN_ID, NOTE)
    select
        h.DOC_ID, h.D_DOC, h.NUMBER,
        DIVISION_FROM = p1.NAME,
        MOL_ID        = m1.MOL_ID,
        MOL_NAME      = m1.SURNAME +
                         case when (nullif(m1.NAME1, '') is null) then '' else ' ' + m1.NAME1 end +
                         case when (nullif(m1.NAME2, '') is null) then '' else ' ' + m1.NAME2 end,
        MOL_EXTERN_ID = m1.TAB_NUMBER,
        DIVISION_TO   = p2.NAME,
        MOL_TO_ID     = m2.MOL_ID,
        MOL_TO_NAME   = m2.SURNAME +
                         case when (nullif(m2.NAME1, '') is null) then '' else ' ' + m2.NAME1 end +
                         case when (nullif(m2.NAME2, '') is null) then '' else ' ' + m2.NAME2 end,
        MOL_TO_EXTERN_ID = m2.TAB_NUMBER,
        NOTE          = h.NOTE
      from
        CISP_SEZ..SDOCS h
          left join CISP_SEZ..MFR_PLACES p1 on (h.PLACE_ID = p1.PLACE_ID)
          left join CISP_SEZ..MOLS m1 on (h.MOL_ID = m1.MOL_ID)
          left join CISP_SEZ..MFR_PLACES p2 on (h.PLACE_TO_ID = p2.PLACE_ID)
          left join CISP_SEZ..MOLS m2 on (h.MOL_TO_ID = m2.MOL_ID)
          -- фильтр по папке
          inner join #filter_objs f on (h.DOC_ID = f.obj_id)
      where
        (h.[TYPE_ID] = 12) and
        (h.EXTERN_ID is null)

  -- табличная часть
  insert into #docs_details (DOC_ID, PRODUCT_ID, ITEM_ID, ITEM_NAME, MFR_DOC_NO, UNIT_NAME, QUANTITY)
    select h.DOC_ID, p.PRODUCT_ID, e.ITEM_ID, ITEM_NAME = ltrim(rtrim(p.NAME)), MFR_DOC_NO = d.MFR_NUMBER, UNIT_NAME = u.NAME, d.QUANTITY
      from
        #docs h
          inner join CISP_SEZ..SDOCS_PRODUCTS d on (h.DOC_ID = d.DOC_ID)
          inner join CISP_SEZ..PRODUCTS p on (d.PRODUCT_ID = p.PRODUCT_ID)
          left join (
            select e.PRODUCT_ID, ITEM_ID = right(ltrim(rtrim(e.EXTERN_ID)), len(ltrim(rtrim(e.EXTERN_ID))) - charindex('-', ltrim(rtrim(e.EXTERN_ID))))
              from CISP_SEZ..MFR_REPLICATIONS_PRODUCTS e
              group by e.PRODUCT_ID, right(ltrim(rtrim(e.EXTERN_ID)), len(ltrim(rtrim(e.EXTERN_ID))) - charindex('-', ltrim(rtrim(e.EXTERN_ID))))
          ) e on (p.PRODUCT_ID = e.PRODUCT_ID)
          inner join PRODUCTS_UNITS u on (d.UNIT_ID = u.UNIT_ID)

  -- залечим ITEM_ID из названия
  update d set d.ITEM_ID = substring(d.ITEM_NAME, 2, charindex(']', d.ITEM_NAME) - 2)
    from #docs_details d
    where
      (d.ITEM_ID is null) and
      (left(d.ITEM_NAME, 1) = '[')

  -- исправим названия
  update d set
      d.ITEM_ID   = case when (left(d.ITEM_ID, 1) = 'm')
                      then replace(d.ITEM_ID, 'm', '')
                      else d.ITEM_ID
                    end,
      d.ITEM_NAME = replace(d.ITEM_NAME, '[' + d.ITEM_ID + '] ', '')
    from #docs_details d

  -- выгрузим в xml
  update t set t.result =
    (
    select
        [@Источник]     = 'CISP_SEZ',
        [@Организация]  = 'СЭЗ',
        [@Агент]        = 'CISP',
        [@ВерсияАгента] = '1',
        [@Запрос]       = null,  -- TODO: вернуть id запроса из log таблицы
        [@Папка]        = convert(varchar(10), @FOLDER_ID, 104),
        (-- документы
         select (
           select
               [@ДокументКод]     = h.DOC_ID,
               [@ДокументДата]    = convert(varchar(10), h.D_DOC, 104),
               [@ДокументНомер]   = h.NUMBER,
               [@ДокументТип]     = 'Выдача материала в производство',
               [@Примечание]      = h.NOTE,
               [@ПодразделениеИз] = h.DIVISION_FROM,
               [@КладовщикИз]     = h.MOL_NAME,
               [@КладовщикИзТаб]  = h.MOL_EXTERN_ID,
               [@ПодразделениеВ]  = h.DIVISION_TO,
               [@КладовщикВ]      = h.MOL_TO_NAME,
               [@КладовщикВТаб]   = h.MOL_TO_EXTERN_ID,
               (-- табличная часть
                select (
                  select
                      [@ProductId]      = d.PRODUCT_ID,
                      [@Код]            = d.ITEM_ID,
                      [@Наименование]   = d.ITEM_NAME,
                      [@Заказ]          = d.MFR_DOC_NO,
                      [@ЕдИзм]          = d.UNIT_NAME,
                      [@КоличествоФакт] = cast(d.QUANTITY as decimal(19,6))
                    from #docs_details d
                    where (h.DOC_ID = d.DOC_ID)
                    FOR XML PATH('Строка'), TYPE
                ) FOR XML PATH('Строки'), TYPE
               )
             from #docs h
             FOR XML PATH('Документ'), TYPE
         ) FOR XML PATH('Документы'), TYPE
        )
      FOR XML PATH('Сообщение')
    )
    from #result t

  --
  drop table
    #docs, #docs_details
end
GO
-- материалы: поступление на склад
CREATE procedure [app_export];20
  @export_id int,
  @date_from date = null,
  @date_to date = null,
  @folder_id int = null
as
begin
  declare @subjectId int = 30
  declare @subjectPrefix varchar(10) = concat(@subjectId, '-')
  declare @objs app_pkids

  -- tables
    create table #docs (
      doc_id int primary key,
      d_doc datetime,
      number varchar(50),
      note varchar(max),
      agent_name varchar(500),
      agent_inn varchar(50),
      d_doc_ext datetime,
      mol_to_id int,
      mol_to_name varchar(255),
      mol_to_extern_id varchar(100),
      acc_register_name varchar(255),
      acc_register_note varchar(max)
      )
    create table #docs_details (
      doc_id int,
      product_id int,
      item_id varchar(32),
      item_name varchar(500),
      mfr_number varchar(50),
      unit_name varchar(20),
      quantity float,
      sum_pc float,
      sum_pct float
      )

  -- @objs
    if (@folder_id is not null) begin
      insert into @objs
      select obj_id
      from objs_folders_details fd
        join sdocs sd on sd.doc_id = fd.obj_id and sd.type_id = 9
      where (folder_id = @folder_id)
        and obj_type = 'SD'

    end else begin
      insert into @objs
        select doc_id from sdocs
        where (type_id = 9) and
            (d_doc between isnull(@date_from,d_doc) and isnull(@date_to, d_doc))
    end

  -- список документов
    insert into #docs(
      doc_id, d_doc, number, note, agent_name, agent_inn, d_doc_ext, mol_to_id, mol_to_name, mol_to_extern_id, acc_register_name, acc_register_note
      )
    select
        h.doc_id, h.d_doc, h.number, h.note, agent_name = a.name, agent_inn = a.inn, h.d_doc_ext,
        h.mol_to_id,
        mol_to_name = concat(m.surname, ' ' + m.name1, ' ' + m.name2),
        mol_to_extern_id = m.tab_number,
        acc_register_name = r.name,
        acc_register_note = r.note
      from
        sdocs h
          left join agents a on (h.agent_id = a.agent_id)
          left join mols m on (h.mol_to_id = m.mol_id)
          left join accounts_registers r on (h.acc_register_id = r.acc_register_id)
          -- фильтр по документам
          join @objs f on (f.id = h.doc_id)

  -- табличная часть
    insert into #docs_details(
      doc_id, product_id, item_id, item_name, mfr_number, unit_name, quantity, sum_pc, sum_pct)
    select
        h.doc_id, p.product_id, item_id = '', item_name = p.name, d.mfr_number,
        unit_name = u.name, d.quantity, sum_pc = d.value_pure, sum_pct = d.value_rur
      from
        #docs h
          join sdocs_products d on (h.doc_id = d.doc_id)
          join products p on (d.product_id = p.product_id)
          join products_units u on (d.unit_id = u.unit_id)

    -- залечим ITEM_ID из названия (конструкторский код)
    update d set d.item_id = substring(d.item_name, 2, charindex(']', d.item_name) - 2)
      from #docs_details d
      where
        (left(d.item_name, 1) = '[')
    -- залечим ITEM_ID из названия (1c-ный код)
    update d set d.item_id = e.extern_id
      from
        #docs_details d
          inner join (
            select e.product_id, extern_id = max(replace(replace(ltrim(rtrim(e.extern_id)), '37-', ''), 'SPB.M1C.', ''))
              from mfr_replications_products e
              group by e.product_id
          ) e on (d.product_id = e.product_id)
      where
        (d.item_id = '') and
        (left(d.item_name, 1) != '[')

    -- исправим названия
    update d set
        d.item_name = replace(d.item_name, '[' + d.item_id + '] ', '')
      from #docs_details d
      where (d.item_id is not null)

  -- выгрузим в xml
  select
    (
    select
        [@Источник]     = db_name(),
        [@Организация]  = 'ЛЭЗ',
        [@Агент]        = 'CISP',
        [@ВерсияАгента] = '1',
        [@Запрос]       = @export_id,
        [@Папка]        = convert(varchar(20), @folder_id, 104),
        (-- документы
         select (
           select
               [@ДокументКод]        = h.doc_id,
               [@ДокументДата]       = convert(varchar(10), h.d_doc, 104),
               [@ДокументНомер]      = h.number,
               [@ДокументТип]        = 'Поступление материала на склад',
               [@ДокументПримечание] = h.note,
               [@Клиент]             = h.agent_name,
               [@КлиентИНН]          = h.agent_inn,
               [@КлиентДата]         = convert(varchar(10), h.d_doc_ext, 104),
               [@Кладовщик]          = h.mol_to_name,
               [@КладовщикТаб]       = h.mol_to_extern_id,
               [@РазделительКод]     = h.acc_register_name,
               [@РазделительПрим]    = h.acc_register_note,
               (-- табличная часть
                select (
                  select
                      [@ProductId]    = d.product_id,
                      [@Код]          = d.item_id,
                      [@Наименование] = d.item_name,
                      [@Заказ]        = d.mfr_number,
                      [@ЕдИзм]        = d.unit_name,
                      [@Количество]   = cast(d.quantity as decimal(19,6)),
                      [@СуммаБНДС]    = cast(d.sum_pc as decimal(19,6)),
                      [@СуммаСНДС]    = cast(d.sum_pct as decimal(19,6))
                    from #docs_details d
                    where (h.doc_id = d.doc_id)
                    for xml path('Строка'), type
                ) for xml path('Строки'), type
               )
             from #docs h
             for xml path('Документ'), type
         ) for xml path('Документы'), type
        )
      for xml path('Сообщение')
    )

  --
  exec drop_temp_table '#docs,#docs_details'
end
GO
-- материалы: выдача в производство
CREATE procedure [app_export];30
  @export_id int,
  @date_from date = null,
  @date_to date = null,
  @folder_id int = null
as
begin
  declare @subjectId int = 30
  declare @subjectPrefix varchar(10) = concat(@subjectId, '-')
  declare @objs app_pkids

  -- tables
    create table #docs (
      doc_id int,
      d_doc datetime,
      number varchar(50),
      division_from varchar(50),
      mol_id int,
      mol_name varchar(255),
      mol_extern_id varchar(100),
      division_to varchar(50),
      mol_to_id int,
      mol_to_name varchar(255),
      mol_to_extern_id varchar(100),
      acc_register_name varchar(255),
      acc_register_note varchar(max),
      note varchar(max)
      )
    create table #docs_details (
      doc_id int,
      product_id int,
      item_id varchar(32),
      item_name varchar(500),
      mfr_doc_no varchar(50),
      unit_name varchar(20),
      quantity float
      )

  -- @objs
    if (@folder_id is not null) begin
      insert into @objs
      select obj_id
      from objs_folders_details
      where (folder_id = @folder_id)
        and obj_type = 'MFTRF'
    end else begin
      insert into @objs
        select obj_id = doc_id
        from sdocs
        where (type_id = 12)
          and (d_doc between isnull(@date_from,d_doc) and isnull(@date_to, d_doc))
    end

  -- список документов
    insert into #docs(
      doc_id, d_doc, number, division_from, mol_id, mol_name, mol_extern_id, division_to, mol_to_id, mol_to_name, mol_to_extern_id, note, acc_register_name, acc_register_note)
    select
        h.doc_id, h.d_doc, h.number,
        division_from = p1.name,
        mol_id        = m1.mol_id,
        mol_name      = concat(m1.surname, ' ' + m1.name1, ' ' + m1.name2),
        mol_extern_id = m1.tab_number,
        division_to   = p2.name,
        mol_to_id     = m2.mol_id,
        mol_to_name   = concat(m2.surname, ' ' + m2.name1, ' ' + m2.name2),
        mol_to_extern_id = m2.tab_number,
        note          = h.note,
        acc_register_name = r.name,
        acc_register_note = r.note
      from
        sdocs h
          left join mfr_places p1 on (h.place_id = p1.place_id)
          left join mols m1 on (h.mol_id = m1.mol_id)
          left join mfr_places p2 on (h.place_to_id = p2.place_id)
          left join mols m2 on (h.mol_to_id = m2.mol_id)
          left join accounts_registers r on (h.acc_register_id = r.acc_register_id)
          -- фильтр по документам
          join @objs f on (h.doc_id = f.id)

  -- табличная часть
    insert into #docs_details (doc_id, product_id, item_id, item_name, mfr_doc_no, unit_name, quantity)
      select h.doc_id, p.product_id, item_id = '', item_name = ltrim(rtrim(p.name)), mfr_doc_no = d.mfr_number, unit_name = u.name, d.quantity
        from
          #docs h
            join sdocs_products d on (h.doc_id = d.doc_id)
            join products p on (d.product_id = p.product_id)
            join products_units u on (d.unit_id = u.unit_id)

    -- залечим ITEM_ID из названия (конструкторский код)
    update d set d.item_id = substring(d.item_name, 2, charindex(']', d.item_name) - 2)
      from #docs_details d
      where
        (nullif(d.item_id, '') is null) and
        (left(d.item_name, 1) = '[')
    -- залечим ITEM_ID из названия (1c-ный код)
    update d set d.item_id = e.extern_id
      from
        #docs_details d
          inner join (
            select e.product_id, extern_id = max(replace(replace(ltrim(rtrim(e.extern_id)), '37-', ''), 'SPB.M1C.', ''))
              from mfr_replications_products e
              group by e.product_id
          ) e on (d.product_id = e.product_id)
      where
        (nullif(d.item_id, '') is null) and
        (left(d.item_name, 1) != '[')

    -- исправим названия
    update d set
        d.item_name = replace(d.item_name, '[' + d.item_id + '] ', '')
      from #docs_details d
      where (d.item_id is not null)


  -- выгрузим в xml
  select
    (
    select
        [@Источник]     = db_name(),
        [@Организация]  = 'ЛЭЗ',
        [@Агент]        = 'CISP',
        [@ВерсияАгента] = '1',
        [@Запрос]       = @export_id,
        [@Папка]        = convert(varchar(20), @folder_id, 104),
        (-- документы
         select (
           select
               [@ДокументКод]     = h.doc_id,
               [@ДокументДата]    = convert(varchar(10), h.d_doc, 104),
               [@ДокументНомер]   = h.number,
               [@ДокументТип]     = 'Выдача материала в производство',
               [@Примечание]      = h.note,
               [@ПодразделениеИз] = h.division_from,
               [@КладовщикИз]     = h.mol_name,
               [@КладовщикИзТаб]  = h.mol_extern_id,
               [@ПодразделениеВ]  = h.division_to,
               [@КладовщикВ]      = h.mol_to_name,
               [@КладовщикВТаб]   = h.mol_to_extern_id,
               [@РазделительКод]  = h.acc_register_name,
               [@РазделительПрим] = h.acc_register_note,
               (-- табличная часть
                select (
                  select
                      [@ProductId]      = d.product_id,
                      [@Код]            = d.item_id,
                      [@Наименование]   = d.item_name,
                      [@Заказ]          = d.mfr_doc_no,
                      [@ЕдИзм]          = d.unit_name,
                      [@КоличествоФакт] = cast(d.quantity as decimal(19,6))
                    from #docs_details d
                    where (h.doc_id = d.doc_id)
                    for xml path('Строка'), type
                ) for xml path('Строки'), type
               )
             from #docs h
             for xml path('Документ'), type
         ) for xml path('Документы'), type
        )
      for xml path('Сообщение')
    )

  --
  exec drop_temp_table '#docs,#docs_details'
end
GO
-- табельное время
CREATE procedure [app_export];50
  @export_id int,
  @date_from date = null,
  @date_to date = null,
  @folder_id int = null
as
begin
  declare @subjectId int = 37
  declare @subjectPrefix varchar(10) = concat(@subjectId, '-')
  declare @objs app_pkids

  -- tables
    create table #data (
      fact_date datetime,
      full_name varchar(400),
      dep_name varchar(255),
      dep_name_full varchar(255),
      mfr_no varchar(150),
      fact_hour decimal(19,3)
    )

  -- @objs
    if (@folder_id is not null) begin
      insert into @objs
      select obj_id
      from objs_folders_details
      where (folder_id = @folder_id)
        and obj_type = 'MFW'
    end 
    
    else begin
      insert into @objs
        select wk_sheet_id
        from mfr_wk_sheets
        where d_doc between isnull(@date_from, d_doc) and isnull(@date_to, d_doc)
    end

  -- реестр данных
    insert into #data (fact_date, full_name, dep_name, dep_name_full, mfr_no, fact_hour)
      select fact_date, full_name, dep_name, dep_name_full, mfr_no, sum(fact_hour)
      from (
        select
            fact_date     = f.d_doc,
            full_name     = ltrim(rtrim(m.surname + ' ' + isnull(m.name1, '') + ' ' + isnull(m.name2, ''))),
            dep_name      = left(isnull(p.name, '---'), 3),
            dep_name_full = p.full_name,
            mfr_no        = h1.number,
            fact_hour     = f.duration_wk * dur.factor / dur_h.factor
        from
            mfr_wk_sheets h
                join mfr_wk_sheets_jobs f on (h.wk_sheet_id = f.wk_sheet_id)
                    join mfr_plans_jobs_details jd on jd.id = f.detail_id
                        join sdocs h1 on (jd.mfr_doc_id = h1.doc_id)
                    join projects_durations dur on dur.duration_id = f.duration_wk_id
                    join projects_durations dur_h on dur_h.duration_id = 2
                join mols m on (f.mol_id = m.mol_id)
                left join (
                    select mol_id, place_id = max(place_id) from mfr_places_mols group by mol_id
                ) e on (m.mol_id = e.mol_id)
                left join mfr_places p on (e.place_id = p.place_id)
                -- фильтр по документам
                join @objs o on (o.id = h.wk_sheet_id)
        where (f.duration_wk is not null)
        ) x
      group by fact_date, full_name, dep_name, dep_name_full, mfr_no

  -- выгрузим в xml
    select
      (
      select
          [@Источник]     = db_name(),
          [@Организация]  = 'ЛЭЗ',
          [@Агент]        = 'CISP',
          [@ВерсияАгента] = '1',
          [@Запрос]       = @export_id,
          [@Папка]        = convert(varchar(20), @folder_id, 104),
          [@Тест]         = 'нет',
          (-- исполнители
            select
                [Дата]            = convert(varchar(10), h.fact_date, 104),
                [Исполнитель]     = h.full_name,
                [Заказ]           = h.mfr_no,
                [ОтработаноЧасов] = h.fact_hour
              from #data h
              for xml path('ИсполнителиГОСЗаказов'), type
          )
        for xml path('Корневой')
      )

  --
  exec drop_temp_table '#data'
end
GO
