if object_id('week_start') is not null drop function week_start
GO
create function week_start(@date datetime) returns date
as
begin
    set @date = cast(@date as date)
    return 
        dateadd(d, 
            case
                when datepart(weekday, @date) = 1 then -6
                else -(datepart(weekday, @date) - 2)
            end,
        @date)    
end
go
