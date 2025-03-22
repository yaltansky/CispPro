if object_id('mfr_items_prices_calc') is not null drop proc mfr_items_prices_calc
go
create proc mfr_items_prices_calc
	@inforce bit = 0
as
begin

	set nocount on;	

	declare @d_calc datetime = isnull((select top 1 d_calc from mfr_items_prices), '1900-01-01')
	if @inforce = 0 and datediff(minute, @d_calc, getdate()) <= 60
	begin
		print 'Register MFR_ITEMS_PRICES is actual. No calculation nedeed.'
		return -- not expired
	end

	exec mfr_replicate_prices
end
go
