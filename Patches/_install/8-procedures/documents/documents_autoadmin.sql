if object_id('documents_autoadmin') is not null
	drop proc documents_autoadmin
go
create proc documents_autoadmin
as
begin
	IF DB_NAME() NOT IN ('CISP') RETURN
	exec documents_calc
end
go
