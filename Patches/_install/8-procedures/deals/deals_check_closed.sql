if object_id('deals_check_closed') is not null drop procedure deals_check_closed
go
-- exec deals_check_closed 700, 9884
create proc deals_check_closed
	@mol_id int,
	@folder_id int
as
begin
	
	set nocount on;

	declare @article_id int = 24

-- @ids
	declare @ids as app_pkids; insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'dl'

-- Cпециальный счёт
	declare @subject_id int = (select top 1 subject_id from deals where deal_id in (select id from @ids))
	declare @nds_account_id int; exec get_nds_account_id @subject_id, @nds_account_id out	

-- @buffer_id
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	delete from objs_folders_details where folder_id = @buffer_id

-- check
	declare @err_deals app_pkids
		insert into @err_deals
		select distinct d.deal_id from findocs# f
			join (
				select d.deal_id, d.budget_id, d.customer_id
				from deals d
					join @ids i on i.id = d.deal_id
			) d on d.budget_id = f.budget_id
		where f.value_ccy > 0
			and f.agent_id != d.customer_id

	if exists(select 1 from @err_deals)
	begin
		raiserror('В буфере находятся сделки, в которых есть несоответствия контрагентов в сделках и оплатах.', 16, 1)
		insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
		select @buffer_id, 'dl', id, 0 from @err_deals
		return
	end

	;with x_deals as (
		select x.deal_id, sum(x.value_bds) as value_plan
		from deals_budgets x
			join @ids i on i.id = x.deal_id
		where article_id = @article_id
		group by deal_id
		)
	, x_fact as (
		select d.deal_id, cast(sum(ff.value_rur) as decimal(18,2)) as value_fact
		from findocs# ff
			join deals d on d.budget_id = ff.budget_id
			join x_deals xd on xd.deal_id = d.deal_id
		where ff.article_id = @article_id
			and ff.account_id <> @nds_account_id
		group by d.deal_id
		)
	insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
	select @buffer_id, 'DL', d.deal_id, @mol_id
	from x_deals d
		join x_fact f on f.deal_id = d.deal_id
	where abs(d.value_plan - f.value_fact) <= 1.00

	update x
	set d_closed = f.max_d_doc
	from deals x
		join objs_folders_details fd on fd.folder_id = @buffer_id and fd.obj_type = 'dl' and fd.obj_id = x.deal_id
		join (
			select deals.deal_id, max(f.d_doc) as max_d_doc
			from findocs# f
				join deals on deals.budget_id = f.budget_id
			where f.article_id = 24
			group by deals.deal_id
		) f on f.deal_id = x.deal_id

-- Сформировать операции по возмещению НДС
	declare @closed table(
		deal_id int primary key, budget_id int, article_id int, value_nds decimal(18,2),
		findoc_id int
		)
	insert into @closed(deal_id, budget_id, article_id, value_nds)
	select db.deal_id, d.budget_id, max(db.article_id), sum(db.value_nds)
	from deals_budgets db
		join deals d on d.deal_id = db.deal_id
		join objs_folders_details fd on fd.folder_id = @buffer_id and fd.obj_type = 'dl' and fd.obj_id = db.deal_id
		join bdr_articles a on a.article_id = db.article_id and a.short_name = 'НДС'
	where db.value_nds > 0
	group by
		db.deal_id, d.budget_id

	update c
	set findoc_id = f.findoc_id
	from @closed c
		join findocs# f on f.budget_id = c.budget_id
	where f.account_id = @nds_account_id

BEGIN TRY
BEGIN TRANSACTION

	declare @seed_findocs int = (select max(findoc_id) from findocs)

	if exists(select 1 from @closed)
	begin
		delete x from findocs x
			join @closed c on c.budget_id = x.budget_id and x.account_id = @nds_account_id

		insert into findocs(
			findoc_id, d_doc, subject_id, account_id, number, budget_id, article_id, ccy_id, value_ccy, value_rur, note
			)
		select
			isnull(c.findoc_id, cc.findoc_id), -- если оплата по сделке была сформирована, то её FINDOC_ID не меняется
			d.d_closed,
			@subject_id,
			@nds_account_id,
			d.number,
			d.budget_id,
			c.article_id,
			'RUR',
			c.value_nds,
			c.value_nds,
			'НДС к возмещению'
		from deals d
			join @closed c on c.deal_id = d.deal_id
				left join (
					select deal_id, @seed_findocs + (row_number() over (order by deal_id)) as findoc_id
					from @closed
					where findoc_id is null
				) cc on cc.deal_id = d.deal_id		
	end

COMMIT TRANSACTION
END TRY

BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION	
	exec sys_set_triggers 1
	declare @err varchar(max) = error_message()
	raiserror (@err, 16, 1)
END CATCH

end
go
