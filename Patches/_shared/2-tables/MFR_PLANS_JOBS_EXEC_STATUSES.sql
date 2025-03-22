USE CISP_SHARED
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'MFR_PLANS_JOBS_EXEC_STATUSES') AND type in (N'U'))
BEGIN
CREATE TABLE MFR_PLANS_JOBS_EXEC_STATUSES(
	STATUS_ID int PRIMARY KEY CLUSTERED,
	NAME varchar(50),
	CSS varchar(50),
	STYLE varchar(50),
	SORT_ID int
)
END
GO

IF NOT EXISTS(SELECT 1 FROM MFR_PLANS_JOBS_EXEC_STATUSES)
BEGIN
    INSERT INTO MFR_PLANS_JOBS_EXEC_STATUSES(STATUS_ID, NAME, CSS, STYLE, SORT_ID) VALUES 
    (-1, 'Не выполнено', 'fa fa-remove text-error', null, 1),
    (0, 'Назначено', 'fa fa-bolt text-warning', null, 2),
    (10, 'Выполнено', 'fa fa-check text-success', null, 3),
    (100, 'Закрыто', 'fa fa-lock text-muted text-bold', null, 4);
END
GO
