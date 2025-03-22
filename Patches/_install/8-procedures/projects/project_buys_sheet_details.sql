if object_id('project_buys_sheet_details') is not null drop proc project_buys_sheet_details
go
create proc project_buys_sheet_details
	@project_id int,
	@product_id int
as
begin

	set nocount on;

	select
		BSD.PRODUCT_ID,
		BSD.OUT_DOC_ID,
		BSD.OUT_D_DOC,
		BSD.IN_DOC_ID,
		BSD.IN_D_DOC,
		BSD.QUANTITY,
		BSD.Q_BUY,
		BSD.Q_STOCK,
		BSD.Q_MFS,
		NOTE = ISNULL(S1.NOTE, '') + ' < ' + ISNULL(S2.NOTE, '')
	from projects_buys_sheets_details bsd
		left join sdocs s1 on s1.doc_id = bsd.out_doc_id
		left join sdocs s2 on s2.doc_id = bsd.in_doc_id
	where bsd.project_id = @project_id

end
go