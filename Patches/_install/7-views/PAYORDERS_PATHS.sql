IF OBJECT_ID('PAYORDERS_PATHS') IS NOT NULL DROP VIEW PAYORDERS_PATHS
GO
CREATE VIEW PAYORDERS_PATHS AS
	SELECT TOP 100 PERCENT CAST(ID AS INT) AS PATH_ID, NAME
	FROM OPTIONS_LISTS
	WHERE L_GROUP = 'PAYORDERPATHS'
	ORDER BY NAME
GO

delete from options_lists where l_group = 'PayorderPaths'
insert into options_lists(l_group, id, name) values
('PayorderPaths', 1, 'МС'),
('PayorderPaths', 2, 'МС > Русэлпром'),
('PayorderPaths', 3, 'МС > Русэлпром > Ресурс'),
('PayorderPaths', 4, 'МС > Русэлпром > Русэлпром-ЛЭЗ'),
('PayorderPaths', 5, 'МС > Русэлпром > РуЭМ'),
('PayorderPaths', 6, 'МС > Русэлпром > Техснаб'),
('PayorderPaths', 7, 'Ресурс'),
('PayorderPaths', 8, 'Русэлпром'),
('PayorderPaths', 9, 'Русэлпром > ВЭМЗ'),
('PayorderPaths', 10, 'Русэлпром > МС'),
('PayorderPaths', 11, 'Русэлпром > НИПТИЭМ'),
('PayorderPaths', 12, 'Русэлпром > НПО ЛЭЗ'),
('PayorderPaths', 13, 'Русэлпром > Ресурс'),
('PayorderPaths', 14, 'Русэлпром > Русэлпром-ЛЭЗ'),
('PayorderPaths', 15, 'Русэлпром > РуЭМ'),
('PayorderPaths', 16, 'Русэлпром > СЭЗ'),
('PayorderPaths', 17, 'Русэлпром > ТД'),
('PayorderPaths', 18, 'Русэлпром > Техснаб'),
('PayorderPaths', 19, 'Русэлпром > ЭМ'),
('PayorderPaths', 20, 'ТД'),
('PayorderPaths', 21, 'ТД > МС'),
('PayorderPaths', 22, 'ТД > МС > Русэлпром'),
('PayorderPaths', 23, 'ТД > МС > Русэлпром > Техснаб'),
('PayorderPaths', 24, 'ТД > Русэлпром'),
('PayorderPaths', 25, 'ТД > Русэлпром > НПО ЛЭЗ'),
('PayorderPaths', 26, 'ТД > Русэлпром > Ресурс'),
('PayorderPaths', 27, 'ТД > Русэлпром > Русэлпром-ЛЭЗ'),
('PayorderPaths', 28, 'ТД > Русэлпром > РуЭМ'),
('PayorderPaths', 29, 'ТД > Русэлпром > Техснаб'),
('PayorderPaths', 30, 'Техснаб'),
('PayorderPaths', 31, 'ЭМ'),
('PayorderPaths', 32, 'ЭМ > Русэлпром'),
('PayorderPaths', 33, 'ЭМ > Русэлпром > ВЭМЗ'),
('PayorderPaths', 34, 'ЭМ > Русэлпром > НИПТИЭМ'),
('PayorderPaths', 35, 'ЭМ > Русэлпром > НПО ЛЭЗ'),
('PayorderPaths', 36, 'ЭМ > Русэлпром > Ресурс'),
('PayorderPaths', 37, 'ЭМ > Русэлпром > Русэлпром-ЛЭЗ'),
('PayorderPaths', 38, 'ЭМ > Русэлпром > РуЭМ'),
('PayorderPaths', 39, 'ЭМ > Русэлпром > СЭЗ'),
('PayorderPaths', 40, 'ЭМ > Русэлпром > Техснаб'),
('PayorderPaths', 41, 'ЭМ > РуЭМ > Техснаб'),
('PayorderPaths', 42, 'Менеджмент'),
('PayorderPaths', 43, 'Менеджмент > Техснаб'),
('PayorderPaths', 44, 'Менеджмент > Русэлпром-ЛЭЗ')
GO
