if object_id('prodmeta_attrs_calc') is not null drop proc prodmeta_attrs_calc
go
create proc prodmeta_attrs_calc
as
begin

	set nocount on;

	exec tree_calc_nodes 'prodmeta_attrs', 'attr_id', @sortable = 1

	delete from prodmeta_attrs_values
	
	insert into prodmeta_attrs_values(attr_id, attr_value, attr_value_number)
	select distinct attr_id, attr_value, attr_value_number
	from products_attrs
	where isnull(attr_value, '') <> ''

end
GO
