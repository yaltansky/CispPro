if object_id('app_autoadmin') is not null drop proc app_autoadmin
go
create proc app_autoadmin
as
begin
	
	set nocount on;

	if datepart(hour, getdate()) in (11,12)
		exec finance_autoadmin
	else begin
		-- modules
        exec finance_autoadmin
		exec mfr_autoadmin
		exec products_autoadmin
		-- CISP
		exec sdocs_autoadmin
		exec sales_autoadmin
        exec documents_autoadmin
		exec mols_autoadmin
		exec tasks_autoadmin
		exec talks_autoadmin
        -- sys
		exec events_autoadmin
		exec app_checkdb
	end
end
go
