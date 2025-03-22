if object_id('mfr_doc_change_parts') is not null drop proc mfr_doc_change_parts
go
create proc mfr_doc_change_parts
	@mol_id int,
	@doc_id int,
	@product_id int,
	@parts_xml xml
as
begin

	set nocount on;

	-- @parts
		declare @handle_xml int; exec sp_xml_preparedocument @handle_xml output, @parts_xml
		declare @parts table(
			id int identity primary key,
			doc_id int,
			product_id int,
			part_number int,
			part_doc_id int,
			part_quantity float,
			q_ratio float,
			is_deleted bit
			)
		insert into @parts(doc_id, product_id, part_number, part_doc_id, part_quantity, is_deleted)
		select * from openxml (@handle_xml, '*/MfrDocPart', 2) with (
			DOC_ID int,
			PRODUCT_ID int,
			PART_NUMBER int,
			PART_DOC_ID int,
			PART_QUANTITY float,
			IS_DELETED bit
			)
		exec sp_xml_removedocument @handle_xml

		update x set q_ratio = part_quantity / nullif(p.quantity,0)
		from @parts x
			join sdocs_products p on p.doc_id = x.doc_id and p.product_id = x.product_id

	declare @seed int = (select max(doc_id) from sdocs)

	update x set part_doc_id = @seed + xx.row_id
	from @parts x
		join (
			select id, row_id = row_number() over (order by part_number)
			from @parts
			where isnull(part_doc_id,0) = 0
		) xx on xx.id = x.id

BEGIN TRY
BEGIN TRANSACTION

	declare @part_prefix int = isnull((
			select row_num
			from (
				select doc_id, x.product_id, row_num = row_number() over (order by p.name)
				from sdocs_products x
					join products p on p.product_id = x.product_id
				where x.doc_id = @doc_id
			) xx
			where xx.product_id = @product_id
		), 1)

	-- sdocs
		delete from sdocs where doc_id in (select part_doc_id from @parts)
		delete from sdocs_mfr_milestones where doc_id in (select part_doc_id from @parts)
		delete from @parts where is_deleted = 1 or isnull(part_quantity,0) <= 0

		SET IDENTITY_INSERT SDOCS ON
			insert into sdocs(
				part_parent_id, type_id, plan_id, doc_id, priority_id, d_doc, number, status_id, subject_id, agent_id, d_delivery, d_ship, d_issue_plan, d_issue_forecast, d_issue, ccy_id, value_ccy, add_date, add_mol_id
				)
			select
				@doc_id, type_id, plan_id, n.part_doc_id, priority_id, d_doc, 
				concat(number, '/', @part_prefix, '.', part_number),
				status_id, subject_id, agent_id, d_delivery, d_ship, d_issue_plan, d_issue_forecast, d_issue, ccy_id, value_ccy,
				getdate(), @mol_id
			from sdocs x,
				(select part_doc_id, part_number from @parts) n
			where doc_id = @doc_id			
		SET IDENTITY_INSERT SDOCS OFF

		update sdocs set part_has_childs = 1 where doc_id = @doc_id

	-- sdocs_products
		insert into sdocs_products(
			doc_id, product_id, quantity, unit_id, price, price_pure, price_pure_trf, price_list, nds_ratio, value_pure, value_nds, value_ccy, value_rur, value_work
			)
		select 
			part_doc_id, n.product_id, part_quantity, unit_id, price, price_pure, price_pure_trf, price_list, nds_ratio,
			value_pure * q_ratio, value_nds * q_ratio, value_ccy * q_ratio, value_rur * q_ratio, value_work * q_ratio
		from sdocs_products x
			join @parts n on n.doc_id = x.doc_id and n.product_id = x.product_id

	-- sdocs_mfr_milestones
		insert into sdocs_mfr_milestones(
			doc_id, product_id, attr_id, ratio, ratio_value, d_to, d_to_plan, d_to_predict, date_lag, d_to_plan_auto, d_to_plan_hand
			)
		select
			n.part_doc_id, n.product_id, attr_id, ratio, 
			ratio_value * n.q_ratio,
			d_to, d_to_plan, d_to_predict, date_lag, d_to_plan_auto, d_to_plan_hand
		from sdocs_mfr_milestones x
			join @parts n on n.doc_id = x.doc_id and n.product_id = x.product_id

	-- sdocs_mfr_parts
		delete from sdocs_mfr_parts where doc_id = @doc_id and product_id = @product_id

		insert into sdocs_mfr_parts(doc_id, product_id, part_number, part_doc_id, part_quantity)
		select doc_id, product_id, part_number, part_doc_id, part_quantity
		from @parts

	-- re-order content of parent
		exec mfr_doc_change_parts;2 @mol_id = @mol_id, @doc_id = @doc_id, @product_id = @product_id
COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
	declare @err varchar(max); set @err = error_message()
	raiserror (@err, 16, 3)
END CATCH -- TRANSACTION

end
go
-- helper: re-order content of parent
create proc mfr_doc_change_parts;2
	@mol_id int,
	@doc_id int,
	@product_id int
as
begin

	-- -- purge parent content, opers
	-- 	delete from sdocs_mfr_opers where content_id in (
	-- 		select content_id from sdocs_mfr_contents where mfr_doc_id = @doc_id and product_id = @product_id
	-- 		)
	-- 	delete from sdocs_mfr_contents where mfr_doc_id = @doc_id and product_id = @product_id

	-- calc contents
		declare @docs as app_pkids; insert into @docs select part_doc_id from sdocs_mfr_parts where doc_id = @doc_id and product_id = @product_id
		exec mfr_drafts_calc @mol_id = @mol_id, @docs = @docs		
end
go

/*
delete from sdocs where number like '120501-029рл%' and type_id = 5 and doc_id > 1676397
delete from sdocs_mfr_milestones where doc_id >= 12007660

exec mfr_doc_change_parts 1000, 1676397, 36273, 
	'
	<ArrayOfMfrDocPart xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
		<MfrDocPart>
			<ID>0</ID>
			<DOC_ID>1676397</DOC_ID>
			<PRODUCT_ID>36273</PRODUCT_ID>
			<PART_NUMBER>1</PART_NUMBER>
			<PART_DOC_ID xsi:nil="true" />
			<PART_QUANTITY>2</PART_QUANTITY>
			<IS_DELETED>false</IS_DELETED>
		</MfrDocPart>
		<MfrDocPart>
			<ID>0</ID>
			<DOC_ID>1676397</DOC_ID>
			<PRODUCT_ID>36273</PRODUCT_ID>
			<PART_NUMBER>2</PART_NUMBER>
			<PART_DOC_ID xsi:nil="true" />
			<PART_QUANTITY>8</PART_QUANTITY>
			<IS_DELETED>false</IS_DELETED>
		</MfrDocPart>
	</ArrayOfMfrDocPart>'

select * from mfr_sdocs where part_has_childs = 1
select * from mfr_sdocs where part_parent_id is not null	
*/
