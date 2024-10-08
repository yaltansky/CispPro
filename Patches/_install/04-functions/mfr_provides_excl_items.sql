if object_id('mfr_provides_excl_items') is not null drop function mfr_provides_excl_items
go
create function mfr_provides_excl_items(@is_buy bit)
returns @items table (id int primary key)
as
begin

    insert into @items
    select item from (
        select distinct item = try_cast(item as int)
        from dbo.str2rows(dbo.app_registry_varchar(
            case when @is_buy = 1 then 'MfrProvidesExcludeMaterialTypes' else 'MfrProvidesExcludeItemTypes' end
            ), ',')
        ) x 
    where item is not null

    return

end
GO
