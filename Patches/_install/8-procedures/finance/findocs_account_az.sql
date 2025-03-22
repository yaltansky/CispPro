if object_id('findocs_account_az') is not null drop procedure findocs_account_az
go
create procedure findocs_account_az
	@id int
as
begin

	set nocount on;

	declare @account_id int = (select account_id from findocs_accounts_az where id = @id);
	declare @value_0 decimal(18,2) = isnull((select saldo_in from findocs_accounts where account_id = @account_id), 0);
	declare @d_from datetime, @d_to datetime

	select 
		@d_from = isnull(d_from, (select max(d_doc) from findocs where account_id = @account_id and status_id >= 0)),
		@d_to = isnull(d_to, @d_from)
	from findocs_accounts_az where id = @id

	declare @value_start decimal(18,2), @value_in decimal(18,2), @value_out decimal(18,2)

	update findocs_accounts_az
	set @value_start = @value_0 + isnull(
			(select sum(value_ccy) from findocs where account_id = @account_id and d_doc < @d_from and status_id >= 0)
			,0),
		@value_in = isnull(
			(select sum(value_ccy) from findocs where account_id = @account_id and d_doc between @d_from and @d_to and value_ccy > 0 and status_id >= 0)
			,0),
		@value_out = isnull(
			(select sum(value_ccy) from findocs where account_id = @account_id and d_doc between @d_from and @d_to and value_ccy < 0 and status_id >= 0)
			,0),
		d_from = @d_from,
		d_to = @d_to,
		value_start = @value_start,
		value_in = @value_in,
		value_out = @value_out,
		value_end = @value_start + @value_in + @value_out
	where id = @id
end
go
