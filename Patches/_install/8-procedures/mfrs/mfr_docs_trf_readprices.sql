/**
    declare @docs app_pkids
        -- insert into @docs select 642829
        -- insert into @docs select doc_id from sdocs where type_id = 12 and d_doc >= '2024-05-01'
        insert into @docs select id from dbo.objs_buffer(1000, 'MFTRF')
    exec mfr_docs_trf_readprices 1000, @docs = @docs, @enforce = 1
**/
if object_id('mfr_docs_trf_readprices') is not null drop proc mfr_docs_trf_readprices
go
create proc mfr_docs_trf_readprices
    @mol_id int,
    @docs app_pkids readonly,
    @enforce bit = 0
as
begin

    -- read mfr_r_provides.price_ship
        update x set 
            nds_ratio = 0.2,
            price_pure = r.price_ship / 1.2 *
                case 
                    when r.unit_name = u.name then 1.0 
                    else nullif(coalesce(uk.koef, dbo.product_ukoef(r.unit_name, u.name), 1), 0)
                end
        from sdocs_products x
            join sdocs sd on sd.doc_id = x.doc_id
            join (
                select id_job, item_id, unit_name, price_ship = sum(price_ship * (isnull(q_job,0) + isnull(q_lzk,0))) / nullif(sum(isnull(q_job,0) + isnull(q_lzk,0)), 0)
                from mfr_r_provides
                where price_ship > 0
                group by id_job, item_id, unit_name
            ) r on r.id_job = x.doc_id and r.item_id = x.product_id
            join products_units u on u.unit_id = x.unit_id
            left join products_ukoefs uk on uk.product_id = x.product_id and uk.unit_from = r.unit_name and uk.unit_to = u.name
        where sd.doc_id in (select id from @docs)
            and (@enforce = 1 or isnull(x.price_pure, 0) = 0)

    -- read mfr_items_prices
        update x set 
            nds_ratio = 0.2,
            price_pure = pr.price_pure
                            / 
                            case 
                                when u.name = u2.name then 1.0 
                                else nullif(coalesce(uk.koef, dbo.product_ukoef(u.name, u2.name), 1), 0)
                            end
        from sdocs_products x
            join sdocs sd on sd.doc_id = x.doc_id
            join mfr_items_prices pr on pr.product_id = x.product_id
                join products_units u on u.unit_id = pr.unit_id
                join products_units u2 on u2.unit_id = x.unit_id
                left join products_ukoefs uk on uk.product_id = pr.product_id and uk.unit_from = u.name and uk.unit_to = u2.name
        where sd.doc_id in (select id from @docs)
            and isnull(x.price_pure, 0) = 0

    exec sdoc_calc @mol_id = @mol_id, @docs = @docs
end
go
