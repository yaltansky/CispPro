if object_id('date2mmmyyyy') is not null drop function date2mmmyyyy
GO
CREATE function [date2mmmyyyy](@date datetime)
returns varchar(16)
as
begin
	
	return cast(
			case datepart(m, @date)
				when 1 then 'январь'
				when 2  then 'февраль'
				when 3  then 'март'
				when 4  then 'апрель'
				when 5  then 'май'
				when 6  then 'июнь'
				when 7  then 'июль'
				when 8  then 'август'
				when 9  then 'сентябрь'
				when 10 then 'октябрь'
				when 11 then 'ноябрь'
				when 12 then 'декабрь'
			end
			+ ' '
			+ cast(datepart(yyyy, @date) as char(4))
			+ ' г'
			as varchar(16))

end


GO
