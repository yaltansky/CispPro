if object_id('mfr_item_change_buy') is not null drop proc mfr_item_change_buy
go
create proc mfr_item_change_buy
	@mol_id int,
	@content_id int,
	@is_buy bit
as
begin

    set nocount on;

	declare @mfr_doc_id int, @product_id int, @draft_id int, @node hierarchyid
	
	select
		@mfr_doc_id = mfr_doc_id,
		@product_id = product_id,
		@draft_id = draft_id,
		@node = node
	from sdocs_mfr_contents
	where content_id = @content_id

BEGIN TRY
BEGIN TRANSACTION

	update x
	set is_deleted = case when @is_buy = 1 then 1 else 0 end
	from sdocs_mfr_contents x
		join sdocs_mfr_contents c2 on c2.mfr_doc_id = x.mfr_doc_id and c2.product_id = x.product_id
			and x.node.IsDescendantOf(c2.node) = 1
	where x.mfr_doc_id = @mfr_doc_id
		and x.product_id = @product_id
		and c2.draft_id = @draft_id
		and x.content_id <> c2.content_id
	
	update sdocs_mfr_contents set is_buy = @is_buy where draft_id = @draft_id
	update sdocs_mfr_drafts set is_buy = @is_buy where draft_id = @draft_id
	
COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max); set @err = error_message()
	raiserror (@err, 16, 3)
END CATCH

end
go
