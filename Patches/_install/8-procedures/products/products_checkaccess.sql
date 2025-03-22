if object_id('products_checkaccess') is not null drop proc products_checkaccess
go
create proc products_checkaccess
	@mol_id int,
	@item varchar(64),
    @action varchar(64) = null,
    @subject_id int = null
as
begin

	declare @roles varchar(max) = isnull(
		dbo.app_registry_varchar(concat(
			@item,
			case when @action is not null then ':' end,
			@action)
		),
		'Admin,Products.Admin'
		)

    if @subject_id is null
        set @subject_id = (select top 1 subject_id from app_databases_subjects where dbname = db_name() and is_default = 1)

	if dbo.isinrole_byobjs(@mol_id, @roles, 'SBJ', @subject_id) = 0
		raiserror('У Вас нет доступа к выполнению текущей операции в заданном контексте.', 16, 1)

end
go
