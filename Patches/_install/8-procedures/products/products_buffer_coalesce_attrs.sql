if object_id('products_buffer_coalesce_attrs') is not null drop proc products_buffer_coalesce_attrs
go
create proc products_buffer_coalesce_attrs
	@mol_id int,
    @product_id int
as
begin
    declare @buffer as app_pkids;
    insert into @buffer select id from dbo.objs_buffer(@mol_id, 'P');

    select pa.*,
        attr_name = a.name,
        attr_exist = 
            case
                when exists(
                    select 1 from products_attrs
                        join @buffer i on i.id = products_attrs.product_id
                    where attr_id = pa.attr_id
                    )
                then 1
            end
    from products_attrs pa
        join prodmeta_attrs a on a.attr_id = pa.attr_id
    where product_id = @product_id
end
go
