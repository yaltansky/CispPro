if object_id('mfr_docs_from_pdm') is not null drop proc mfr_docs_from_pdm
go
create proc mfr_docs_from_pdm
	@mol_id int,
	@docs app_pkids readonly
as
begin
    set nocount on;

    -- purge
        delete from mfr_drafts where mfr_doc_id in (select id from @docs)
        exec mfr_drafts_purge 1000, @docs = @docs

        delete from sdocs_mfr_contents where mfr_doc_id in (select id from @docs)
        delete from sdocs_mfr_opers where mfr_doc_id in (select id from @docs)

    -- normalize
        update mfr_pdms set is_default = 0 where is_deleted = 1;
        
        update x set is_default = 1
        from mfr_pdms x
            join (
                select item_id from mfr_pdms where is_deleted = 0
                group by item_id having count(*) = 1
            ) xx on xx.item_id = x.item_id
        where isnull(is_default, 0) = 0 and x.is_deleted = 0

    -- mfr_drafts
        insert into mfr_drafts(mfr_doc_id, product_id, item_id, pdm_id, is_buy, is_root, is_product, status_id)
        select x.doc_id, x.product_id, x.product_id, p.pdm_id, 0, 1, 1, 10
        from sdocs_products x
            join mfr_pdms p on p.item_id = x.product_id and p.is_default = 1
        where doc_id in (select id from @docs)

    -- import from pdm
        declare c_drafts cursor static local read_only for 
            select draft_id from mfr_drafts where mfr_doc_id in (select id from @docs);
        
        declare @draft_id int;
        
        open c_drafts; fetch next from c_drafts into @draft_id
            while (@@fetch_status != -1)
            begin
                begin try
                    if (@@fetch_status != -2) begin
                        exec mfr_drafts_from_pdm 1000, @draft_id
                    end
                    fetch next from c_drafts into @draft_id
                end try

                begin catch
                    declare @err varchar(max) = concat('error draft #', @draft_id, ':', error_message())
                    raiserror (@err, 16, 1)
                end catch
            end
        close c_drafts; deallocate c_drafts

    -- calc 
        exec mfr_drafts_calc @mol_id = @mol_id, @docs = @docs

    -- milestone
        declare @attr_product int = (select top 1 attr_id from mfr_attrs where name like '%готовая продукция%')
        update x set milestone_id = @attr_product
        from sdocs_mfr_opers x
            join sdocs_mfr_contents c on c.content_id = x.content_id
                join @docs i on i.id = c.mfr_doc_id
                join mfr_drafts d on d.draft_id = c.draft_id and d.is_product = 1
        where x.is_last = 1
end
GO
