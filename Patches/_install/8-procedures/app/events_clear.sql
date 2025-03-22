if exists(select 1 from sys.objects where name = 'events_clear')
	drop proc events_clear
go

create proc events_clear
	@mol_id int
as
begin

	-- alerts by tasks
	update tasks_hists_mols
	set d_read = getdate()
	where mol_id = @mol_id and d_read is null

	-- alerts by talks
	update talks_mols
	set count_unreads = 0
	where mol_id = @mol_id and count_unreads > 0

	-- other alerts	
	update events_mols
	set read_date = getdate()
	where mol_id = @mol_id and read_date is null
	
end
go
