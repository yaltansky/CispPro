if object_id('mfr_docs_trf_turns') is not null drop proc mfr_docs_trf_turns
go
-- exec mfr_docs_trf_turns 1000, @d_from = '2021-12-01'
create proc mfr_docs_trf_turns
	@mol_id int,
	@d_from date = null,
	@d_to date = null,
	@product_id int = null
as
begin

	set nocount on;

	set @d_from = isnull(@d_from, '1900-01-01')
	set @d_to = isnull(@d_to, dbo.today())

	-- tables
		declare @data table(
			subject_id int,
			place_id int,
			product_id int,
			doc_id int,
			d_doc date,
			number varchar(50),
			unit_name varchar(20),
			quantity float,
			index ix_group(subject_id, place_id, product_id)
		)	

		declare @turn table(
			subject_id int,
			place_id int,
			product_id int,
			doc_id int,
			d_doc date,
			number varchar(50),
			unit_name varchar(20),
			q_start float,
			q_input float,
			q_output float,
			q_end float
		)	

	-- подготовка данных
		-- приходы на PLACE_ID
			insert into @data(subject_id, place_id, product_id, doc_id, d_doc, number, quantity, unit_name)
			select isnull(pl.subject_id, sd.subject_id), pl.place_id, sp.product_id, sp.doc_id, sd.d_doc, sd.number, sp.quantity, isnull(u.name, '-')
			from sdocs_products sp
				join sdocs sd on sd.doc_id = sp.doc_id
				left join mfr_places pl on pl.place_id = sd.place_id
				left join products_units u on u.unit_id = sp.unit_id
			where type_id = 9
				and sd.status_id >= 0
				and (@product_id is null or sp.product_id = @product_id)

		-- поступления на PLACE_TO_ID
			insert into @data(subject_id, place_id, product_id, doc_id, d_doc, number, quantity, unit_name)
			select pl.subject_id, pl.place_id, sp.product_id, sp.doc_id, sd.d_doc, sd.number, sp.quantity, isnull(u.name, '-')
			from sdocs_products sp
				join sdocs sd on sd.doc_id = sp.doc_id
				join mfr_places pl on pl.place_id = sd.place_to_id
				left join products_units u on u.unit_id = sp.unit_id
			where type_id in (10, 12)
				and sd.status_id >= 0
				and (@product_id is null or sp.product_id = @product_id)

		-- расходы с PLACE_ID
			insert into @data(subject_id, place_id, product_id, doc_id, d_doc, number, quantity, unit_name)
			select pl.subject_id, pl.place_id, sp.product_id, sp.doc_id, sd.d_doc, sd.number, -sp.quantity, isnull(u.name, '-')
			from sdocs_products sp
				join sdocs sd on sd.doc_id = sp.doc_id
				join mfr_places pl on pl.place_id = sd.place_id
				left join products_units u on u.unit_id = sp.unit_id
			where type_id in (10, 12)
				and sd.status_id >= 0
				and (@product_id is null or sp.product_id = @product_id)

	-- входящий остаток
		insert into @turn(subject_id, place_id, product_id, d_doc, number, q_start, unit_name)
		select
			subject_id,
			place_id,
			product_id,
			d_doc = @d_from,
			number = 'ВхОстаток',		
			sum(quantity),
			max(unit_name)
		from @data
		where d_doc < @d_from
		group by subject_id, place_id, product_id

	-- обороты
		insert into @turn(subject_id, place_id, product_id, doc_id, d_doc, number, q_input, q_output, unit_name)
		select
			subject_id,
			place_id,
			product_id,
			doc_id,
			d_doc,
			number,
			case when quantity > 0 then quantity end,
			case when quantity < 0 then -quantity end,
			unit_name
		from @data
		where d_doc between @d_from and @d_to

	-- исходящий остаток
		insert into @turn(subject_id, place_id, product_id, d_doc, number, q_end, unit_name)
		select
			subject_id,
			place_id,
			product_id,
			d_doc = @d_from,
			number = 'ИсхОстаток',		
			sum(quantity),
			max(unit_name)
		from @data
		group by subject_id, place_id, product_id

	-- select
		select 
			SUBJECT_NAME = S.SHORT_NAME,
			PLACE_NAME = ISNULL(PL.FULL_NAME, '-'),
			PRODUCT_GROUP1_NAME = PG1.NAME,
			PRODUCT_GROUP2_NAME = PG2.NAME,
			PRODUCT_NAME = P.NAME,		
			X.DOC_ID,
			X.D_DOC,
			X.NUMBER,
			UNIT_NAME = LOWER(LTRIM(X.UNIT_NAME)),
			X.Q_START,
			X.Q_INPUT,
			X.Q_OUTPUT,
			X.Q_END
		from @turn x
			join subjects s on s.subject_id = x.subject_id
			left join mfr_places pl on pl.place_id = x.place_id
			join products p on p.product_id = x.product_id
			left join v_products_groups pg1 on pg1.product_id = x.product_id
			left join v_products_subgroups pg2 on pg2.product_id = x.product_id
		where isnull(x.q_start,0) <> 0
			or isnull(x.q_input,0) <> 0
			or isnull(x.q_output,0) <> 0
			or isnull(x.q_end,0) <> 0

end
go
