if object_id('sdocs_reps_provides_mfr_program') is not null drop proc sdocs_reps_provides_mfr_program
go
-- exec sdocs_reps_provides_mfr_program 700, '2019-06-01', '2019-06-30'
create proc sdocs_reps_provides_mfr_program
	@mol_id int,
	@d_from datetime = null, 
	@d_to datetime = null
as
begin
	
	set nocount on;

	if @d_from is null set @d_from = '2019-06-01'
	if @d_to is null set @d_to = '2019-06-30'

	--if @d_from is null set @d_from = dbo.today()
	--if @d_to is null set @d_to = dbo.today()

	declare @max_date datetime = '9999-12-31'

	select * from v_sdocs_provides
	-- Исключить записи, если все даты (запуска, выпуска) < “От” или все даты > “До”
	where id_mfr is not null
		and not (
			(isnull(d_mfr, @max_date) < @d_from and isnull(d_issue, @max_date) < @d_from)
			or (isnull(d_mfr, @max_date) > @d_to and isnull(d_issue, @max_date) > @d_to)
			)
		
end
go
