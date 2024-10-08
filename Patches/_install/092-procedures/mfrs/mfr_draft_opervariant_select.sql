if object_id('mfr_draft_opervariant_select') is not null drop proc mfr_draft_opervariant_select
go
create proc [mfr_draft_opervariant_select]
	@mol_id int,
	@draft_id int,
	@variant_number int
as
begin

	set nocount on;

	-- clear
	update mfr_drafts_opers set variant_selected = null
	where draft_id = @draft_id

	-- set
	update mfr_drafts_opers set variant_selected = 1
	where draft_id = @draft_id
		and variant_number = @variant_number

end
GO
