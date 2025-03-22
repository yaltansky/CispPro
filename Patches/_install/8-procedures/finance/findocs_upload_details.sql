if object_id('findocs_upload_details') is not null drop procedure findocs_upload_details
go
create procedure findocs_upload_details
/*
	Детализация оплат-приходов на основании транзитных оплат-расходов.
	Данные детализации оплат-расходов предварительно загружаются из xlsx-файла 1С.
	
	Пример схемы транзитного платежа:
		1. Расход по субъекту ЭМ, контрагент "Русэлпром"
		2. Приход по субъекту УК, контрагент "Русэлпром Электрические машины"
*/
	@mol_id int = 0, -- used to identify user's buffer
	@mode int, -- 1 - get info, 2 - prepare, 3 - process
	@trace bit = 0
as
begin

	set nocount on;

	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @echo = @trace, @trace_id = @tid out

	declare @tid_msg varchar(100) = concat(@proc_name, '.params: ', 
		'mol_id=', @mol_id,
		', mode_id=', @mode
		)
	exec tracer_log @tid, @tid_msg

exec tracer_log @tid, '#targets (приходы на УК)'
	create table #targets(findoc_id int primary key, subject_id int, d_doc datetime, value_ccy decimal(18,2))
		create index ix_targets on #targets(value_ccy, d_doc)

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)

	if @mode = 3
	begin
		insert into #targets(findoc_id, subject_id, d_doc, value_ccy)
		select x.findoc_id, x.subject_id, x.d_doc, x.value_ccy
		from findocs x
			join objs_folders_details fd on fd.folder_id = @buffer_id and fd.obj_type = 'fd' and fd.obj_id = x.findoc_id

		if (select count(distinct subject_id) from #targets) > 1
		begin
			raiserror('В буфере должны быть оплаты по одному субъекту учёта.', 16, 1)
			return
		end

		declare @objects as app_objects
		insert into @objects exec findocs_reglament_getobjects @mol_id = @mol_id, @for_update = 1

		declare @subject_id int, @subject_name varchar(50)
			select @subject_id = subject_id, @subject_name = name
			from subjects
			where subject_id = (select top 1 subject_id from #targets)

		if not exists(select 1 from @objects where obj_type = 'sbj' and obj_id = @subject_id)
		begin
			raiserror('У Вас нет прав для модерации по субъекту учёта "%s". Обратитесь к администратору системы.', 16, 1, @subject_name)
			return
		end

		if exists(
			select d1.findoc_id
			from findocs_upload_details1 d1
				join findocs_upload_details2 d2 on d2.PayId = d1.PayId
			where d1.findoc_id is not null
			group by d1.findoc_id
			having count(distinct d1.PayId) > 1
			)
		begin
			raiserror('Есть дубликаты по полям: Дата, Сумма. Необходимо удалить дубликаты в Excel-файле и обработать дубликаты вручную.', 16, 1)
			return
		end

		exec tracer_log @tid, 'mapping IDs (расход должен быть ранее прихода)	'
		update x
		set duplicated = 1
		from findocs_upload_details1 x
			join (
				select o.valueccy, o.docdate
				from findocs_upload_details1 o
					join #targets i on i.value_ccy = o.valueccy and o.docdate between i.d_doc and i.d_doc
				group by o.valueccy, o.docdate
				having count(distinct i.findoc_id) > 1
			) d on d.ValueCcy = x.ValueCcy and d.DocDate = x.DocDate

		update o
		set findoc_id = i.findoc_id
		from findocs_upload_details1 o
			join #targets i on i.value_ccy = o.valueccy and o.docdate between i.d_doc and i.d_doc
		where o.duplicated = 0

		if exists(
			select 1 from #targets
			where findoc_id not in (select findoc_id from findocs_upload_details1 where findoc_id is not null)
			)
		begin
			raiserror('В буфере есть операции, которые не идентифицированы с файлом Excel.', 16, 1)
			return
		end
	end

exec tracer_log @tid, 'mapping article_id'
	if @mode = 2
	begin
		update x
		set article_id = a.article_id
		from findocs_upload_details2 x
			join findocs_upload_details_map m on m.from_article_name = x.articlename
				join bdr_articles a on a.short_name = m.to_article_name
					join subjects s on s.subject_id = a.subject_id and s.short_name = x.mfrname
		where x.article_id is null

		update x
		set article_id = a.article_id
		from findocs_upload_details2 x
			join findocs_upload_details_map m on m.from_article_name = x.articlename
				join bdr_articles a on a.name = m.to_article_name
		where x.article_id is null

		update x
		set article_id = a.article_id
		from findocs_upload_details2 x
			join bdr_articles a on a.short_name = x.articlename
				join subjects s on s.subject_id = a.subject_id and s.short_name = x.mfrname
		where x.article_id is null

		update x
		set article_id = a.article_id
		from findocs_upload_details2 x
			join bdr_articles a on a.name = x.articlename
		where x.article_id is null
	end	

exec tracer_log @tid, 'upload details'

BEGIN TRY
BEGIN TRANSACTION

	create table #process(findoc_id int index ix_findoc, PayId int index ix_pay)
	
	insert into #process 
		select distinct d1.findoc_id, d1.PayId
		from findocs_upload_details1 d1
			join findocs_upload_details2 d2 on d2.PayId = d1.PayId
		where d1.findoc_id is not null

	if @mode = 3
	begin
		exec tracer_log @tid, '   delete from findocs_details'
		
		delete from findocs_details where findoc_id in (select findoc_id from #process)

		exec tracer_log @tid, '   insert into findocs_details'
		insert into findocs_details(findoc_id, budget_id, article_id, value_ccy, value_rur, note, update_date, update_mol_id)
		select d1.findoc_id, 33, isnull(d2.article_id,0), d2.valueccy, d2.valueccy,
			case
				when d2.article_id is null then d2.ArticleName + ' (' + d2.MfrName +')'
			end,
			getdate(), @mol_id
		from findocs_upload_details1 d1
			join findocs_upload_details2 d2 on d2.PayId = d1.PayId
			join #process x on x.payid = d1.PayId

		if exists(
			select 1
			from findocs_details d
				join findocs f on f.findoc_id = d.findoc_id
				join #process x on x.findoc_id = d.findoc_id
			group by f.findoc_id, f.value_ccy
			having cast(f.value_ccy - sum(d.value_ccy) as decimal) <> 0
			)
		begin
			if @trace = 1
			begin
				declare @err_findocs as app_pkids
					insert into @err_findocs
					select distinct f.findoc_id
					from findocs_details d
						join findocs f on f.findoc_id = d.findoc_id
						join #process x on x.findoc_id = d.findoc_id
					group by f.findoc_id, f.value_ccy
					having cast(f.value_ccy - sum(d.value_ccy) as decimal) <> 0

				select * from findocs where findoc_id in (select id from @err_findocs)

				select * from findocs_upload_details1 where PayId in (
					select payId from #process where findoc_id in (select id from @err_findocs)
					)

				select payid, sum(ValueCcy) from findocs_upload_details2 where PayId in (
					select payId from #process where findoc_id in (select id from @err_findocs)
					)
				group by payid

			end

			raiserror('Есть операции, в которых есть несоответствие итоговой суммы с детализацией.', 16, 1)
		end

		update x
		set ProcessedDate = getdate(),
			ProcessedUserId = @mol_id
		from findocs_upload_details1 x
			join #process p on p.findoc_id = x.findoc_id

		-- 	change buffer
		delete from objs_folders_details where folder_id = @buffer_id
		
		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select @buffer_id, 'fd', findoc_id, @mol_id
		from #process
	end

	select
		-- header
		CreatedUserName = (select name from mols where mol_id = (select top 1 CreatedUserId from findocs_upload_details1)),
		CreatedDate = (select max(CreatedDate) from findocs_upload_details1),
		ProcessedUserName = (select name from mols where mol_id = (select top 1 ProcessedUserId from findocs_upload_details1)),
		ProcessedDate = (select max(ProcessedDate) from findocs_upload_details1),		
		CreatedDate = (select max(CreatedDate) from findocs_upload_details1),
		-- Source
		CountSource = (select count(*) from findocs_upload_details1),
		CountSourceProcessed = (select count(*) from #process),
		-- Duplicates
		CountSourceDuplicates = (select count(*) from findocs_upload_details1 where Duplicated = 1),
		SourceDuplicates = dbo.xml2json(
			(select PayId, DocDate, Number, ValueCcy from findocs_upload_details1 where Duplicated = 1 for xml raw)
			),
		-- Undefined
		CountSourceUndefined = (
			select count(*) 
			from findocs_upload_details1 x
			where exists(select 1 from findocs_upload_details2 where PayId = x.PayId and article_id is null)
			),
		SourceUndefined = dbo.xml2json((
			select 
				row_number() over (order by (select 1)) as Id,
				*
			from (
				select distinct ArticleName, MfrName
				from findocs_upload_details2
				where article_id is null
					and MfrName is not null
				) x
			for xml raw
			)),
		-- Unprocessed
		CountSourceUnprocessed = (select count(*) from findocs_upload_details1 where findoc_id is null),
		SourceUnprocessed = dbo.xml2json(
			(select PayId, DocDate, Number, ValueCcy from findocs_upload_details1 where findoc_id is null for xml raw)
			),
		-- target
		CountTarget = (select count(*) from #targets),
		CountTargetProcessed = (
			select count(*)
			from #targets t
				join #process p on p.findoc_id = t.findoc_id 
			),
		CountTargetUndefined = (select count(*) from findocs where findoc_id in (select findoc_id from #targets) and status_id = 0)

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max) set @err = error_message()
	raiserror (@err, 16, 1)
END CATCH

	if object_id('tempdb.dbo.#targets') is not null drop table #targets
	exec tracer_close @tid

end
go
