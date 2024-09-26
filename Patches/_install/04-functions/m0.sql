if object_id('m0') is not null drop function m0
go
-- select m0(null)
create function [m0] (@x float) returns float as
begin
  return (@x * sign(@x + abs(@x)))
end
GO
