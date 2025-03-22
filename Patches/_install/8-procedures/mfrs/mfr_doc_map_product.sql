if object_id('mfr_doc_map_product') is not null drop proc mfr_doc_map_product
go
create proc mfr_doc_map_product
	@doc_id int,
	@old_product_id int,
	@new_product_id int
as
begin

	SET NOCOUNT ON;

    BEGIN TRY
    BEGIN TRANSACTION

        -- sdocs_mfr_drafts
            update sdocs_mfr_drafts set product_id = @new_product_id
            where mfr_doc_id = @doc_id and product_id = @old_product_id

            RAISERROR('manual', 16, 1)    

        -- sdocs_mfr_contents
            update sdocs_mfr_contents set product_id = @new_product_id
            where mfr_doc_id = @doc_id and product_id = @old_product_id

        -- sdocs_mfr_opers
            update sdocs_mfr_opers set product_id = @new_product_id
            where mfr_doc_id = @doc_id and product_id = @old_product_id

        -- sdocs_mfr_milestones
            delete from sdocs_mfr_milestones where doc_id = @doc_id and product_id = @new_product_id
            update sdocs_mfr_milestones set product_id = @new_product_id
            where doc_id = @doc_id and product_id = @old_product_id

        -- mfr_plans_jobs_details
            update mfr_plans_jobs_details set product_id = @new_product_id
            where mfr_doc_id = @doc_id and product_id = @old_product_id

    COMMIT TRANSACTION
    END TRY

    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        declare @err varchar(max) = error_message()
        raiserror (@err, 16, 1)
    END CATCH

end
go
