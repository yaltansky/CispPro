if object_id('products_autoadmin') is not null drop proc products_autoadmin
go
create proc products_autoadmin
as
begin
	exec prodmeta_attrs_calc
end
go
