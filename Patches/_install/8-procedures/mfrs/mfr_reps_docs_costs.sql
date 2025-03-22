if object_id('mfr_reps_docs_costs') is not null drop proc mfr_reps_docs_costs
go
-- exec mfr_reps_docs_costs 700, @folder_id = 19600
create proc mfr_reps_docs_costs
	@mol_id int,	
	@plan_id int = null,
	@folder_id int = null, -- папка планов или заказов
	@materal_group_attr_id int = 31 -- материал.ГруппаНаименование (select * from mfr_attrs where attr_id = 31
as
begin

	set nocount on;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- @docs
	declare @docs as app_pkids

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

	declare @objs as app_pkids
	insert into @objs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfp' -- планы (по-умолчанию)

	if exists(select 1 from @objs)
		-- буфер/папка/папки содержат планы
		insert into @docs select doc_id from sdocs where plan_id in (select id from @objs)			
	else begin
		-- буфер/папка/папки содержат заказы
		insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'mfr'
	end

	if not exists(select 1 from @objs)
		insert into @docs select doc_id from sdocs
		where plan_id in (select plan_id from mfr_plans where status_id = 1)

-- reglament access
	declare @objects as app_objects; insert into @objects exec mfr_getobjects @mol_id = @mol_id
	declare @subjects as app_pkids; insert into @subjects select distinct obj_id from @objects where obj_type = 'sbj'

	delete x from @docs x
		join sdocs sd on sd.DOC_ID = x.id
			left join @subjects s on s.id = sd.subject_id
	where s.id is null

	declare @result table(
		mfr_doc_id int,
		product_id int,
		child_id int,
		--
		content_id int index ix_content,
		draft_id int index ix_draft,
		item_id int,
		oper_id int index ix_oper,		
		oper_number int,
		group1_name varchar(250),
		group2_name varchar(250),
		material_content_id int index ix_material_content,
		material_id int index ix_material,
		resource_id int index ix_resource,
		material_or_resource_name varchar(500),
		unit_name varchar(20),
		q_brutto_product float,
		cost_plan float,
		cost_fact float,
		slice varchar(10),
		--
		index ix_child (mfr_doc_id, product_id, child_id),
		index ix_opers (draft_id, oper_number)
		)

-- items
	insert into @result(
		mfr_doc_id, product_id, child_id,
		content_id, draft_id, item_id, oper_id, q_brutto_product, unit_name,
		slice
		)
	select
		o.mfr_doc_id,
		c.product_id,
		c.child_id,
		c.content_id,
		c.draft_id,
		c.item_id,
		o.oper_id,
		c.q_brutto_product,
		c.unit_name,
		'items'
	from sdocs_mfr_opers o
		join sdocs_mfr_contents c on c.content_id = o.content_id and c.is_deleted = 0
			join @docs i on i.id = c.mfr_doc_id
	where c.is_buy = 0

-- materials
	insert into @result(
		mfr_doc_id, product_id,
		content_id, item_id, oper_id, 
		group1_name, material_content_id, material_id, material_or_resource_name, cost_plan,
		slice
		)
	select
		c.mfr_doc_id,
		c.product_id,
		c.content_id,
		r.item_id,
		r.oper_id,		
		'Материалы',
		c.content_id,
		c.item_id,
		c.name,
		c.item_value0,
		'materials'
	from sdocs_mfr_contents c
		join @result r on r.mfr_doc_id = c.mfr_doc_id and r.product_id = c.product_id and c.parent_id = r.child_id and r.slice = 'items'
	where c.is_buy = 1

-- resources
	insert into @result(
		mfr_doc_id, product_id,
		content_id, item_id, oper_id, group1_name, resource_id, material_or_resource_name, cost_plan,
		slice
		)
	select
		r.mfr_doc_id,
		r.product_id,
		r.content_id,
		r.item_id,
		r.oper_id,
		'Ресурсы',
		dr.resource_id,
		rs.name,
		dr.loading_value,
		'resources'
	from sdocs_mfr_drafts_opers do
		join @result r on r.draft_id = do.draft_id and r.oper_number = do.number and r.slice = 'items'
		join sdocs_mfr_drafts_opers_resources dr on dr.oper_id = do.oper_id
			join mfr_resources rs on rs.resource_id = dr.resource_id

	update x set group2_name = ca.note
	from @result x
		join sdocs_mfr_contents_attrs ca on ca.content_id = x.material_content_id and ca.attr_id = @materal_group_attr_id

	update x set group2_name = r.name
	from @result x
		join mfr_resources r on r.resource_id = x.resource_id

	update x set unit_name = xx.unit_name
	from @result x
		join @result xx on xx.content_id = x.content_id and xx.slice = 'Items'

	select 
		PlanName = pln.number,
		MfrNumber = sd.number,
		ItemName = p.name,
		OperName = o.name,
		Group1Name = isnull(x.group1_name, '-'),
		Group2Name = isnull(x.group2_name, '-'),
		MaterialOrResourceName = x.material_or_resource_name,
		UnitName = x.unit_name,
		ItemQuantity = x.q_brutto_product,
		CostPlan = x.cost_plan,
		MfrDocHid = concat('#', x.mfr_doc_id),
		ContentHid = concat('#', x.content_id)
	from @result x
		left join sdocs sd on sd.doc_id = x.mfr_doc_id
			left join mfr_plans pln on pln.plan_id = sd.plan_id
		left join products p on p.product_id = x.item_id
		left join sdocs_mfr_opers o on o.oper_id = x.oper_id		

end
GO
