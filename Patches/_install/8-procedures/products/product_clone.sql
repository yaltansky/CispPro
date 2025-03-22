if object_id('product_clone') is not null drop proc product_clone
go
create proc product_clone
	@mol_id int,
	@product_id int,
	@new_id int out
as
begin

	set nocount on;

	insert into products(
		parent_id, name, name_print, status_id, mol_id, admin_id, note, tags, group1_id, group2_id, type_id, class_id
		)
	select
	 	@product_id, name + ' (копия)', name_print + ' (копия)', 0, @mol_id, @mol_id, note, tags, group1_id, group2_id, type_id, class_id
	from products
	where product_id = @product_id
	
	set @new_id = @@identity

	insert into products_attrs(product_id, attr_id, attr_value)
	select @new_id, attr_id, attr_value
	from products_attrs
	where product_id = @product_id

end
go
