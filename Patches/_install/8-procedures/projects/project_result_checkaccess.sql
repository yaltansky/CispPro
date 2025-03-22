if object_id('project_result_checkaccess') is not null drop proc project_result_checkaccess
go
create proc project_result_checkaccess
	@mol_id int,
	@result_id int,
	@allowaccess bit out
as
begin
	set @allowaccess = 1 -- public
end
GO
