if object_id('sdocs_autoadmin') is not null drop proc sdocs_autoadmin
go
create proc sdocs_autoadmin
	@date_from datetime = null,
	@date_to datetime = null,
	@subject_id int = null
as
begin
    exec sdocs_calc_access

	IF DB_NAME() NOT IN ('CISP') RETURN

-- репликация документов	
	exec sdocs_replicate @date_from = @date_from, @date_to = @date_to, @subject_id = @subject_id

-- пересчёт основного регистра
	exec sdocs_provides_calc

end
go
