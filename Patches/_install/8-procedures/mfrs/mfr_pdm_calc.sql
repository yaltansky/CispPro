if object_id('mfr_pdm_calc') is not null drop proc mfr_pdm_calc
go
create proc mfr_pdm_calc
	@mol_id int,
	@pdm_id int = null,
	@pdms app_pkids readonly
as
begin

	set nocount on;

	create table #pdm_calc(id int primary key)

	if @pdm_id is not null
		insert into #pdm_calc select @pdm_id
	else
		insert into #pdm_calc select id from @pdms

	update x set has_childs = 
		case
			when exists(select 1 from mfr_pdm_items where pdm_id = x.pdm_id and parent_id = x.id) then 1
			else 0
		end
	from mfr_pdm_items x
		join #pdm_calc i on i.id = x.pdm_id

end
GO
