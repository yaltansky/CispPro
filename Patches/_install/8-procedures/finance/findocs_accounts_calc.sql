if object_id('findocs_accounts_calc') is not null drop proc findocs_accounts_calc
GO
create procedure findocs_accounts_calc
	@mol_id int = null,
	@account_id int = null, -- id
	@account_ids varchar(max) = null -- or: acc1, acc2, acc3 ...
as
begin

	set nocount on;

	declare @accounts as app_pkids

	if isnull(@account_id,0) <> 0
		insert into @accounts select @account_id
	else if @account_ids is not null
		insert into @accounts select distinct item from dbo.str2rows(@account_ids, ',') where item is not null
	else 
		insert into @accounts select account_id from findocs_accounts

	exec findocs_accounts_calc;2 @accounts = @accounts
	
	if isnull(@account_id,0) = 0 
	begin
		exec tree_calc_nodes 'findocs_accounts', 'account_id', @sortable = 0
		update findocs_accounts set ccy_id = '' 	where has_childs = 1
	end
end
go

create procedure findocs_accounts_calc;2
	@accounts as app_pkids readonly
as
begin

	set nocount on;

-- delete rows marked as deleted
    delete from findocs where status_id = -1

-- refresh ccy_rates
	exec ccy_rates_calc

-- update last_xxx
	update a
	set saldo_out = isnull(a.saldo_in,0) + isnull(asum.value_ccy,0),
		last_d_doc = asum.d_doc,
		last_d_upload = u.d_upload,
		last_upload_id = u.upload_id
	from findocs_accounts a
		join @accounts ids on ids.id = a.account_id
		left join (
			select fd.account_id, sum(fd.value_ccy) as value_ccy, max(d_doc) as d_doc
			from findocs fd
            where status_id >= 0
			group by fd.account_id
		) asum on asum.account_id = a.account_id
		left join (
			select account_id, max(add_date) as d_upload, max(upload_id) as upload_id
			from findocs_uploads
			group by account_id
		) u on u.account_id = a.account_id

end
go