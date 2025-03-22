if object_id('mfr_plan_jobs_checkaccess') is not null drop proc mfr_plan_jobs_checkaccess
go
create proc mfr_plan_jobs_checkaccess
	@mol_id int,
	@item varchar(64),
    @action varchar(64),
    @jobs app_pkids readonly,
	@job_id int = null
as
begin

	declare @allow_reglament bit = isnull(cast((select dbo.app_registry_value('AllowMfrReglamentPlaces')) as bit), 0)
	
	if @allow_reglament = 0
	begin
		exec mfr_checkaccess @mol_id = @mol_id, @item = @item, @action = @action
		return
	end

    declare @subject_id int = (select top 1 subject_id from mfr_plans where status_id = 1)
	declare @is_admin bit = dbo.isinrole_byobjs(@mol_id, 'Mfr.Admin', 'SBJ', @subject_id)

	declare @jaccess_jobs as app_pkids
	
	if @job_id is not null
		insert into @jaccess_jobs select @job_id
	else
		insert into @jaccess_jobs select id from @jobs

	if 0 = any(
		select 
			case
				when @is_admin = 1 then 1
				when @mol_id in (x.add_mol_id, x.executor_id) then 1
				when exists(
					select 1 from mfr_places_mols
					where place_id = x.place_id and mol_id = @mol_id
						and (isnull(is_chief,0) = 1 or isnull(is_dispatch,0) = 1 or isnull(is_master,0) = 1)
					) then 1
				else 0
			end
		from mfr_plans_jobs x
			join @jaccess_jobs i on i.id = x.plan_job_id
		)
	begin
		raiserror('В данном контексте обнаружены объекты вне Вашей зоны ответственности. Операция приостановлена.', 16, 1)
		return
	end

end
go
