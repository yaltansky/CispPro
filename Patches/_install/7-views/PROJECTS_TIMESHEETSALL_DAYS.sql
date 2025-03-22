IF OBJECT_ID('PROJECTS_TIMESHEETSALL_DAYS') IS NOT NULL DROP VIEW PROJECTS_TIMESHEETSALL_DAYS
GO
CREATE VIEW PROJECTS_TIMESHEETSALL_DAYS AS
SELECT
    X.ID,
    X.TIMESHEET_ID,
    SHEET.PROJECT_ID,
    PROJECT_NAME = P.NAME,
	P.CURATOR_ID,
	P.CHIEF_ID,
	P.ADMIN_ID,
    SHEET.TASK_ID,
    TASK_NAME = SHEET.NAME,
    EV.EVENT_ID,
    EVENT_NAME = EV.NAME,
    SHEET.MOL_ID,
    MOL_NAME = MOLS.NAME,
    X.D_DOC,
	SHEET.D_DEADLINE,
    SHEET.SUM_PLAN_H,
	SHEET.SUM_FACT_H,
	X.PLAN_H,
	X.FACT_H,
    X.NOTE,
    SHEET.TALK_ID,
	SHEET.IS_CLOSED,
	SHEET.IS_DELETED,
	X.FIXED_DATE,
	FIXED_MOL_NAME = M2.NAME
FROM PROJECTS_TIMESHEETS_DAYS X
	JOIN PROJECTS_TIMESHEETS SHEET ON SHEET.TIMESHEET_ID = X.TIMESHEET_ID 
		JOIN PROJECTS P ON P.PROJECT_ID = SHEET.PROJECT_ID
		JOIN MOLS ON MOLS.MOL_ID = SHEET.MOL_ID
	LEFT JOIN PROJECTS_TIMESHEETS_EVENTS EV ON EV.EVENT_ID = X.EVENT_ID
	LEFT JOIN MOLS M2 ON M2.MOL_ID = X.FIXED_MOL_ID
GO

create trigger tu_projects_timesheetsall_days on PROJECTS_TIMESHEETSALL_DAYS
instead of update
as
begin
	
	set nocount on ;

	if update(task_name)
		update x set name = i.task_name
		from projects_timesheets x
			join inserted i on i.timesheet_id = x.timesheet_id

	if update(is_closed)
		update x set is_closed = i.is_closed
		from projects_timesheets x
			join inserted i on i.timesheet_id = x.timesheet_id

	if update(d_doc) or update(event_id) or update(fact_h) or update(note)
		update x
		set d_doc = i.d_doc, 
			event_id = i.event_id, 
			fact_h = i.fact_h,
			note = i.note
		from projects_timesheets_days x
			join inserted i on i.id = x.id

	if update(is_deleted)
		delete projects_timesheets_days
		where id in (select id from inserted where is_deleted = 1)
end
GO
