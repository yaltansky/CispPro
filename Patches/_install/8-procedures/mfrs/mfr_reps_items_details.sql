if object_id('mfr_reps_items_details') is not null drop proc mfr_reps_items_details
go
-- exec mfr_reps_items_details 700, @plan_id = 3
-- exec mfr_reps_items_details 700, @folder_id = 19600, @place_id = 31
create proc mfr_reps_items_details
	@mol_id int,
	@plan_id int = null,
	@folder_id int = null, -- папка планов
	@place_id int = null
as
begin

	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- @plans
	declare @plans as app_pkids

	if @folder_id is not null set @plan_id = null

	if @plan_id = 0 insert into @plans select plan_id from mfr_plans where status_id = 1
	else if @plan_id is not null insert into @plans select @plan_id
	else insert into @plans exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfp'

-- reglament access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'
	declare @subject_id int = (select subject_id from mfr_plans where plan_id = @plan_id)

	declare @attrMfrRoute int = (select attr_id from mfr_attrs where attr_key = 'MfrRoute')

	select
		x.plan_number,
		x.mfr_number,
		x.item_name,
		item_q = concat(x.q_brutto_product, ' ', x.unit_name),
		item_route = ca.note,
		item_status = x.status_name,
		item_opers_to = dbo.getday(x.opers_to),
		child_item_name = p2.name,
		child_unit_name = xx.unit_name,
		child_q = xx.q_brutto_product,
		mfr_doc_hid = concat('#', x.mfr_doc_id),
		item_hid = concat('#', x.item_id),
		child_item_hid = concat('#', xx.item_id)
	from v_sdocs_mfr_contents x
		join sdocs sd on sd.doc_id = x.mfr_doc_id
		join sdocs_mfr_contents xx on xx.mfr_doc_id = x.mfr_doc_id and xx.parent_id = x.child_id
			join products p2 on p2.product_id = xx.item_id
		left join sdocs_mfr_contents_attrs ca on ca.content_id = x.content_id and ca.attr_id = @attrMfrRoute
	where 
		-- reglament access
		sd.subject_id in (select id from @subjects)
		-- conditions
		and x.plan_id in (select id from @plans)
		and (
			@place_id is null
			or exists(select 1 from sdocs_mfr_opers where content_id = x.content_id and place_id = @place_id)
		)

end
GO
