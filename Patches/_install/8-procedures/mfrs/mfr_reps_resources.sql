if object_id('mfr_reps_resources') is not null drop proc mfr_reps_resources
go
-- exec mfr_reps_resources 700, @plan_id = 0, @is_alldays = 1
create proc mfr_reps_resources
	@mol_id int,
	@plan_id int = null,
	@folder_id int = null, -- папка планов
	@d_doc datetime = null,
	@is_alldays bit = 0
as
begin

	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

-- reglament access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

-- @plans
	declare @plans as app_pkids
	declare @contents as app_pkids

	if @folder_id is not null set @plan_id = null
	
	if @plan_id = 0 
	begin
		if exists(select 1 from dbo.objs_buffer(@mol_id, 'mfc'))
			insert into @contents
			select id from dbo.objs_buffer(@mol_id, 'mfc')
		else
			insert into @plans select plan_id from mfr_plans where status_id = 1
				and subject_id in (select id from @subjects)
	end
	else if @plan_id is not null
		insert into @plans select @plan_id
	else 
		insert into @plans exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfp'

-- @d_from, @d_to
	set @d_doc = isnull(@d_doc, dbo.today())
	declare @d_from datetime = dateadd(d, -datepart(d, @d_doc)+1, @d_doc)
	declare @d_to datetime = dateadd(m, 1, @d_from) - 1

	if @is_alldays = 1
	begin
		set @d_from = 0
		set @d_to = '9999-12-31'
	end

	select
		RowId = x.id,
		ResourceName = res.name,
		ResourceDate = x.resource_date,
		PlaceName = pl.full_name,
		MfrNumber = sd.number,
		ItemName = p.name,
		OperName = o.name,
		OperFrom = x.oper_from,
		OperTo = x.oper_to,
		Loading = x.loading,
		ContentHid = concat('#', x.content_id),
		OperHid = concat('#', x.oper_id)
	from mfr_plans_resources_fifo x
		join mfr_plans pln on pln.plan_id = x.plan_id
		-- dict
		join mfr_resources res on res.resource_id = x.resource_id
		join sdocs_mfr_opers o on o.oper_id = x.oper_id
		join mfr_places pl on pl.place_id = x.oper_place_id
		join products p on p.product_id = x.item_id
		join sdocs sd on sd.doc_id = x.mfr_doc_id
	where x.resource_date between @d_from and @d_to

end
go
