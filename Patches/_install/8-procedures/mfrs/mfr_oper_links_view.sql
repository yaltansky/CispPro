if object_id('mfr_opers_links_extra_view') is not null drop proc mfr_opers_links_extra_view
go
-- exec mfr_opers_links_extra_view 2009946, 39257
create proc mfr_opers_links_extra_view
	@mfr_doc_id int,
	@product_id int,
    @content_id int = null
as
begin
    select x.*,
        SOURCE_CONTENT_NAME = cs.NAME,
        SOURCE_OPER_NAME = os.NAME,
        TARGET_CONTENT_NAME = ct.NAME,
        TARGET_OPER_NAME = ot.NAME
    from sdocs_mfr_opers_links_extra x
        join sdocs_mfr_contents cs on cs.content_id = x.source_content_id
            join sdocs_mfr_opers os on os.content_id = cs.content_id and os.number = x.source_oper_number
        join sdocs_mfr_contents ct on ct.content_id = x.target_content_id
            join sdocs_mfr_opers ot on ot.content_id = ct.content_id and ot.number = x.target_oper_number
    where x.mfr_doc_id = @mfr_doc_id
        and x.product_id = @product_id
        and (@content_id is null or x.source_content_id = @content_id or x.target_content_id = @content_id)
    order by cs.name, os.number, ct.name, ot.number
end
go
