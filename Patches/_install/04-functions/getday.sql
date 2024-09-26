if object_id('getday') is not null drop function getday
go
CREATE function [getday](@datetime as datetime)
    returns datetime
as
begin
    return cast(floor(cast(@datetime as float)) as datetime)
end
GO
