if object_id('mfr_wk_sheet_clone') is not null drop proc mfr_wk_sheet_clone
go
create proc mfr_wk_sheet_clone
	@mol_id int,
	@wk_sheet_id int
as
begin

	set nocount on;

	BEGIN TRY
	BEGIN TRANSACTION

		-- mfr_wk_sheets
			insert into mfr_wk_sheets(
				subject_id, place_id, d_doc, number, status_id, executor_id, note, add_mol_id
				)
			select 
				subject_id, place_id, d_doc, '(c)' + number, status_id, executor_id, note, @mol_id
			from mfr_wk_sheets
			where wk_sheet_id = @wk_sheet_id
		
		declare @new_id int = @@identity

		-- mfr_wk_sheets_details
			insert into mfr_wk_sheets_details(
				wk_sheet_id, mol_id, wk_hours, wk_k_inc, wk_ktu, wk_post_id, has_childs, node, sort_id
				)
			select @new_id, mol_id, wk_hours, wk_k_inc, wk_ktu, wk_post_id, has_childs, node, sort_id
			from mfr_wk_sheets_details
			where wk_sheet_id = @wk_sheet_id

			update x set parent_id = (
				select top 1 id from mfr_wk_sheets_details where wk_sheet_id = x.wk_sheet_id
					and node = x.node.GetAncestor(1)
				)
			from mfr_wk_sheets_details x
			where wk_sheet_id = @new_id
				and has_childs = 0

			declare @where_rows varchar(100) = concat('wk_sheet_id = ', @new_id)
			exec tree_calc_nodes 'mfr_wk_sheets_details', 'id', @where_rows = @where_rows, @use_sort_id = 1

		-- select new card
			select top 1 * from mfr_wk_sheets where wk_sheet_id = @new_id

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH

end
GO
