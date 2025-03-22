if object_id('mols_autoadmin') is not null drop proc mols_autoadmin
go
create proc mols_autoadmin
as
begin

	set nocount on;	

	IF DB_NAME() NOT IN ('CISP') RETURN

-- delete mols caches
	truncate table findocs_cache

-- purge dummys
	delete from mols where isnull(name, '') = ''
end
go
