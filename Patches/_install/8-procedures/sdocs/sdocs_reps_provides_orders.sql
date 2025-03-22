if object_id('sdocs_reps_provides_orders') is not null drop proc sdocs_reps_provides_orders
go
-- exec sdocs_reps_provides_orders 700, '2019-06-01', '2019-06-30'
create proc sdocs_reps_provides_orders
	@mol_id int,
	@d_from datetime = null, 
	@d_to datetime = null,
	@folder_id int = null
as
begin
	
	set nocount on;

	if @d_from is null set @d_from = dbo.today()
	if @d_to is null set @d_to = dbo.today()

	declare @max_date datetime = '9999-12-31'

-- @ids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'SD'
	declare @filter_ids bit = case when exists(select 1 from @ids) then 1 end

	select 
		x.*,
		D.VENDOR_NAME,
		D.DIRECTION_NAME,
		D.MOL_NAME
	from v_sdocs_provides x
		left join v_deals d on d.deal_id = x.id_deal
	-- Исключить записи, если все даты (запуска, выпуска, отгрузки) < “От” или все даты > “До”
	where not (
			(
					isnull(x.d_mfr, @max_date) < @d_from
				and isnull(x.d_issue, @max_date) < @d_from
				and isnull(x.d_ship, @max_date) < @d_from
				and isnull(x.d_order, @max_date) < @d_from
			) or (
					isnull(x.d_mfr, @max_date) > @d_to
				and isnull(x.d_issue, @max_date) > @d_to
				and isnull(x.d_ship, @max_date) > @d_to
				and isnull(x.d_order, @max_date) > @d_to
			)
		)
		and (
			@filter_ids is null
			or (
				x.id_order in (select id from @ids)
				or x.id_ship in (select id from @ids)
				or x.id_mfr in (select id from @ids)
				or x.id_issue in (select id from @ids)
			)
		)

end
go
