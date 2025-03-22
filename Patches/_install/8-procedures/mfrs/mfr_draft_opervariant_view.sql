if object_id('mfr_draft_opervariant_view') is not null drop proc mfr_draft_opervariant_view
go
-- exec mfr_draft_opervariant_view 1000
create proc mfr_draft_opervariant_view
	@mol_id int
as
begin

	set nocount on;

	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')
	declare @pdm_id int = nullif((select top 1 pdm_id from v_sdocs_mfr_contents c, @buffer i where c.content_id = i.id and c.pdm_id is not null), 0)
	declare @item_id int = (select top 1 item_id from v_sdocs_mfr_contents c, @buffer i where c.content_id = i.id)

    if 1 < (select count(distinct item_id) from sdocs_mfr_contents c, @buffer i where c.content_id = i.id)
        select distinct
            PdmId = null,
            ItemId = c.item_id,
            VariantNumber = 1,
            VariantName = 'Ошибка: разные детали в буфере',
            OperName = c.name,
            ResourceName = ''
        from sdocs_mfr_contents c, @buffer i 
        where c.content_id = i.id

    else 
        select
            PdmId = d.pdm_id,
            ItemId = d.item_id,
            VariantNumber = o.variant_number,
            VariantName = concat('Вариант#', o.variant_number),
            OperName = concat('#', o.number, '-', o.name),
            ResourceName = (
                select top 1 rs.name
                from mfr_pdm_opers_resources r
                    join mfr_resources rs on rs.resource_id = r.resource_id
                where r.oper_id = o.oper_id
                )
        from mfr_pdm_opers o
            join mfr_pdms d on d.pdm_id = o.pdm_id
        where d.pdm_id = isnull(@pdm_id, d.pdm_id)
            and d.item_id = @item_id
        order by o.variant_number, o.number

end
go
