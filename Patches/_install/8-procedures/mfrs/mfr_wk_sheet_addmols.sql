if object_id('mfr_wk_sheet_addmols') is not null drop proc mfr_wk_sheet_addmols
go
create proc mfr_wk_sheet_addmols
	@mol_id int,
	@wk_sheet_id int,
	@place_id int
as
begin

	set nocount on;

	delete from mfr_wk_sheets_details where wk_sheet_id = @wk_sheet_id

	insert into mfr_wk_sheets_details(wk_sheet_id, parent_id, mol_id, name, wk_hours, add_date, add_mol_id)
	select @wk_sheet_id, parent_id, mol_id, name, 8, getdate(), @mol_id
	from mfr_places_mols
	where place_id = (select place_id from mfr_wk_sheets where wk_sheet_id = @wk_sheet_id)
		and isnull(is_dispatch,0) = 0

	update x set parent_id = xx.id
	from mfr_wk_sheets_details x
		join mfr_wk_sheets_details xx on xx.wk_sheet_id = x.wk_sheet_id and xx.mol_id = x.parent_id
	where x.wk_sheet_id = @wk_sheet_id

	declare @where_rows varchar(100) = concat('wk_sheet_id = ', @wk_sheet_id)
	exec tree_calc_nodes 'mfr_wk_sheets_details', 'id', @where_rows = @where_rows, @use_sort_id = 1
end
GO
