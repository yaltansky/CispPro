if object_id('mfr_wk_sheets_replicate') is not null drop proc mfr_wk_sheets_replicate
go
-- exec mfr_wk_sheets_replicate @mol_id = 1000
create proc mfr_wk_sheets_replicate
	@mol_id int,
	@trace bit = 1
as
begin

	set nocount on;

begin
	
	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
		' @mol_id=', @mol_id
		)
	exec tracer_log @tid, @tid_msg
end -- params

begin

	create table #wksheets(
		DocId VARCHAR(50),
		WK_SHEET_ID INT,		
		EXTERN_ID VARCHAR(50) PRIMARY KEY,
		D_DOC DATETIME,
		NUMBER VARCHAR(100),
		SUBJECT_ID INT,
		PLACE_ID INT,
		NOTE VARCHAR(MAX),
		IS_EXTERNAL BIT
		)
		create unique index ix_docid on #wksheets(DocId)

	create table #wksheets_details(
		EXTERN_ID VARCHAR(50) INDEX IX_EXTERN,
		TAB_NUMBER VARCHAR(50),
		MOL_NAME VARCHAR(250),
		POST_NAME VARCHAR(250),
		MOL_ID INT,
		DEPT_ID INT,
		WK_HOURS FLOAT,
		NOTE VARCHAR(MAX),
		PRIMARY KEY (EXTERN_ID, TAB_NUMBER)
	)
	
end -- #tables create

begin
	exec tracer_log @tid, 'Fill #tables'

	insert into #wksheets(
		DocId, extern_id,
		subject_id, place_id,
		d_doc,
		number,
		note,
		is_external
		)
	select 
		h.DocId,
		concat('5.', h.DocId),
		h.subject_id, h.place_id,
		h.DocDate,
		h.DocNo,
		concat(h.DocTypeName, ', автоматически импортировано'),
		case when h.DocTypeName = 'внешние' then 1 end
	from cf..doc_mfr_personsh h
	
	insert into #wksheets_details(
		extern_id,
		tab_number,
		dept_id, mol_id, mol_name, post_name,
		wk_hours
		)
	select
		concat('5.', d.DocId),
		d.EmployeeNumber,
		case
			when sd.is_external = 1 then 5243 -- 000 Внештатные работники
			else d.dept_id
		end,
		d.mol_id,
		d.FullName,
		d.JobTitle,
		d.WorkedTime
	from cf..doc_mfr_personsd d
		join #wksheets sd on sd.DocId = d.DocId

end -- #tables fill

--update mols
--set dept_id = 5243
--where mol_id in (
--	select distinct x.mol_id from #wksheets_details x 
--		join #wksheets h on h.extern_id = x.extern_id
--	where h.is_external = 1
--	)

--return

BEGIN TRY
BEGIN TRANSACTION

begin
	exec tracer_log @tid, 'Seed'

	update x set wk_sheet_id = sd.wk_sheet_id
	from #wksheets x
		join mfr_wk_sheets sd on sd.extern_id = x.extern_id
	
	declare @seed_id int = isnull((select max(wk_sheet_id) from mfr_wk_sheets), 0)

	update x
	set wk_sheet_id = @seed_id + xx.id
	from #wksheets x
		join (
			select row_number() over (order by (select 0)) as id, extern_id
			from #wksheets
		) xx on xx.extern_id = x.extern_id
	where x.wk_sheet_id is null
end -- wk_sheet_id

begin
	exec tracer_log @tid, 'Dictionaries'
	exec mfr_wk_sheets_replicate;2	
end -- dictionaries

begin
	exec tracer_log @tid, 'Process MFR_WK_SHEETS'

	select * into #old_mfr_wk_sheets from mfr_wk_sheets where wk_sheet_id in (select wk_sheet_id from #wksheets)
	select * into #old_mfr_wk_sheets_details from mfr_wk_sheets_details where wk_sheet_id in (select wk_sheet_id from #wksheets)

	delete from mfr_wk_sheets where note like '%автоматически%'

	SET IDENTITY_INSERT MFR_WK_SHEETS ON;

		insert into mfr_wk_sheets(
			extern_id, wk_sheet_id,
			subject_id, place_id, status_id,
			d_doc, number,
			note,
			add_mol_id
			)
		select
			x.extern_id, x.wk_sheet_id,
			x.subject_id, x.place_id,
			isnull(old.status_id, 100),
			x.d_doc, x.number,
			x.note,
			@mol_id
		from #wksheets x
			left join #old_mfr_wk_sheets old on old.wk_sheet_id = x.wk_sheet_id

		set @tid_msg = concat('    MFR_WK_SHEETS: ', @@rowcount, ' rows')
		exec tracer_log @tid, @tid_msg

		drop table #old_mfr_wk_sheets
	
	SET IDENTITY_INSERT MFR_WK_SHEETS OFF;
end -- mfr_wk_sheets

begin
	exec tracer_log @tid, 'Process MFR_WK_SHEETS_DETAILS'

	insert into mfr_wk_sheets_details(
		wk_sheet_id, mol_id, wk_hours, note
		)
	select
		h.wk_sheet_id, d.mol_id, d.wk_hours, d.note
	from #wksheets_details d
		join #wksheets h on h.extern_id = d.extern_id
	
	set @tid_msg = concat('    MFR_WK_SHEETS_DETAILS: ', @@rowcount, ' rows')
	exec tracer_log @tid, @tid_msg

	drop table #old_mfr_wk_sheets_details
end -- details

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max); set @err = error_message()
	raiserror (@err, 16, 3)
END CATCH -- TRANSACTION

begin

	final:
		if object_id('tempdb.dbo.#wksheets') is not null drop table #wksheets
		if object_id('tempdb.dbo.#wksheets_details') is not null drop table #wksheets_details

	exec mfr_wk_sheets_calc @trace = @trace

	-- close log	
	exec tracer_close @tid
	if @trace = 1 exec tracer_view @tid
	return

	mbr:
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		raiserror('manual break', 16, 1)

end -- final

end
GO
-- helper: авто-справочники
create proc mfr_wk_sheets_replicate;2
as
begin
	set nocount on;

	declare @mols table(
		row_id int identity,
		mol_id int,
		mol_name varchar(100) index ix_mol_name,
		name varchar(100),
		surname varchar(50),
		name1 varchar(50),
		name2 varchar(50),
		post_name varchar(150),
		dept_id int
		)

	update x set mol_id = m.mol_id
	from #wksheets_details x
		join mols m on concat(surname, ' ', name1, ' ', name2) = x.mol_name
	where x.mol_id is null

	insert into @mols(mol_name, name, surname, name1, name2, post_name, dept_id)
	select distinct
		mol_name,
		concat(
			dbo.strtoken(mol_name, ' ', 1),
			' ',
			left(dbo.strtoken(mol_name, ' ', 2), 1), '.',
			left(dbo.strtoken(mol_name, ' ', 3), 1), '.'
			),
		dbo.strtoken(mol_name, ' ', 1),
		dbo.strtoken(mol_name, ' ', 2),
		dbo.strtoken(mol_name, ' ', 3),
		post_name,
		dept_id
	from #wksheets_details
	where mol_id	 is null
	order by 1

	declare @seed_id int = isnull((select max(mol_id) from mols), 0)
	update @mols	 set mol_id = @seed_id + row_id

-- mols_posts
	insert into mols_posts(subject_id, name)
	select subject_id, name
	from (
		select distinct 37 as subject_id, name = post_name -- TODO: SUBJECT_ID
		from @mols
		) x
	where not exists(select 1 from mols_posts where subject_id = x.subject_id and name = x.name)

-- mols
	insert into mols(
		mol_id, name, surname, name1, name2, post_id, posts_names, dept_id, status_id
		)
	select
		m.mol_id, m.name, m.surname, m.name1, m.name2, mp.post_id, mp.name,
		m.dept_id,
		1
	from @mols m
		join mols_posts mp on mp.subject_id = 37 and mp.name = m.post_name -- TODO: SUBJECT_ID

-- map
	update x set mol_id = m.mol_id
	from #wksheets_details x
		join @mols m on m.mol_name = x.mol_name
	where x.mol_id is null

end
GO
