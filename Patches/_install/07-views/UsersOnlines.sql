/****** Object:  View [UsersOnlines]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[UsersOnlines]'))
EXEC dbo.sp_executesql @statement = N'
CREATE VIEW [UsersOnlines]
AS

select
	Id = m.MOL_ID,
	Surname = m.SURNAME,
	Name1 = m.NAME1,
	Name2 = m.NAME2,
	Email = m.EMAIL,
	u.StatusId,
	StatusName = case u.StatusId
		when 1 then ''Онлайн''
		when 2 then ''Офлайн''
		when 3 then ''Сегодня''
		when 4 then ''Давно''
		when 100 then ''Не заходил(а)''
		else ''Не зарегистрирован''
	end
from mols m
	left join users u on u.id = m.mol_id
where m.is_working = 1
' 
GO
