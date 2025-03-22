if object_id('invoice_calc') is not null drop proc invoice_calc
go
create proc invoice_calc
	@mol_id int,
	@doc_id int
as
begin

	set nocount on;

	update x set ratio_value = x.ratio * sd.value_ccy
	from sdocs_milestones x
		join sdocs sd on sd.doc_id = x.doc_id
	where sd.doc_id = @doc_id

end
GO
