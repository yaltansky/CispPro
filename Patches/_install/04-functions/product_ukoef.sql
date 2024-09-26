if object_id('product_ukoef') is not null drop function product_ukoef
GO
create function [product_ukoef](@unit_from varchar(20), @unit_to varchar(20))
returns float
as
begin

	return
		case
			when @unit_from = 'т' and @unit_to = 'кг' then 1000
			when @unit_from = 'кг' and @unit_to = 'т' then 0.001
			else 1.0
		end

end
GO
